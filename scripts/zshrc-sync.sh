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

# Function to log messages with timestamp
log_message() {
  local level="$1"
  local message="$2"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >&2
}

# Function to backup existing .zshrc
backup_zshrc() {
  if [ -f "$HOME_ZSHRC" ] && [ ! -L "$HOME_ZSHRC" ]; then
    local backup_file="$HOME_ZSHRC.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Backing up existing .zshrc to $backup_file${NC}"
    if cp "$HOME_ZSHRC" "$backup_file" 2>/dev/null; then
      echo -e "${GREEN}Backup created successfully${NC}"
      return 0
    else
      echo -e "${RED}Backup failed${NC}"
      log_message "ERROR" "Failed to backup $HOME_ZSHRC to $backup_file"
      return 1
    fi
  fi
  return 0
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
    echo -e "${RED}Failed to create iCloud directory${NC}"
    log_message "ERROR" "Failed to create directory: $(dirname "$ICLOUD_ZSHRC")"
    exit 1
  fi
  
  # If iCloud .zshrc doesn't exist, copy from dotfiles
  if [ ! -f "$ICLOUD_ZSHRC" ]; then
    echo -e "${YELLOW}Creating .zshrc in iCloud Drive${NC}"
    if ! check_permissions "$ICLOUD_ZSHRC"; then
      log_message "ERROR" "No write permission for iCloud directory"
      exit 1
    fi
    if ! cp "$DOTFILES_ZSHRC" "$ICLOUD_ZSHRC" 2>/dev/null; then
      echo -e "${RED}Failed to copy .zshrc to iCloud Drive${NC}"
      log_message "ERROR" "Failed to copy $DOTFILES_ZSHRC to $ICLOUD_ZSHRC"
      exit 1
    fi
  fi
  
  # Check if home .zshrc is already correctly symlinked
  symlink_correct=false
  if [ -L "$HOME_ZSHRC" ]; then
    # Use readlink for better symlink resolution
    current_target="$(readlink "$HOME_ZSHRC" 2>/dev/null)"
    if [ "$current_target" = "$ICLOUD_ZSHRC" ] || [ "$(cd "$(dirname "$HOME_ZSHRC")" && realpath "$current_target" 2>/dev/null)" = "$(realpath "$ICLOUD_ZSHRC" 2>/dev/null)" ]; then
      echo -e "${GREEN}.zshrc is already correctly symlinked to iCloud${NC}"
      symlink_correct=true
    else
      log_message "INFO" "Symlink exists but points to wrong target: $current_target"
    fi
  fi
  
  if [ "$symlink_correct" = false ]; then
    # Backup existing .zshrc if needed
    if ! backup_zshrc; then
      log_message "WARN" "Backup failed, continuing with caution"
    fi
    
    # Remove existing .zshrc (file or wrong symlink)
    if ! rm -f "$HOME_ZSHRC" 2>/dev/null; then
      echo -e "${RED}Failed to remove existing .zshrc${NC}"
      log_message "ERROR" "Failed to remove $HOME_ZSHRC"
      exit 1
    fi
    
    # Create symlink to iCloud
    if ! check_permissions "$HOME_ZSHRC"; then
      log_message "ERROR" "No write permission for home directory"
      exit 1
    fi
    if ! ln -s "$ICLOUD_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
      echo -e "${RED}Failed to create symlink to iCloud Drive${NC}"
      log_message "ERROR" "Failed to create symlink from $HOME_ZSHRC to $ICLOUD_ZSHRC"
      exit 1
    fi
    echo -e "${GREEN}Created symlink: ~/.zshrc → iCloud Drive${NC}"
  fi
  
  # Keep dotfiles version in sync
  if ! diff -q "$ICLOUD_ZSHRC" "$DOTFILES_ZSHRC" >/dev/null 2>&1; then
    echo -e "${YELLOW}Syncing iCloud version to dotfiles${NC}"
    if ! check_permissions "$DOTFILES_ZSHRC"; then
      echo -e "${RED}No write permission for dotfiles, continuing anyway${NC}"
      log_message "WARN" "No write permission for $DOTFILES_ZSHRC"
    elif ! cp "$ICLOUD_ZSHRC" "$DOTFILES_ZSHRC" 2>/dev/null; then
      echo -e "${RED}Failed to sync to dotfiles, continuing anyway${NC}"
      log_message "WARN" "Failed to copy $ICLOUD_ZSHRC to $DOTFILES_ZSHRC"
    else
      echo -e "${GREEN}Dotfiles .zshrc updated${NC}"
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
      echo -e "${GREEN}.zshrc is up to date${NC}"
    else
      # Backup and update
      if ! backup_zshrc; then
        log_message "WARN" "Backup failed, continuing with caution"
      fi
      if ! check_permissions "$HOME_ZSHRC"; then
        echo -e "${RED}No write permission for home directory${NC}"
        log_message "ERROR" "No write permission for $HOME_ZSHRC"
        exit 1
      fi
      if ! cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
        echo -e "${RED}Failed to update .zshrc from dotfiles${NC}"
        log_message "ERROR" "Failed to copy $DOTFILES_ZSHRC to $HOME_ZSHRC"
        exit 1
      fi
      echo -e "${GREEN}Updated .zshrc from dotfiles${NC}"
    fi
  else
    # Remove any symlink and copy from dotfiles
    if ! rm -f "$HOME_ZSHRC" 2>/dev/null; then
      echo -e "${RED}Failed to remove existing .zshrc${NC}"
      log_message "ERROR" "Failed to remove $HOME_ZSHRC"
      exit 1
    fi
    if ! check_permissions "$HOME_ZSHRC"; then
      echo -e "${RED}No write permission for home directory${NC}"
      log_message "ERROR" "No write permission for $HOME_ZSHRC"
      exit 1
    fi
    if ! cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
      echo -e "${RED}Failed to install .zshrc from dotfiles${NC}"
      log_message "ERROR" "Failed to copy $DOTFILES_ZSHRC to $HOME_ZSHRC"
      exit 1
    fi
    echo -e "${GREEN}Installed .zshrc from dotfiles${NC}"
  fi
  
  echo ""
  echo -e "${BLUE}Setup: Dotfiles only (no iCloud)${NC}"
  echo "Edit .zshrc in dotfiles repo and run this script to update"
fi

# Final check
if [ -f "$HOME_ZSHRC" ] || [ -L "$HOME_ZSHRC" ]; then
  echo ""
  echo -e "${GREEN}.zshrc setup complete!${NC}"
  
  # Update the claude-sync alias path to be relative to home
  if grep -q "claude-sync.*boblbee/scripts/claude-sync.sh" "$HOME_ZSHRC"; then
    echo ""
    echo "Note: claude-sync alias detected"
    echo "You may need to source your .zshrc for changes to take effect:"
    echo "  source ~/.zshrc"
  fi
else
  echo ""
  echo -e "${RED}Setup failed - please check permissions${NC}"
  exit 1
fi