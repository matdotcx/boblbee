#!/usr/bin/env bash

#########################################################
# Title: zshrc-sync
# Description: Smart .zshrc sync that handles iCloud Drive on macOS and simple sync on Ubuntu
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source OS detection
source "$(dirname "$0")/detect-os.sh"

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

# Function to check if iCloud Drive is available AND functional (macOS only)
check_icloud() {
  if ! is_macos; then
    return 1
  fi
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
    if is_macos; then
      stat -f %m "$file" 2>/dev/null || echo "0"
    else
      # Linux/Ubuntu uses different stat format
      stat -c %Y "$file" 2>/dev/null || echo "0"
    fi
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
    if git add assets/.zshrc 2>/dev/null; then
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

# Main logic - platform-specific behavior
if is_ubuntu; then
  echo -e "${BLUE}Ubuntu detected - using simple dotfiles sync${NC}"
  
  # Ubuntu: Simple bidirectional sync between dotfiles and home
  newest_file=$(find_newest_file "$HOME_ZSHRC" "$DOTFILES_ZSHRC")
  
  if [ -n "$newest_file" ]; then
    echo -e "${BLUE}Newest version found: $(basename "$newest_file")${NC}"
    
    # Sync to the other location
    if [ "$newest_file" = "$HOME_ZSHRC" ] && ! diff -q "$HOME_ZSHRC" "$DOTFILES_ZSHRC" >/dev/null 2>&1; then
      echo -e "${YELLOW}Updating dotfiles from home directory${NC}"
      if check_permissions "$DOTFILES_ZSHRC" && cp "$HOME_ZSHRC" "$DOTFILES_ZSHRC" 2>/dev/null; then
        echo -e "${GREEN}Dotfiles updated${NC}"
        commit_dotfiles_changes "Update .zshrc from home directory"
      else
        echo -e "${RED}Failed to update dotfiles${NC}"
        log_message "ERROR" "Failed to copy $HOME_ZSHRC to $DOTFILES_ZSHRC"
        exit 1
      fi
    elif [ "$newest_file" = "$DOTFILES_ZSHRC" ] && ! diff -q "$DOTFILES_ZSHRC" "$HOME_ZSHRC" >/dev/null 2>&1; then
      echo -e "${YELLOW}Updating home directory from dotfiles${NC}"
      if ! backup_zshrc; then
        log_message "WARN" "Backup failed, continuing with caution"
      fi
      if check_permissions "$HOME_ZSHRC" && cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
        echo -e "${GREEN}Home .zshrc updated${NC}"
      else
        echo -e "${RED}Failed to update home .zshrc${NC}"
        log_message "ERROR" "Failed to copy $DOTFILES_ZSHRC to $HOME_ZSHRC"
        exit 1
      fi
    else
      echo -e "${GREEN}Files are already in sync${NC}"
    fi
  else
    # No files exist, create from dotfiles
    if [ -f "$DOTFILES_ZSHRC" ]; then
      echo -e "${YELLOW}Installing .zshrc from dotfiles${NC}"
      if check_permissions "$HOME_ZSHRC" && cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
        echo -e "${GREEN}Installed .zshrc from dotfiles${NC}"
      else
        echo -e "${RED}Failed to install .zshrc from dotfiles${NC}"
        log_message "ERROR" "Failed to copy $DOTFILES_ZSHRC to $HOME_ZSHRC"
        exit 1
      fi
    else
      echo -e "${RED}No .zshrc found in dotfiles${NC}"
      exit 1
    fi
  fi
  
  echo ""
  echo -e "${BLUE}Setup: Dotfiles ↔ Home (bidirectional sync)${NC}"
  echo "Edit .zshrc in either location and run this script to sync"
  
elif check_icloud; then
  echo -e "${BLUE}iCloud Drive detected${NC}"
  
  # Ensure iCloud directory structure exists
  if ! mkdir -p "$(dirname "$ICLOUD_ZSHRC")" 2>/dev/null; then
    echo -e "${RED}Failed to create iCloud directory${NC}"
    log_message "ERROR" "Failed to create directory: $(dirname "$ICLOUD_ZSHRC")"
    exit 1
  fi
  
  # Create iCloud .zshrc from dotfiles if it doesn't exist
  if [ ! -f "$ICLOUD_ZSHRC" ]; then
    echo -e "${YELLOW}Creating .zshrc in iCloud Drive from dotfiles${NC}"
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
  
  # Find the newest version among all three locations
  newest_file=$(find_newest_file "$HOME_ZSHRC" "$DOTFILES_ZSHRC" "$ICLOUD_ZSHRC")
  
  if [ -n "$newest_file" ]; then
    echo -e "${BLUE}Newest version found: $(basename "$newest_file")${NC}"
    
    # Sync newest to all other locations
    files_updated=false
    
    # Update dotfiles if needed
    if [ "$newest_file" != "$DOTFILES_ZSHRC" ] && ! diff -q "$newest_file" "$DOTFILES_ZSHRC" >/dev/null 2>&1; then
      echo -e "${YELLOW}Updating dotfiles from $(basename "$newest_file")${NC}"
      if check_permissions "$DOTFILES_ZSHRC" && cp "$newest_file" "$DOTFILES_ZSHRC" 2>/dev/null; then
        echo -e "${GREEN}Dotfiles updated${NC}"
        files_updated=true
        # Commit the change
        if [ "$newest_file" = "$HOME_ZSHRC" ]; then
          commit_dotfiles_changes "Update .zshrc from home directory"
        elif [ "$newest_file" = "$ICLOUD_ZSHRC" ]; then
          commit_dotfiles_changes "Update .zshrc from iCloud Drive"
        fi
      else
        echo -e "${RED}Failed to update dotfiles${NC}"
        log_message "ERROR" "Failed to copy $newest_file to $DOTFILES_ZSHRC"
      fi
    fi
    
    # Update iCloud if needed
    if [ "$newest_file" != "$ICLOUD_ZSHRC" ] && ! diff -q "$newest_file" "$ICLOUD_ZSHRC" >/dev/null 2>&1; then
      echo -e "${YELLOW}Updating iCloud from $(basename "$newest_file")${NC}"
      if check_permissions "$ICLOUD_ZSHRC" && cp "$newest_file" "$ICLOUD_ZSHRC" 2>/dev/null; then
        echo -e "${GREEN}iCloud updated${NC}"
        files_updated=true
      else
        echo -e "${RED}Failed to update iCloud${NC}"
        log_message "ERROR" "Failed to copy $newest_file to $ICLOUD_ZSHRC"
      fi
    fi
    
    if [ "$files_updated" = false ]; then
      echo -e "${GREEN}All versions are already in sync${NC}"
    fi
  fi
  
  # Ensure home .zshrc is symlinked to iCloud
  symlink_correct=false
  if [ -L "$HOME_ZSHRC" ]; then
    current_target="$(readlink "$HOME_ZSHRC" 2>/dev/null)"
    if [ "$current_target" = "$ICLOUD_ZSHRC" ] || [ "$(cd "$(dirname "$HOME_ZSHRC")" && realpath "$current_target" 2>/dev/null)" = "$(realpath "$ICLOUD_ZSHRC" 2>/dev/null)" ]; then
      echo -e "${GREEN}.zshrc is already correctly symlinked to iCloud${NC}"
      symlink_correct=true
    else
      log_message "INFO" "Symlink exists but points to wrong target: $current_target"
    fi
  fi
  
  if [ "$symlink_correct" = false ]; then
    # Backup existing .zshrc if it's a regular file
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
    # Verify target file exists before creating symlink
    if [ ! -f "$ICLOUD_ZSHRC" ]; then
      echo -e "${RED}Cannot create symlink - iCloud target file does not exist${NC}"
      log_message "ERROR" "iCloud file $ICLOUD_ZSHRC does not exist, falling back to dotfiles-only mode"
      # Fall through to non-iCloud mode below
    else
      if ! ln -s "$ICLOUD_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
        echo -e "${RED}Failed to create symlink to iCloud Drive${NC}"
        log_message "ERROR" "Failed to create symlink from $HOME_ZSHRC to $ICLOUD_ZSHRC"
        exit 1
      fi
      echo -e "${GREEN}Created symlink: ~/.zshrc → iCloud Drive${NC}"
    fi
  fi
  
  echo ""
  echo -e "${BLUE}Setup: iCloud Drive (primary) ↔ Dotfiles (backup)${NC}"
  echo "Edit .zshrc in iCloud Drive for immediate effect"
  echo "Changes will be automatically synced to dotfiles and committed"
  
else
  echo -e "${BLUE}macOS without iCloud Drive - using dotfiles only${NC}"
  
  # Find newest between home and dotfiles
  newest_file=$(find_newest_file "$HOME_ZSHRC" "$DOTFILES_ZSHRC")
  
  if [ -n "$newest_file" ]; then
    echo -e "${BLUE}Newest version found: $(basename "$newest_file")${NC}"
    
    # Sync to the other location
    if [ "$newest_file" = "$HOME_ZSHRC" ] && ! diff -q "$HOME_ZSHRC" "$DOTFILES_ZSHRC" >/dev/null 2>&1; then
      echo -e "${YELLOW}Updating dotfiles from home directory${NC}"
      if check_permissions "$DOTFILES_ZSHRC" && cp "$HOME_ZSHRC" "$DOTFILES_ZSHRC" 2>/dev/null; then
        echo -e "${GREEN}Dotfiles updated${NC}"
        commit_dotfiles_changes "Update .zshrc from home directory"
      else
        echo -e "${RED}Failed to update dotfiles${NC}"
        log_message "ERROR" "Failed to copy $HOME_ZSHRC to $DOTFILES_ZSHRC"
        exit 1
      fi
    elif [ "$newest_file" = "$DOTFILES_ZSHRC" ] && ! diff -q "$DOTFILES_ZSHRC" "$HOME_ZSHRC" >/dev/null 2>&1; then
      echo -e "${YELLOW}Updating home directory from dotfiles${NC}"
      if ! backup_zshrc; then
        log_message "WARN" "Backup failed, continuing with caution"
      fi
      if check_permissions "$HOME_ZSHRC" && cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
        echo -e "${GREEN}Home .zshrc updated${NC}"
      else
        echo -e "${RED}Failed to update home .zshrc${NC}"
        log_message "ERROR" "Failed to copy $DOTFILES_ZSHRC to $HOME_ZSHRC"
        exit 1
      fi
    else
      echo -e "${GREEN}Files are already in sync${NC}"
    fi
  else
    # No files exist, create from dotfiles
    if [ -f "$DOTFILES_ZSHRC" ]; then
      echo -e "${YELLOW}Installing .zshrc from dotfiles${NC}"
      if check_permissions "$HOME_ZSHRC" && cp "$DOTFILES_ZSHRC" "$HOME_ZSHRC" 2>/dev/null; then
        echo -e "${GREEN}Installed .zshrc from dotfiles${NC}"
      else
        echo -e "${RED}Failed to install .zshrc from dotfiles${NC}"
        log_message "ERROR" "Failed to copy $DOTFILES_ZSHRC to $HOME_ZSHRC"
        exit 1
      fi
    else
      echo -e "${RED}No .zshrc found in dotfiles${NC}"
      exit 1
    fi
  fi
  
  echo ""
  echo -e "${BLUE}Setup: Dotfiles ↔ Home (bidirectional sync)${NC}"
  echo "Edit .zshrc in either location and run this script to sync"
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