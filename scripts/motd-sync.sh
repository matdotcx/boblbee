#!/usr/bin/env bash

#########################################################
# Title: motd-sync
# Description: Smart .motd sync that handles iCloud Drive
# Source: https://github.com/matdotcx/
#########################################################

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Paths
ICLOUD_MOTD="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ark/Sync/System/.motd"
DOTFILES_MOTD="$DOTFILES_DIR/assets/.motd"
HOME_MOTD="$HOME/.motd"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Smart .motd Sync Setup ==="
echo ""

# Check if source .motd exists
if [ ! -f "$DOTFILES_MOTD" ]; then
  echo -e "${RED}✗ Source file not found: $DOTFILES_MOTD${NC}"
  echo "Please ensure the .motd file exists in the assets directory"
  exit 1
fi

# Function to check if iCloud Drive is available AND functional
check_icloud() {
  local icloud_base="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
  if [ ! -d "$icloud_base" ]; then
    log_message "INFO" "iCloud directory does not exist"
    return 1
  fi
  # Test if we can actually write to iCloud (may exist but not signed in)
  local test_file="$icloud_base/.boblbee_write_test_$$"
  if touch "$test_file" 2>/dev/null; then
    rm -f "$test_file" 2>/dev/null
    return 0
  else
    log_message "INFO" "iCloud exists but not writable (not signed in?)"
    return 1
  fi
}

# Function to log messages with timestamp
log_message() {
  local level="$1"
  local message="$2"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >&2
}

# Function to get file modification time (returns epoch seconds)
get_file_mtime() {
  local file="$1"
  if [ -L "$file" ]; then
    # If it's a symlink, get the target's mtime
    file="$(readlink "$file")"
  fi
  if [ -f "$file" ]; then
    stat -f %m "$file" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# Function to find the newest file among multiple paths
find_newest_file() {
  local newest_file=""
  local newest_time=0
  local current_time
  
  for file in "$@"; do
    if [ -f "$file" ] || [ -L "$file" ]; then
      current_time=$(get_file_mtime "$file")
      if [ "$current_time" -gt "$newest_time" ]; then
        newest_time="$current_time"
        newest_file="$file"
      fi
    fi
  done
  
  echo "$newest_file"
}

# Function to commit changes to git repo
commit_dotfiles_changes() {
  local commit_msg="$1"
  cd "$DOTFILES_DIR" || return 1
  
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git add assets/.motd 2>/dev/null; then
      if git diff --staged --quiet; then
        echo -e "${BLUE}No changes to commit${NC}"
        return 0
      else
        if git commit -m "$commit_msg" 2>/dev/null; then
          echo -e "${GREEN}Changes committed to git: $commit_msg${NC}"
          return 0
        else
          echo -e "${YELLOW}Git commit failed, but file was updated${NC}"
          return 1
        fi
      fi
    else
      echo -e "${YELLOW}Git add failed, but file was updated${NC}"
      return 1
    fi
  else
    echo -e "${BLUE}Not in a git repository, skipping commit${NC}"
    return 0
  fi
}

# Function to backup existing .motd
backup_motd() {
  if [ -f "$HOME_MOTD" ] && [ ! -L "$HOME_MOTD" ]; then
    local backup_file="$HOME_MOTD.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Backing up existing .motd to $backup_file${NC}"
    if cp "$HOME_MOTD" "$backup_file" 2>/dev/null; then
      echo -e "${GREEN}Backup created successfully${NC}"
      return 0
    else
      echo -e "${RED}Backup failed${NC}"
      log_message "ERROR" "Failed to backup $HOME_MOTD to $backup_file"
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
  if ! mkdir -p "$(dirname "$ICLOUD_MOTD")" 2>/dev/null; then
    echo -e "${RED}Failed to create iCloud directory${NC}"
    log_message "ERROR" "Failed to create directory: $(dirname "$ICLOUD_MOTD")"
    exit 1
  fi
  
  # Create iCloud .motd from dotfiles if it doesn't exist
  if [ ! -f "$ICLOUD_MOTD" ]; then
    echo -e "${YELLOW}Creating .motd in iCloud Drive from dotfiles${NC}"
    if ! check_permissions "$ICLOUD_MOTD"; then
      log_message "ERROR" "No write permission for iCloud directory"
      exit 1
    fi
    if ! cp "$DOTFILES_MOTD" "$ICLOUD_MOTD" 2>/dev/null; then
      echo -e "${RED}Failed to copy .motd to iCloud Drive${NC}"
      log_message "ERROR" "Failed to copy $DOTFILES_MOTD to $ICLOUD_MOTD"
      exit 1
    fi
  fi
  
  # Find the newest version among all three locations
  newest_file=$(find_newest_file "$HOME_MOTD" "$DOTFILES_MOTD" "$ICLOUD_MOTD")
  
  if [ -n "$newest_file" ]; then
    echo -e "${BLUE}Newest version found: $(basename "$newest_file")${NC}"
    
    # Sync newest to all other locations
    files_updated=false
    
    # Update dotfiles if needed
    if [ "$newest_file" != "$DOTFILES_MOTD" ] && ! diff -q "$newest_file" "$DOTFILES_MOTD" >/dev/null 2>&1; then
      echo -e "${YELLOW}Updating dotfiles from $(basename "$newest_file")${NC}"
      if check_permissions "$DOTFILES_MOTD" && cp "$newest_file" "$DOTFILES_MOTD" 2>/dev/null; then
        echo -e "${GREEN}Dotfiles updated${NC}"
        files_updated=true
        # Commit the change
        if [ "$newest_file" = "$HOME_MOTD" ]; then
          commit_dotfiles_changes "Update .motd from home directory"
        elif [ "$newest_file" = "$ICLOUD_MOTD" ]; then
          commit_dotfiles_changes "Update .motd from iCloud Drive"
        fi
      else
        echo -e "${RED}Failed to update dotfiles${NC}"
        log_message "ERROR" "Failed to copy $newest_file to $DOTFILES_MOTD"
      fi
    fi
    
    # Update iCloud if needed
    if [ "$newest_file" != "$ICLOUD_MOTD" ] && ! diff -q "$newest_file" "$ICLOUD_MOTD" >/dev/null 2>&1; then
      echo -e "${YELLOW}Updating iCloud from $(basename "$newest_file")${NC}"
      if check_permissions "$ICLOUD_MOTD" && cp "$newest_file" "$ICLOUD_MOTD" 2>/dev/null; then
        echo -e "${GREEN}iCloud updated${NC}"
        files_updated=true
      else
        echo -e "${RED}Failed to update iCloud${NC}"
        log_message "ERROR" "Failed to copy $newest_file to $ICLOUD_MOTD"
      fi
    fi
    
    if [ "$files_updated" = false ]; then
      echo -e "${GREEN}All versions are already in sync${NC}"
    fi
  fi
  
  # Ensure home .motd is symlinked to iCloud
  symlink_correct=false
  if [ -L "$HOME_MOTD" ]; then
    current_target="$(readlink "$HOME_MOTD" 2>/dev/null)"
    if [ "$current_target" = "$ICLOUD_MOTD" ] || [ "$(cd "$(dirname "$HOME_MOTD")" && realpath "$current_target" 2>/dev/null)" = "$(realpath "$ICLOUD_MOTD" 2>/dev/null)" ]; then
      echo -e "${GREEN}.motd is already correctly symlinked to iCloud${NC}"
      symlink_correct=true
    else
      log_message "INFO" "Symlink exists but points to wrong target: $current_target"
    fi
  fi
  
  if [ "$symlink_correct" = false ]; then
    # Backup existing .motd if it's a regular file
    if ! backup_motd; then
      log_message "WARN" "Backup failed, continuing with caution"
    fi
    
    # Remove existing .motd (file or wrong symlink)
    if ! rm -f "$HOME_MOTD" 2>/dev/null; then
      echo -e "${RED}Failed to remove existing .motd${NC}"
      log_message "ERROR" "Failed to remove $HOME_MOTD"
      exit 1
    fi
    
    # Create symlink to iCloud
    if ! check_permissions "$HOME_MOTD"; then
      log_message "ERROR" "No write permission for home directory"
      exit 1
    fi
    # Verify target file exists before creating symlink
    if [ ! -f "$ICLOUD_MOTD" ]; then
      echo -e "${RED}Cannot create symlink - iCloud target file does not exist${NC}"
      log_message "ERROR" "iCloud file $ICLOUD_MOTD does not exist"
    else
      if ! ln -s "$ICLOUD_MOTD" "$HOME_MOTD" 2>/dev/null; then
        echo -e "${RED}Failed to create symlink to iCloud Drive${NC}"
        log_message "ERROR" "Failed to create symlink from $HOME_MOTD to $ICLOUD_MOTD"
        exit 1
      fi
      echo -e "${GREEN}Created symlink: ~/.motd → iCloud Drive${NC}"
    fi
  fi
  
  echo ""
  echo -e "${BLUE}Setup: iCloud Drive (primary) ↔ Dotfiles (backup)${NC}"
  echo "Edit .motd in iCloud Drive for immediate effect"
  echo "Changes will be automatically synced to dotfiles and committed"
  
else
  echo -e "${BLUE}No iCloud Drive detected - using dotfiles only${NC}"
  
  # Check if home .motd exists and copy to dotfiles if needed
  if [ -f "$HOME_MOTD" ] && [ ! -L "$HOME_MOTD" ] && [ ! -f "$DOTFILES_MOTD" ]; then
    echo -e "${YELLOW}Copying existing .motd to dotfiles${NC}"
    if check_permissions "$DOTFILES_MOTD" && cp "$HOME_MOTD" "$DOTFILES_MOTD" 2>/dev/null; then
      echo -e "${GREEN}Copied .motd to dotfiles${NC}"
      commit_dotfiles_changes "Add .motd from home directory"
    else
      echo -e "${RED}Failed to copy .motd to dotfiles${NC}"
      log_message "ERROR" "Failed to copy $HOME_MOTD to $DOTFILES_MOTD"
      exit 1
    fi
  fi
  
  # Ensure home .motd is symlinked to dotfiles
  symlink_correct=false
  if [ -L "$HOME_MOTD" ]; then
    current_target="$(readlink "$HOME_MOTD" 2>/dev/null)"
    if [ "$current_target" = "$DOTFILES_MOTD" ] || [ "$(cd "$(dirname "$HOME_MOTD")" && realpath "$current_target" 2>/dev/null)" = "$(realpath "$DOTFILES_MOTD" 2>/dev/null)" ]; then
      echo -e "${GREEN}.motd is already correctly symlinked to dotfiles${NC}"
      symlink_correct=true
    else
      log_message "INFO" "Symlink exists but points to wrong target: $current_target"
    fi
  fi
  
  if [ "$symlink_correct" = false ]; then
    # Backup existing .motd if it's a regular file
    if ! backup_motd; then
      log_message "WARN" "Backup failed, continuing with caution"
    fi
    
    # Remove existing .motd (file or wrong symlink)
    if ! rm -f "$HOME_MOTD" 2>/dev/null; then
      echo -e "${RED}Failed to remove existing .motd${NC}"
      log_message "ERROR" "Failed to remove $HOME_MOTD"
      exit 1
    fi
    
    # Create symlink to dotfiles
    if ! check_permissions "$HOME_MOTD"; then
      log_message "ERROR" "No write permission for home directory"
      exit 1
    fi
    if ! ln -s "$DOTFILES_MOTD" "$HOME_MOTD" 2>/dev/null; then
      echo -e "${RED}Failed to create symlink to dotfiles${NC}"
      log_message "ERROR" "Failed to create symlink from $HOME_MOTD to $DOTFILES_MOTD"
      exit 1
    fi
    echo -e "${GREEN}Created symlink: ~/.motd → dotfiles${NC}"
  fi
  
  echo ""
  echo -e "${BLUE}Setup: ~/.motd → Dotfiles (symlinked)${NC}"
  echo "Edit .motd in dotfiles and changes take effect immediately"
fi

# Final check
if [ -f "$HOME_MOTD" ] || [ -L "$HOME_MOTD" ]; then
  echo ""
  echo -e "${GREEN}.motd setup complete!${NC}"
else
  echo ""
  echo -e "${RED}Setup failed - please check permissions${NC}"
  exit 1
fi