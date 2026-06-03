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

# Prompt for git identity if not already configured.
# Sets git config --global so all subsequent scripts (GPG signing, commits,
# etc.) have the identity available from the start.
configure_git_identity() {
    local current_name current_email

    current_name=$(git config --global user.name 2>/dev/null || echo "")
    current_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "$current_name" && -n "$current_email" ]]; then
        echo "Git identity already configured: $current_name <$current_email>"
        return 0
    fi

    echo ""
    echo "Git identity is not yet configured on this machine."

    if [[ -z "$current_name" ]]; then
        read -p "Enter your full name for git commits: " input_name
        if [[ -n "$input_name" ]]; then
            git config --global user.name "$input_name"
            echo "  user.name set to: $input_name"
        else
            echo "  Skipped — you can set this later with: git config --global user.name \"Your Name\""
        fi
    else
        echo "  user.name already set: $current_name"
    fi

    if [[ -z "$current_email" ]]; then
        read -p "Enter your email for git commits: " input_email
        if [[ -n "$input_email" ]]; then
            git config --global user.email "$input_email"
            echo "  user.email set to: $input_email"
        else
            echo "  Skipped — you can set this later with: git config --global user.email \"you@example.com\""
        fi
    else
        echo "  user.email already set: $current_email"
    fi

    echo ""
}

# Switch boblbee's origin remote from HTTPS to SSH.
# The initial clone uses HTTPS because it works before SSH keys are set up,
# but once setup is complete we want SSH for push access.
switch_remote_to_ssh() {
    local repo_dir
    repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
    local current_url
    current_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null)

    if [[ "$current_url" == https://github.com/* ]]; then
        # Convert https://github.com/owner/repo.git → git@github.com:owner/repo.git
        local ssh_url
        ssh_url=$(echo "$current_url" | sed 's|https://github.com/|git@github.com:|')
        git -C "$repo_dir" remote set-url origin "$ssh_url"
        echo ""
        echo "Switched boblbee remote from HTTPS to SSH:"
        echo "  $current_url → $ssh_url"
    elif [[ "$current_url" == git@github.com:* ]]; then
        echo "Boblbee remote is already SSH: $current_url"
    else
        echo "Boblbee remote is not a GitHub URL — leaving as-is: $current_url"
    fi
}

# Platform-specific setup
if is_ubuntu; then
    echo "Starting boblbee setup for Ubuntu..."
    echo ""

    # Ubuntu git identity is handled interactively by ubuntu-git-setup.sh,
    # but configure early so claude.sh and other scripts can use it too.
    configure_git_identity

    # Ubuntu setup sequence
    run_script "ubuntu-essentials.sh"
    run_script "ubuntu-git-setup.sh"
    run_script "git-config-shared.sh"
    run_script "claude.sh"
    run_script "zshrc-sync.sh"
    run_script "tmux-sync.sh"
    run_script "motd-sync.sh"
    run_script "ssh-sync.sh"
    run_script "tailscale-setup.sh"
    run_script "observability-collector.sh"
    run_script "setup-gpg-signing.sh"
    run_script "self-update.sh" "" "--install"

    switch_remote_to_ssh

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

    # Prompt for git identity early so GPG signing and commits work
    configure_git_identity

    # Original macOS setup sequence
    run_script "hostname-fqdn.sh" "sudo" "$HOST_SHORT_NAME"
    run_script "touchid-sudo.sh" "sudo"
    run_script "xcode.sh"
    run_script "macports.sh" "sudo"
    run_script "dots.sh"
    run_script "git-config-shared.sh"
    run_script "claude.sh"
    run_script "zshrc-sync.sh"
    run_script "tmux-sync.sh"
    run_script "ghostty-sync.sh"
    run_script "zed-sync.sh"
    run_script "motd-sync.sh"
    run_script "ssh-sync.sh"
    run_script "tailscale-setup.sh"
    run_script "observability-collector.sh"
    run_script "pam-ssh-agent-sudo.sh"
    run_script "setup-gpg-signing.sh"
    run_script "self-update.sh" "" "--install"

    switch_remote_to_ssh

    echo ""
    echo "macOS setup complete!"

else
    echo "Unsupported operating system: $(uname -s)"
    echo "This script supports macOS and Ubuntu only."
    exit 1
fi
