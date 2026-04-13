#!/bin/bash
#
# install-collector.sh - Install Prometheus node_exporter
#
# Downloads and installs the correct node_exporter binary for the current
# platform and architecture, then configures it to start automatically.
#
# Supports:
#   - macOS (arm64, amd64) - LaunchAgent
#   - Linux (arm64, armv7, amd64) - systemd user service
#
# Usage:
#   ./install-collector.sh           # Install with default port 9100
#   ./install-collector.sh 9101      # Install with custom port
#
# Requirements:
#   - curl
#   - tar
#   - systemctl (Linux) or launchctl (macOS)
#

set -e

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

# Configuration
INSTALL_DIR="$HOME/bin"
LOG_DIR="$HOME/logs"
PORT="${1:-9100}"

# Get Tailscale IP, handling both CLI and App Store installations.
# Falls back to grepping network interfaces for a 100.x.x.x CGNAT address
# (Tailscale's assigned range) when the CLI is unavailable.
get_tailscale_ip() {
    # 1. Try the tailscale CLI (works on Linux / standalone macOS installs)
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null) && [[ -n "$ts_ip" ]] && { echo "$ts_ip"; return 0; }

    # 2. Grep network interfaces for Tailscale's CGNAT range (100.64.0.0/10)
    #    This covers the Mac App Store version where the CLI is not on PATH.
    if is_macos; then
        ts_ip=$(ifconfig 2>/dev/null | grep -A1 'utun' | grep 'inet ' | grep -oE '100\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    else
        ts_ip=$(ip -4 addr show 2>/dev/null | grep -oE '100\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    [[ -n "$ts_ip" ]] && { echo "$ts_ip"; return 0; }

    return 1
}

# Get listen address: prefer Tailscale IP (reachable by Prometheus), fall back
# to localhost.  NEVER default to 0.0.0.0 — node_exporter should not be
# world-reachable on public interfaces.
get_listen_address() {
    local ts_ip
    ts_ip=$(get_tailscale_ip)
    if [[ -n "$ts_ip" ]]; then
        echo "$ts_ip"
        return 0
    fi
    echo "127.0.0.1"
}

LISTEN_ADDRESS="${2:-$(get_listen_address)}"

# Alias for Linux detection (not in detect-os.sh)
is_linux() {
    [[ "$OSTYPE" == "linux-gnu"* ]]
}

get_os() {
    if is_macos; then
        echo "darwin"
    elif is_linux; then
        echo "linux"
    else
        log_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
}

get_arch() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armv7)
            echo "armv7"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

# ============================================================================
# Download and install binary
# ============================================================================

download_node_exporter() {
    local os="$1"
    local arch="$2"
    local version="$NODE_EXPORTER_VERSION"
    local filename="node_exporter-${version}.${os}-${arch}"
    local url="https://github.com/prometheus/node_exporter/releases/download/v${version}/${filename}.tar.gz"
    local tmp_dir

    tmp_dir=$(mktemp -d)
    trap "rm -rf $tmp_dir" EXIT

    log_info "Downloading node_exporter v${version} for ${os}-${arch}..."

    if ! curl -sL "$url" -o "$tmp_dir/node_exporter.tar.gz"; then
        log_error "Failed to download from $url"
        exit 1
    fi

    log_info "Extracting..."
    tar -xzf "$tmp_dir/node_exporter.tar.gz" -C "$tmp_dir"

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Install binary
    mv "$tmp_dir/$filename/node_exporter" "$INSTALL_DIR/node_exporter"
    chmod +x "$INSTALL_DIR/node_exporter"

    # Create textfile collector directory
    mkdir -p "$PROMETHEUS_TEXTFILE_DIR"

    log_success "Installed to $INSTALL_DIR/node_exporter"
}

# ============================================================================
# Service configuration - macOS
# ============================================================================

configure_macos_service() {
    local plist_path="$HOME/Library/LaunchAgents/com.observability.node-exporter.plist"

    log_info "Creating LaunchAgent..."

    mkdir -p "$HOME/Library/LaunchAgents"
    mkdir -p "$LOG_DIR"

    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.observability.node-exporter</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/node_exporter</string>
        <string>--web.listen-address=${LISTEN_ADDRESS}:${PORT}</string>
        <string>--collector.textfile.directory=${PROMETHEUS_TEXTFILE_DIR}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/node-exporter.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/node-exporter.log</string>
</dict>
</plist>
EOF

    # Unload if already loaded
    launchctl unload "$plist_path" 2>/dev/null || true

    # Load the agent
    launchctl load "$plist_path"

    log_success "LaunchAgent configured"
}

# ============================================================================
# Service configuration - Linux
# ============================================================================

configure_linux_service() {
    local service_dir
    local service_path
    local use_system=false

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        service_dir="/etc/systemd/system"
        service_path="$service_dir/node-exporter.service"
        use_system=true
        log_info "Running as root, installing system service..."
    else
        service_dir="$HOME/.config/systemd/user"
        service_path="$service_dir/node-exporter.service"
        log_info "Installing user service..."
    fi

    mkdir -p "$service_dir"
    mkdir -p "$LOG_DIR"

    cat > "$service_path" << EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/node_exporter --web.listen-address=${LISTEN_ADDRESS}:${PORT} --collector.textfile.directory=${PROMETHEUS_TEXTFILE_DIR}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    if $use_system; then
        systemctl daemon-reload
        systemctl enable node-exporter
        systemctl restart node-exporter
    else
        systemctl --user daemon-reload
        systemctl --user enable node-exporter
        systemctl --user restart node-exporter

        # Enable lingering so user services start at boot
        loginctl enable-linger "$(whoami)" 2>/dev/null || true
    fi

    log_success "Systemd service configured"
}

# ============================================================================
# Verification
# ============================================================================

verify_installation() {
    log_info "Waiting for service to start..."
    sleep 3

    log_info "Verifying node_exporter is running..."

    # Check the actual listen address, not localhost — the exporter may be
    # bound to a Tailscale IP or other non-loopback address.
    if curl -s "http://${LISTEN_ADDRESS}:${PORT}/metrics" > /dev/null 2>&1; then
        log_success "node_exporter is running on ${LISTEN_ADDRESS}:${PORT}"

        # Show a sample metric
        local sample
        sample=$(curl -s "http://${LISTEN_ADDRESS}:${PORT}/metrics" | grep "^node_uname_info" | head -1)
        if [[ -n "$sample" ]]; then
            log_info "Sample metric: $sample"
        fi
        return 0
    else
        log_error "node_exporter is not responding on ${LISTEN_ADDRESS}:${PORT}"
        log_info "Check logs in $LOG_DIR/node-exporter.log"
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   node_exporter Installer${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""

    local os
    local arch

    os=$(get_os)
    arch=$(get_arch)

    log_info "Detected platform: ${os}-${arch}"
    log_info "Listen address: ${LISTEN_ADDRESS}:${PORT}"
    log_info "Install directory: ${INSTALL_DIR}"
    echo ""

    # Check for existing installation
    if [[ -f "$INSTALL_DIR/node_exporter" ]]; then
        local current_version
        current_version=$("$INSTALL_DIR/node_exporter" --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ "$current_version" == "$NODE_EXPORTER_VERSION" ]]; then
            log_warn "node_exporter v${NODE_EXPORTER_VERSION} already installed"
            log_info "Reconfiguring service..."
        else
            log_info "Upgrading from v${current_version} to v${NODE_EXPORTER_VERSION}"
            download_node_exporter "$os" "$arch"
        fi
    else
        download_node_exporter "$os" "$arch"
    fi

    # Configure service based on platform
    if is_macos; then
        configure_macos_service
    elif is_linux; then
        configure_linux_service
    fi

    # Verify
    if verify_installation; then
        echo ""
        echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}   Installation Complete${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Metrics endpoint: http://${LISTEN_ADDRESS}:${PORT}/metrics"
        echo ""
        echo "Commands:"
        if is_macos; then
            echo "  View logs:  tail -f $LOG_DIR/node-exporter.log"
            echo "  Stop:       launchctl unload ~/Library/LaunchAgents/com.observability.node-exporter.plist"
            echo "  Start:      launchctl load ~/Library/LaunchAgents/com.observability.node-exporter.plist"
        else
            if [[ $EUID -eq 0 ]]; then
                echo "  View logs:  journalctl -u node-exporter -f"
                echo "  Stop:       systemctl stop node-exporter"
                echo "  Start:      systemctl start node-exporter"
            else
                echo "  View logs:  journalctl --user -u node-exporter -f"
                echo "  Stop:       systemctl --user stop node-exporter"
                echo "  Start:      systemctl --user start node-exporter"
            fi
        fi
        echo ""
    else
        exit 1
    fi
}

main "$@"
