#!/bin/bash

###############################################################################
# Title: detect-os.sh
# Description: OS detection utility for boblbee dotfiles
# Provides functions to detect macOS, Ubuntu, and system capabilities
# Source: https://github.com/matdotcx/boblbee
###############################################################################

# Detect if running on macOS
is_macos() {
    [[ "$OSTYPE" == "darwin"* ]]
}

# Detect if running on Ubuntu
is_ubuntu() {
    [[ -f /etc/lsb-release ]] && grep -q "Ubuntu" /etc/lsb-release
}

# Check if system is CLI-only (no desktop environment)
is_cli_only() {
    ! pgrep -x "Xorg\|gdm\|lightdm\|sddm\|lxdm" >/dev/null 2>&1
}

# Get OS name for display
get_os_name() {
    if is_macos; then
        echo "macOS"
    elif is_ubuntu; then
        echo "Ubuntu"
    else
        echo "Unknown"
    fi
}

# Get package manager command
get_package_manager() {
    if is_macos; then
        if command -v port >/dev/null 2>&1; then
            echo "port"
        elif command -v brew >/dev/null 2>&1; then
            echo "brew"
        else
            echo ""
        fi
    elif is_ubuntu; then
        echo "apt"
    else
        echo ""
    fi
}

# Get the appropriate home bin path
get_user_bin_path() {
    if is_ubuntu; then
        echo "$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/bin"
    else
        echo "$HOME/bin:$HOME/.local/bin"
    fi
}

# Export functions if script is sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]] || [[ "${ZSH_VERSION}" ]]; then
    # Script is being sourced
    export -f is_macos is_ubuntu is_cli_only get_os_name get_package_manager get_user_bin_path 2>/dev/null || true
fi