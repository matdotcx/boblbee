#!/bin/bash

#########################################################
# Title: index
# Description: Call and install each module - supports macOS and Ubuntu
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Ensure we're running from the scripts directory (run_script uses ./script)
cd "$(dirname "$0")" || exit 1

# Source OS detection
source "./detect-os.sh"

# Note: Some scripts require sudo privileges.
# They will ask for password when needed.

# Function to run script with error checking
# Executes via the script's own shebang (not forced bash) so zsh scripts work.
run_script() {
    local script="$1"
    local use_sudo="${2:-}"
    shift 2 2>/dev/null || shift $#
    local extra_args=("$@")

    if [ ! -f "$script" ]; then
        echo "Error: Script $script not found"
        exit 1
    fi

    # Ensure executable
    chmod +x "$script" 2>/dev/null || true

    echo "Running $script..."
    if [ "$use_sudo" = "sudo" ]; then
        if ! sudo "./$script" "${extra_args[@]}"; then
            echo "Error: $script failed"
            exit 1
        fi
    else
        if ! "./$script" "${extra_args[@]}"; then
            echo "Error: $script failed"
            exit 1
        fi
    fi
    sleep 3
}

# Platform-specific setup
if is_ubuntu; then
    echo "Starting boblbee setup for Ubuntu..."
    echo ""

    # Ubuntu setup sequence
    run_script "ubuntu-essentials.sh"
    run_script "ubuntu-git-setup.sh"
    run_script "claude.sh"
    run_script "zshrc-sync.sh"
    run_script "tmux-sync.sh"
    run_script "motd-sync.sh"
    run_script "ssh-sync.sh"
    run_script "tailscale-setup.sh"
    run_script "observability-collector.sh"
    run_script "setup-gpg-signing.sh"
    run_script "self-update.sh" "" "--install"

    echo ""
    echo "Ubuntu setup complete!"
    echo "Please log out and back in to use zsh as your default shell."
    echo "Or run: exec zsh"

elif is_macos; then
    echo "Starting boblbee setup for macOS..."
    echo ""

    # Prompt for computer name up front
    current_name=$(scutil --get ComputerName 2>/dev/null || echo "Unknown")
    echo "Current computer name: $current_name"
    read -p "Enter new computer name (or press Enter to keep current): " input_name
    if [[ -n "$input_name" && "$input_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        HOST_SHORT_NAME="$input_name"
    else
        [[ -n "$input_name" ]] && echo "Invalid name. Using current name: $current_name"
        HOST_SHORT_NAME="$current_name"
    fi

    # Original macOS setup sequence
    run_script "hostname-fqdn.sh" "sudo" "$HOST_SHORT_NAME"
    run_script "touchid-sudo.sh" "sudo"
    run_script "xcode.sh"
    run_script "macports.sh" "sudo"
    run_script "dots.sh"
    run_script "claude.sh"
    run_script "zshrc-sync.sh"
    run_script "tmux-sync.sh"
    run_script "ghostty-sync.sh"
    run_script "motd-sync.sh"
    run_script "ssh-sync.sh"
    run_script "tailscale-setup.sh"
    run_script "observability-collector.sh"
    run_script "pam-ssh-agent-sudo.sh"
    run_script "setup-gpg-signing.sh"
    run_script "self-update.sh" "" "--install"

    echo ""
    echo "macOS setup complete!"

else
    echo "Unsupported operating system: $(uname -s)"
    echo "This script supports macOS and Ubuntu only."
    exit 1
fi
