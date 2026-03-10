#!/usr/bin/env bash
#
# pam-ssh-agent-sudo.sh - Enable sudo authentication via SSH agent
#
# Builds and installs pam_ssh_agent_auth on macOS, allowing passwordless sudo
# when connected via SSH with agent forwarding.
#
# Requirements:
#   - macOS with Xcode command line tools
#   - OpenSSL (via MacPorts at /opt/local)
#   - SSH agent forwarding enabled
#
# Usage:
#   ./pam-ssh-agent-sudo.sh           # Build and install
#   ./pam-ssh-agent-sudo.sh uninstall # Remove
#
# After installation, connect with: ssh -A hostname
# Then sudo will authenticate via your SSH agent keys.
#
# Note: Your SSH public key must be in ~/.ssh/authorized_keys on the target.
# If using Tailscale SSH, add the Tailscale ECDSA key (ssh-add -L shows it).
#

set -e

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

VERSION="0.10.3"
BUILD_DIR="/tmp/pam_ssh_agent_auth-build"
INSTALL_DIR="/usr/local/lib/pam"
PAM_MODULE="pam_ssh_agent_auth.so"

check_requirements() {
    log_info "Checking requirements..."

    if ! is_macos; then
        log_error "This script is for macOS only"
        exit 0
    fi

    if ! xcode-select -p &>/dev/null; then
        log_error "Xcode command line tools not installed"
        echo "  Run: xcode-select --install"
        exit 1
    fi

    if [[ ! -d "/opt/local/lib" ]] || [[ ! -f "/opt/local/lib/libssl.dylib" ]]; then
        log_error "OpenSSL not found at /opt/local (MacPorts)"
        echo "  Install with: sudo port install openssl"
        exit 1
    fi

    log_success "Requirements satisfied"
}

download_source() {
    log_info "Downloading pam_ssh_agent_auth v${VERSION}..."

    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    curl -sL "https://sourceforge.net/projects/pamsshagentauth/files/pam_ssh_agent_auth/v${VERSION}/pam_ssh_agent_auth-${VERSION}.tar.bz2/download" \
        -o pam_ssh_agent_auth.tar.bz2

    tar xjf pam_ssh_agent_auth.tar.bz2
    cd "pam_ssh_agent_auth-${VERSION}"

    log_success "Source downloaded and extracted"
}

apply_patches() {
    log_info "Applying Debian compatibility patches..."

    local patches=(
        "0001-authfd.c-check-return-value-of-seteuid-2"
        "openssl-1.1.1-1"
        "openssl-1.1.1-2"
        "0002-fix-segfault-when-using-ECDSA-keys"
        "fix-configure"
        "1000-clean-ed25519"
        "fingerprint_sha256"
        "1000-gcc-14"
    )

    for patch in "${patches[@]}"; do
        curl -sL "https://sources.debian.org/data/main/p/pam-ssh-agent-auth/${VERSION}-11/debian/patches/${patch}.patch" \
            | patch -p1 -s || log_warn "Patch ${patch} may have partially applied"
    done

    # Add explicit_bzero for macOS (not available in system libraries)
    cat >> openbsd-compat/bsd-misc.c << 'EOF'

/* explicit_bzero for macOS - prevents compiler from optimising out security-critical memset */
#if !defined(HAVE_EXPLICIT_BZERO)
void explicit_bzero(void *buf, size_t len) {
    memset(buf, 0, len);
    asm volatile("" : : "r"(buf) : "memory");
}
#endif
EOF

    log_success "Patches applied"
}

build_module() {
    log_info "Building PAM module..."

    CFLAGS="-Wno-implicit-function-declaration -Wno-int-conversion -I/opt/local/include -D_FORTIFY_SOURCE=0" \
    LDFLAGS="-L/opt/local/lib" \
    ./configure --without-openssl-header-check >/dev/null 2>&1

    make clean >/dev/null 2>&1 || true
    make >/dev/null 2>&1

    if [[ ! -f "${PAM_MODULE}" ]]; then
        log_error "Build failed - ${PAM_MODULE} not created"
        exit 1
    fi

    log_success "PAM module built successfully"
}

install_module() {
    log_info "Installing PAM module..."

    sudo mkdir -p "${INSTALL_DIR}"
    sudo cp "${PAM_MODULE}" "${INSTALL_DIR}/"
    sudo chmod 755 "${INSTALL_DIR}/${PAM_MODULE}"

    log_success "PAM module installed to ${INSTALL_DIR}/${PAM_MODULE}"
}

configure_sudoers() {
    log_info "Configuring sudoers..."

    if sudo grep -q "SSH_AUTH_SOCK" /etc/sudoers 2>/dev/null; then
        log_success "SSH_AUTH_SOCK already in sudoers"
    else
        echo 'Defaults    env_keep += "SSH_AUTH_SOCK"' | sudo EDITOR='tee -a' visudo >/dev/null
        log_success "Added SSH_AUTH_SOCK to sudoers env_keep"
    fi
}

configure_pam() {
    log_info "Configuring PAM for sudo..."

    local pam_file="/etc/pam.d/sudo"
    local pam_line="auth       sufficient     pam_ssh_agent_auth.so file=~/.ssh/authorized_keys"

    if sudo grep -q "pam_ssh_agent_auth" "${pam_file}" 2>/dev/null; then
        log_success "PAM already configured"
    else
        # Insert after the first comment line
        sudo sed -i.bak "s|^# sudo: auth account password session|# sudo: auth account password session\\
${pam_line}|" "${pam_file}"
        sudo rm -f "${pam_file}.bak"
        log_success "PAM configured for ssh-agent auth"
    fi
}

show_summary() {
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}   pam_ssh_agent_auth Installation Complete${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
    echo "To use passwordless sudo via SSH agent:"
    echo ""
    echo "  1. Ensure your public key is in ~/.ssh/authorized_keys on this machine"
    echo "  2. Connect with agent forwarding: ssh -A $(hostname)"
    echo "  3. Run sudo - it will authenticate via your SSH agent"
    echo ""
    echo "If using Tailscale SSH:"
    echo "  - Tailscale provides its own SSH agent with an ECDSA key"
    echo "  - Add it to authorized_keys: ssh-add -L >> ~/.ssh/authorized_keys"
    echo ""
    echo "Troubleshooting:"
    echo "  - Check agent keys: ssh-add -l"
    echo "  - Check authorized_keys: cat ~/.ssh/authorized_keys"
    echo "  - Verify SSH_AUTH_SOCK is set: echo \$SSH_AUTH_SOCK"
    echo ""
}

uninstall() {
    log_info "Uninstalling pam_ssh_agent_auth..."

    # Remove PAM config
    if sudo grep -q "pam_ssh_agent_auth" /etc/pam.d/sudo 2>/dev/null; then
        sudo sed -i.bak '/pam_ssh_agent_auth/d' /etc/pam.d/sudo
        sudo rm -f /etc/pam.d/sudo.bak
        log_success "Removed PAM configuration"
    fi

    # Remove module
    if [[ -f "${INSTALL_DIR}/${PAM_MODULE}" ]]; then
        sudo rm -f "${INSTALL_DIR}/${PAM_MODULE}"
        log_success "Removed PAM module"
    fi

    # Clean build directory
    rm -rf "${BUILD_DIR}"

    echo ""
    log_success "pam_ssh_agent_auth uninstalled"
    echo ""
    echo "Note: SSH_AUTH_SOCK env_keep in sudoers was not removed (harmless to leave)"
}

main() {
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}   pam_ssh_agent_auth Setup for macOS${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""

    check_requirements
    download_source
    apply_patches
    build_module
    install_module
    configure_sudoers
    configure_pam

    # Cleanup
    rm -rf "${BUILD_DIR}"

    show_summary
}

case "${1:-install}" in
    install)
        main
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "Usage: $0 [install|uninstall]"
        exit 1
        ;;
esac
