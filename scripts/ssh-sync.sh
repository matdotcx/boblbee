#!/usr/bin/env bash

#########################################################
# Title: ssh-sync
# Description: Set up SSH configuration sync - iCloud Drive on macOS, local management on Ubuntu
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source OS detection
source "$(dirname "$0")/detect-os.sh"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== SSH Configuration Sync ==="
echo ""

# Paths
ICLOUD_SSH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ark/Sync/System/.ssh"
HOME_SSH="$HOME/.ssh"

# Function to check if iCloud Drive is available AND functional (macOS only)
check_icloud() {
  if ! is_macos; then
    return 1
  fi
  local icloud_base="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
  if [ ! -d "$icloud_base" ]; then
    return 1
  fi
  # Test if we can actually write to iCloud (may exist but not signed in)
  local test_file="$icloud_base/.boblbee_write_test_$$"
  if touch "$test_file" 2>/dev/null; then
    rm -f "$test_file" 2>/dev/null
    return 0
  else
    return 1
  fi
}

# Function to backup existing SSH
backup_ssh() {
  if [ -d "$HOME_SSH" ] && [ ! -L "$HOME_SSH" ]; then
    local backup_dir="$HOME_SSH.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Backing up existing .ssh to $backup_dir${NC}"
    mv "$HOME_SSH" "$backup_dir"
    echo -e "${GREEN}✓ SSH backup created${NC}"
  fi
}

# Main logic - platform-specific behavior
if is_ubuntu; then
  echo -e "${BLUE}Ubuntu detected - local SSH management${NC}"
  
  # Ubuntu: Simple SSH configuration management
  if [ -d "$HOME_SSH" ]; then
    echo -e "${GREEN}✓ SSH directory exists${NC}"
    
    # Ensure correct permissions
    chmod 700 "$HOME_SSH"
    
    # Set permissions for SSH files
    if ls "$HOME_SSH"/* >/dev/null 2>&1; then
      chmod 600 "$HOME_SSH"/* 2>/dev/null || true
      chmod 644 "$HOME_SSH"/*.pub 2>/dev/null || true
      chmod 644 "$HOME_SSH"/known_hosts* 2>/dev/null || true
      chmod 644 "$HOME_SSH"/config 2>/dev/null || true
      echo -e "${GREEN}✓ SSH permissions set correctly${NC}"
    fi
    
    # Display SSH public keys if they exist
    echo ""
    echo -e "${BLUE}Available SSH public keys:${NC}"
    for pub_key in "$HOME_SSH"/*.pub; do
      if [ -f "$pub_key" ]; then
        echo "$(basename "$pub_key"):"
        cat "$pub_key"
        echo ""
      fi
    done
    
  else
    echo -e "${YELLOW}No SSH directory found${NC}"
    echo "To set up SSH keys:"
    echo "  1. Run ssh-keygen -t rsa -b 4096 -C 'your_email@example.com'"
    echo "  2. Add the public key to your Git hosting service"
    echo "  3. Run this script again to verify permissions"
  fi
  
  echo ""
  echo -e "${BLUE}Setup: Local SSH management${NC}"
  echo "SSH keys and config managed locally (not synced)"
  
elif check_icloud; then
  echo -e "${BLUE}iCloud Drive detected${NC}"
  
  # Check if iCloud SSH directory exists
  if [ ! -d "$ICLOUD_SSH" ]; then
    echo -e "${YELLOW}No SSH configuration found in iCloud${NC}"
    
    # If local SSH exists and isn't a symlink, offer to move it
    if [ -d "$HOME_SSH" ] && [ ! -L "$HOME_SSH" ]; then
      echo ""
      echo "Found existing SSH configuration at ~/.ssh"
      echo -e "${BLUE}Would you like to move it to iCloud? (y/n)${NC}"
      read -n 1 -r
      echo
      
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Create directory structure in iCloud
        mkdir -p "$(dirname "$ICLOUD_SSH")"
        
        # Move SSH to iCloud
        echo "Moving SSH configuration to iCloud..."
        mv "$HOME_SSH" "$ICLOUD_SSH"
        
        # Create symlink
        ln -s "$ICLOUD_SSH" "$HOME_SSH"
        echo -e "${GREEN}✓ SSH configuration moved to iCloud and linked${NC}"
      else
        echo "Keeping local SSH configuration"
        exit 0
      fi
    else
      echo "No local SSH configuration to migrate"
      echo ""
      echo "To set up SSH in iCloud:"
      echo "1. Create your SSH keys"
      echo "2. Run this script again to move them to iCloud"
      exit 0
    fi
  else
    # iCloud SSH exists, check symlink
    if [ -L "$HOME_SSH" ] && [ "$(readlink "$HOME_SSH")" = "$ICLOUD_SSH" ]; then
      echo -e "${GREEN}✓ SSH already correctly symlinked to iCloud${NC}"
    else
      # Backup existing SSH if needed
      backup_ssh
      
      # Remove existing file/symlink
      rm -rf "$HOME_SSH"
      
      # Create symlink
      ln -s "$ICLOUD_SSH" "$HOME_SSH"
      echo -e "${GREEN}✓ SSH configuration linked to iCloud${NC}"
    fi
  fi
  
  # Ensure correct permissions
  if [ -L "$HOME_SSH" ]; then
    # For symlinks, we need to check the target
    echo "Checking SSH permissions..."
    chmod 700 "$ICLOUD_SSH" 2>/dev/null || true
    chmod 600 "$ICLOUD_SSH"/* 2>/dev/null || true
    chmod 644 "$ICLOUD_SSH"/*.pub 2>/dev/null || true
    chmod 644 "$ICLOUD_SSH"/known_hosts* 2>/dev/null || true
    chmod 644 "$ICLOUD_SSH"/config 2>/dev/null || true
    echo -e "${GREEN}✓ SSH permissions verified${NC}"
  fi
  
else
  echo -e "${BLUE}No iCloud Drive detected${NC}"
  echo "SSH configuration will remain local only"
  
  # Ensure local SSH directory exists with correct permissions
  if [ -d "$HOME_SSH" ]; then
    chmod 700 "$HOME_SSH"
    echo -e "${GREEN}✓ Local SSH permissions verified${NC}"
  else
    echo "No SSH configuration found"
  fi
fi

echo ""
echo -e "${GREEN}✓ SSH setup complete!${NC}"