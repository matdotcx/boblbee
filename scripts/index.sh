#!/bin/bash

#########################################################
# Title: index
# Description: Call and install each module - supports macOS and Ubuntu
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source OS detection
source "$(dirname "$0")/detect-os.sh"

# Note: Some scripts require sudo privileges.
# They will ask for password when needed.

# Function to run script with error checking
run_script() {
    local script="$1"
    local use_sudo="$2"
    
    if [ ! -f "$script" ]; then
        echo "Error: Script $script not found"
        exit 1
    fi
    
    echo "Running $script..."
    if [ "$use_sudo" = "sudo" ]; then
        if ! sudo bash "$script"; then
            echo "Error: $script failed"
            exit 1
        fi
    else
        if ! bash "$script"; then
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
    run_script "observability-collector.sh"
    run_script "hostname-fqdn.sh" "sudo"

    echo ""
    echo "Ubuntu setup complete!"
    echo "Please log out and back in to use zsh as your default shell."
    echo "Or run: exec zsh"
    
elif is_macos; then
    echo "Starting boblbee setup for macOS..."
    echo ""
    
    # Original macOS setup sequence
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
    run_script "observability-collector.sh"
    run_script "hostname-fqdn.sh" "sudo"

    echo ""
    echo "macOS setup complete!"
    
else
    echo "Unsupported operating system: $(uname -s)"
    echo "This script supports macOS and Ubuntu only."
    exit 1
fi
