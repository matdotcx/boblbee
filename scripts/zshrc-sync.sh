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
DOTFILES_ZSHRC="$DOTFILES_DIR/assets/.zshrc"
HOME_ZSHRC="$HOME/.zshrc"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Smart .zshrc Sync Setup ==="
echo ""

# Check if source .zshrc exists
if [ ! -f "$DOTFILES_ZSHRC" ]; then
  echo -e "${RED}✗ Source file not found: $DOTFILES_ZSHRC${NC}"
  echo "Please ensure the .zshrc file exists in the assets directory"
  exit 1
fi

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
    if cp "$HOME_ZSHRC" "$backup_file" 2>/dev/null; then
      echo -e "${GREEN}✓ Backup created successfully${NC}"
    else
      echo -e "${RED}✗ Backup failed, continuing anyway${NC}"
    fi
  fi
}

# Function to check write permissions
check_permissions() {
  local target_dir="$(dirname "$1")"
  if [ ! -w "$target_dir" ]; then
    echo -e "${RED}✗ No write permission for $target_dir${NC}"
    return 1
  fi
  return 0
}

# Main logic
if check_icloud; then
  echo -e "${BLUE}iCloud Drive detected${NC}"
  
  # Ensure iCloud directory structure exists
  if ! mkdir -p "$(dirname "$ICLOUD_ZSHRC")" 2>/dev/null; then
    echo -e "${RED}✗ Failed to create iCloud directory${NC}"
    exit 1
  fi
  
  # If iCloud .zshrc doesn't exist, copy from dotfiles
  if [ ! -f "$ICLOUD_ZSHRC" ]; then
    echo -e "${YELLOW}Creating .zshrc in iCloud Drive${NC}"
    if ! check_permissions "$ICLOUD_ZSHRC" || ! cp "$DOTFILES_ZSHRC" "$ICLOUD_ZSHRC" 2>/dev/null; then
      echo -e "${RED}✗ Failed to copy .zshrc to iCloud Drive${NC}"
      exit 1
    fi
  fi
  
  # Check if home .zshrc is already correctly symlinked
  if [ -L "$HOME_ZSHRC" ] && [ "$(realpath "$HOME_ZSHRC" 2>/dev/null)" = "$(realpath "$ICLOUD_ZSHRC" 2>/dev/null)" ]; then
    echo -e "${GREEN}✓ .zshrc is already correctly symlinked to iCloud${NC}"
  else
    # Backup existing .zshrc if needed
    backup_zshrc
    
    # Remove existing .zshrc (file or wrong symlink)
    rm -f "$HOME_ZSHRC"
    
    # Create symlink to iCloud
    if ! check_permissions "$HOME_ZSHRC" || ! ln -s "$ICLOUD_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
      echo -e "${RED}✗ Failed to create symlink to iCloud Drive${NC}"
      exit 1
    fi
    echo -e "${GREEN}✓ Created symlink: ~/.zshrc → iCloud Drive${NC}"
  fi
  
  # Keep dotfiles version in sync
  if ! diff -q "$ICLOUD_ZSHRC" "$DOTFILES_ZSHRC" >/dev/null 2>&1; then
    echo -e "${YELLOW}Syncing iCloud version to dotfiles${NC}"
    if ! check_permissions "$DOTFILES_ZSHRC" || ! cp "$ICLOUD_ZSHRC" "$DOTFILES_ZSHRC" 2>/dev/null; then
      echo -e "${RED}✗ Failed to sync to dotfiles, continuing anyway${NC}"
    else
      echo -e "${GREEN}✓ Dotfiles .zshrc updated${NC}"
    fi
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
      if ! check_permissions "$HOME_ZSHRC" || ! cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
        echo -e "${RED}✗ Failed to update .zshrc from dotfiles${NC}"
        exit 1
      fi
      echo -e "${GREEN}✓ Updated .zshrc from dotfiles${NC}"
    fi
  else
    # Remove any symlink and copy from dotfiles
    rm -f "$HOME_ZSHRC"
    if ! check_permissions "$HOME_ZSHRC" || ! cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
      echo -e "${RED}✗ Failed to install .zshrc from dotfiles${NC}"
      exit 1
    fi
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