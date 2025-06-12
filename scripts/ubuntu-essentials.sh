#!/bin/bash

###############################################################################
# Title: ubuntu-essentials.sh
# Description: Essential tools setup for Ubuntu systems
# Installs build tools, npm, sets up Claude Code, and configures zsh
# Source: https://github.com/matdotcx/boblbee
###############################################################################

set -e

# Source OS detection
source "$(dirname "$0")/detect-os.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running on Ubuntu
if ! is_ubuntu; then
    log_error "This script is designed for Ubuntu systems only"
    exit 1
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should not be run as root"
    exit 1
fi

log_info "Starting Ubuntu essentials setup..."

# Update package list
log_info "Updating package list..."
sudo apt update

# Install essential packages
log_info "Installing essential packages..."
essential_packages=(
    "build-essential"
    "git"
    "curl"
    "zsh"
    "vim"
    "tree"
    "htop"
    "ripgrep"
    "fd-find"
    "npm"
    "unzip"
    "ca-certificates"
    "keychain"
)

for package in "${essential_packages[@]}"; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        log_info "Installing $package..."
        sudo apt install -y "$package"
    else
        log_success "$package already installed"
    fi
done

# Create user directories
log_info "Creating user directories..."
mkdir -p "$HOME/bin"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.npm-global"

# Configure npm global directory
log_info "Configuring npm global directory..."
npm config set prefix "$HOME/.npm-global"

# Update PATH for current session if not already set
if [[ ":$PATH:" != *":$HOME/.npm-global/bin:"* ]]; then
    export PATH="$HOME/.npm-global/bin:$PATH"
    log_info "Added npm global bin to PATH for current session"
fi

# Install Claude Code globally
log_info "Installing Claude Code..."
if command -v claude >/dev/null 2>&1; then
    log_success "Claude Code already installed"
else
    npm install -g @anthropic-ai/claude-code
    log_success "Claude Code installed successfully"
fi

# Verify Claude Code installation
if command -v claude >/dev/null 2>&1; then
    claude_version=$(claude --version 2>/dev/null || echo "unknown")
    log_success "Claude Code is available (version: $claude_version)"
else
    log_warning "Claude Code installation may not be complete. PATH update required."
fi

# Set zsh as default shell if not already set
current_shell=$(getent passwd "$USER" | cut -d: -f7)
if [[ "$current_shell" != "/usr/bin/zsh" ]] && [[ "$current_shell" != "/bin/zsh" ]]; then
    log_info "Setting zsh as default shell..."
    chsh -s "$(which zsh)"
    log_success "Default shell changed to zsh (will take effect on next login)"
else
    log_success "zsh is already the default shell"
fi

# Create basic zsh configuration if none exists
if [[ ! -f "$HOME/.zshrc" ]]; then
    log_info "Creating basic .zshrc..."
    cat > "$HOME/.zshrc" << 'EOF'
# Basic zsh configuration - will be replaced by boblbee sync
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"

# Enable colors
autoload -U colors && colors

# Basic prompt
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '

# History configuration
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=1000
setopt autocd
EOF
    log_success "Basic .zshrc created"
fi

# Set up git if not configured
if ! git config --global user.name >/dev/null 2>&1; then
    log_warning "Git user.name not configured. Run the ubuntu-git-setup.sh script next."
fi

log_success "Ubuntu essentials setup completed successfully!"
log_info "Next steps:"
log_info "  1. Run ./ubuntu-git-setup.sh to configure git"
log_info "  2. Run ./claude.sh to set up Claude Code preferences"
log_info "  3. Run ./zshrc-sync.sh to sync your zsh configuration"
log_info "  4. Log out and back in (or run 'exec zsh') to use zsh as default shell"