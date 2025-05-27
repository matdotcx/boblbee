#!/usr/bin/env bash

#########################################################
# Title: zshrc-sync
# Description: Smart .zshrc sync that handles iCloud Drive
# Source: https://github.com/matdotcx/
#########################################################

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Paths
ICLOUD_ZSHRC="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ark/Sync/System/.zshrc"
DOTFILES_ZSHRC="$DOTFILES_DIR/.zshrc"
HOME_ZSHRC="$HOME/.zshrc"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Smart .zshrc Sync Setup ==="
echo ""

# Function to check if iCloud Drive is available
check_icloud() {
  if [ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
    return 0
  else
    return 1
  fi
}

# Function to backup existing .zshrc
backup_zshrc() {
  if [ -f "$HOME_ZSHRC" ] && [ ! -L "$HOME_ZSHRC" ]; then
    local backup_file="$HOME_ZSHRC.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Backing up existing .zshrc to $backup_file${NC}"
    cp "$HOME_ZSHRC" "$backup_file"
  fi
}

# Main logic
if check_icloud; then
  echo -e "${BLUE}iCloud Drive detected${NC}"
  
  # Ensure iCloud directory structure exists
  mkdir -p "$(dirname "$ICLOUD_ZSHRC")"
  
  # If iCloud .zshrc doesn't exist, copy from dotfiles
  if [ ! -f "$ICLOUD_ZSHRC" ]; then
    echo -e "${YELLOW}Creating .zshrc in iCloud Drive${NC}"
    cp "$DOTFILES_ZSHRC" "$ICLOUD_ZSHRC"
  fi
  
  # Check if home .zshrc is already correctly symlinked
  if [ -L "$HOME_ZSHRC" ] && [ "$(readlink "$HOME_ZSHRC")" = "$ICLOUD_ZSHRC" ]; then
    echo -e "${GREEN}✓ .zshrc is already correctly symlinked to iCloud${NC}"
  else
    # Backup existing .zshrc if needed
    backup_zshrc
    
    # Remove existing .zshrc (file or wrong symlink)
    rm -f "$HOME_ZSHRC"
    
    # Create symlink to iCloud
    ln -s "$ICLOUD_ZSHRC" "$HOME_ZSHRC"
    echo -e "${GREEN}✓ Created symlink: ~/.zshrc → iCloud Drive${NC}"
  fi
  
  # Keep dotfiles version in sync
  if ! diff -q "$ICLOUD_ZSHRC" "$DOTFILES_ZSHRC" >/dev/null 2>&1; then
    echo -e "${YELLOW}Syncing iCloud version to dotfiles${NC}"
    cp "$ICLOUD_ZSHRC" "$DOTFILES_ZSHRC"
    echo -e "${GREEN}✓ Dotfiles .zshrc updated${NC}"
  fi
  
  echo ""
  echo -e "${BLUE}Setup: iCloud Drive (primary) ↔ Dotfiles (backup)${NC}"
  echo "Edit .zshrc in iCloud Drive for immediate effect"
  echo "Changes will be backed up to dotfiles on next sync"
  
else
  echo -e "${BLUE}No iCloud Drive detected - using dotfiles only${NC}"
  
  # Check if home .zshrc is already correctly set up
  if [ -f "$HOME_ZSHRC" ] && ! [ -L "$HOME_ZSHRC" ]; then
    # Compare with dotfiles version
    if diff -q "$HOME_ZSHRC" "$DOTFILES_ZSHRC" >/dev/null 2>&1; then
      echo -e "${GREEN}✓ .zshrc is up to date${NC}"
    else
      # Backup and update
      backup_zshrc
      cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC"
      echo -e "${GREEN}✓ Updated .zshrc from dotfiles${NC}"
    fi
  else
    # Remove any symlink and copy from dotfiles
    rm -f "$HOME_ZSHRC"
    cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC"
    echo -e "${GREEN}✓ Installed .zshrc from dotfiles${NC}"
  fi
  
  echo ""
  echo -e "${BLUE}Setup: Dotfiles only (no iCloud)${NC}"
  echo "Edit .zshrc in dotfiles repo and run this script to update"
fi

# Final check
if [ -f "$HOME_ZSHRC" ] || [ -L "$HOME_ZSHRC" ]; then
  echo ""
  echo -e "${GREEN}✓ .zshrc setup complete!${NC}"
  
  # Update the claude-sync alias path to be relative to home
  if grep -q "claude-sync.*boblbee/scripts/claude-sync.sh" "$HOME_ZSHRC"; then
    echo ""
    echo "Note: claude-sync alias detected"
    echo "You may need to source your .zshrc for changes to take effect:"
    echo "  source ~/.zshrc"
  fi
else
  echo ""
  echo -e "${RED}✗ Setup failed - please check permissions${NC}"
  exit 1
fi