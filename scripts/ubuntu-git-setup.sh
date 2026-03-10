#!/bin/bash

###############################################################################
# Title: ubuntu-git-setup.sh
# Description: Git configuration setup for Ubuntu to match macOS workflow
# Sets up shared git config and SSH keys for consistent development experience
# Source: https://github.com/matdotcx/boblbee
###############################################################################

set -e

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/lib.sh"

# Alias for backwards compat within this script
log_warning() { log_warn "$1"; }

# Check if running on Ubuntu
if ! is_ubuntu; then
    log_error "This script is designed for Ubuntu systems only"
    exit 1
fi

log_info "Starting Git configuration for Ubuntu..."

# Function to prompt for user input
prompt_user() {
    local prompt="$1"
    local default="$2"
    local response
    
    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " response
        echo "${response:-$default}"
    else
        read -p "$prompt: " response
        echo "$response"
    fi
}

# Configure git user information
configure_git_user() {
    local current_name=$(git config --global user.name 2>/dev/null || echo "")
    local current_email=$(git config --global user.email 2>/dev/null || echo "")
    
    if [[ -z "$current_name" ]]; then
        log_info "Configuring git user information..."
        name=$(prompt_user "Enter your full name for git commits")
        git config --global user.name "$name"
        log_success "Git user.name set to: $name"
    else
        log_success "Git user.name already configured: $current_name"
    fi
    
    if [[ -z "$current_email" ]]; then
        email=$(prompt_user "Enter your email for git commits")
        git config --global user.email "$email"
        log_success "Git user.email set to: $email"
    else
        log_success "Git user.email already configured: $current_email"
    fi
}

# Configure git settings to match macOS setup
configure_git_settings() {
    log_info "Configuring git settings..."
    
    # Core settings
    git config --global init.defaultBranch main
    git config --global core.autocrlf input
    git config --global core.safecrlf true
    git config --global pull.rebase false
    git config --global push.default simple
    
    # Editor preference
    if command -v vim >/dev/null 2>&1; then
        git config --global core.editor vim
    fi
    
    # Aliases to match macOS workflow
    git config --global alias.st status
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.unstage 'reset HEAD --'
    git config --global alias.last 'log -1 HEAD'
    git config --global alias.visual '!gitk'
    
    log_success "Git settings configured"
}

# Set up SSH key for git
setup_ssh_key() {
    local ssh_dir="$HOME/.ssh"
    local key_file="$ssh_dir/id_rsa"
    
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        log_info "Created .ssh directory"
    fi
    
    if [[ -f "$key_file" ]]; then
        log_success "SSH key already exists: $key_file"
        log_info "Public key content:"
        cat "$key_file.pub" 2>/dev/null || log_warning "Public key file not found"
    else
        log_info "No SSH key found. You have several options:"
        echo "1. Copy existing SSH key from macOS"
        echo "2. Generate a new SSH key"
        echo "3. Skip SSH key setup for now"
        
        choice=$(prompt_user "Choose option (1/2/3)" "1")
        
        case "$choice" in
            1)
                log_info "To copy SSH key from macOS:"
                echo "  1. On macOS: cat ~/.ssh/id_rsa"
                echo "  2. Copy the output and paste it when prompted"
                echo "  3. Do the same for ~/.ssh/id_rsa.pub"
                echo ""
                read -p "Press Enter when ready to paste private key..."
                
                log_info "Paste your private key (press Ctrl+D when done):"
                cat > "$key_file"
                chmod 600 "$key_file"
                
                log_info "Paste your public key (press Ctrl+D when done):"
                cat > "$key_file.pub"
                chmod 644 "$key_file.pub"
                
                log_success "SSH key copied from macOS"
                ;;
            2)
                email=$(git config --global user.email)
                ssh-keygen -t rsa -b 4096 -C "$email" -f "$key_file"
                log_success "New SSH key generated"
                log_info "Add this public key to your Git hosting service:"
                cat "$key_file.pub"
                ;;
            3)
                log_info "SSH key setup skipped"
                return
                ;;
        esac
    fi
    
    # Start SSH agent and add key
    if [[ -f "$key_file" ]]; then
        eval "$(ssh-agent -s)" >/dev/null
        ssh-add "$key_file" 2>/dev/null || log_warning "Could not add SSH key to agent"
        log_success "SSH key added to agent"
    fi
}

# Set up GitHub token for CLI operations
setup_github_token() {
    if [[ -f "$HOME/.github_token" ]]; then
        log_success "GitHub token file already exists"
    else
        log_info "GitHub token setup (optional):"
        echo "To enable GitHub CLI operations, you can:"
        echo "1. Create a Personal Access Token on GitHub"
        echo "2. Save it to ~/.github_token"
        echo ""
        
        read -p "Do you want to set up GitHub token now? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            token=$(prompt_user "Enter your GitHub Personal Access Token")
            echo "$token" > "$HOME/.github_token"
            chmod 600 "$HOME/.github_token"
            log_success "GitHub token saved to ~/.github_token"
        else
            log_info "GitHub token setup skipped"
        fi
    fi
}

# Test git configuration
test_git_setup() {
    log_info "Testing git configuration..."
    
    # Test basic git commands
    if git config --global user.name >/dev/null && git config --global user.email >/dev/null; then
        log_success "Git user configuration is complete"
    else
        log_error "Git user configuration is incomplete"
        return 1
    fi
    
    # Test SSH connection to GitHub
    if [[ -f "$HOME/.ssh/id_rsa" ]]; then
        log_info "Testing SSH connection to GitHub..."
        if ssh -T git@github.com -o ConnectTimeout=10 -o BatchMode=yes 2>&1 | grep -q "successfully authenticated"; then
            log_success "SSH connection to GitHub successful"
        else
            log_warning "SSH connection to GitHub failed or not configured"
        fi
    fi
    
    log_success "Git setup test completed"
}

# Main execution
main() {
    configure_git_user
    configure_git_settings
    setup_ssh_key
    setup_github_token
    test_git_setup
    
    log_success "Git configuration completed successfully!"
    log_info "Your git setup should now match your macOS workflow"
    log_info "Next steps:"
    log_info "  1. Verify SSH key is added to your Git hosting service"
    log_info "  2. Test git operations with a repository"
    log_info "  3. Run boblbee sync scripts to complete setup"
}

# Run main function
main