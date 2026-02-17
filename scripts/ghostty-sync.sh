#!/usr/bin/env bash

#########################################################
# Title: ghostty-sync
# Description: Sync Ghostty terminal config between dotfiles and Application Support
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source OS detection
source "$(dirname "$0")/detect-os.sh"

if ! is_macos; then
  echo "Ghostty sync is macOS-only, skipping."
  exit 0
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Paths
GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
GHOSTTY_CONFIG="$GHOSTTY_DIR/config"
DOTFILES_CONFIG="$DOTFILES_DIR/assets/ghostty-config"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Ghostty Config Sync ==="
echo ""

# Check if source config exists in dotfiles
if [ ! -f "$DOTFILES_CONFIG" ]; then
  echo -e "${RED}✗ Source file not found: $DOTFILES_CONFIG${NC}"
  echo "Please ensure the ghostty-config file exists in the assets directory"
  exit 1
fi

# Function to get file modification time (returns epoch seconds)
get_file_mtime() {
  local file="$1"
  if [ -f "$file" ]; then
    stat -f %m "$file" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

# Function to commit changes to git repo
commit_dotfiles_changes() {
  local commit_msg="$1"
  cd "$DOTFILES_DIR" || return 1

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git add assets/ghostty-config 2>/dev/null; then
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
    fi
  fi
}

# Ensure Ghostty config directory exists
if [ ! -d "$GHOSTTY_DIR" ]; then
  echo -e "${YELLOW}Creating Ghostty config directory${NC}"
  if ! mkdir -p "$GHOSTTY_DIR" 2>/dev/null; then
    echo -e "${RED}Failed to create directory: $GHOSTTY_DIR${NC}"
    exit 1
  fi
fi

# If no local config exists yet, install from dotfiles
if [ ! -f "$GHOSTTY_CONFIG" ]; then
  echo -e "${YELLOW}Installing Ghostty config from dotfiles${NC}"
  if cp "$DOTFILES_CONFIG" "$GHOSTTY_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}Ghostty config installed${NC}"
  else
    echo -e "${RED}Failed to install Ghostty config${NC}"
    exit 1
  fi
  echo ""
  echo -e "${GREEN}Ghostty config setup complete!${NC}"
  exit 0
fi

# Both files exist — sync the newest
DOTFILES_MTIME=$(get_file_mtime "$DOTFILES_CONFIG")
LOCAL_MTIME=$(get_file_mtime "$GHOSTTY_CONFIG")

if diff -q "$DOTFILES_CONFIG" "$GHOSTTY_CONFIG" >/dev/null 2>&1; then
  echo -e "${GREEN}Ghostty config is already in sync${NC}"
elif [ "$LOCAL_MTIME" -gt "$DOTFILES_MTIME" ]; then
  echo -e "${YELLOW}Local config is newer — updating dotfiles${NC}"
  if cp "$GHOSTTY_CONFIG" "$DOTFILES_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}Dotfiles updated${NC}"
    commit_dotfiles_changes "Update ghostty config from local"
  else
    echo -e "${RED}Failed to update dotfiles${NC}"
    exit 1
  fi
else
  echo -e "${YELLOW}Dotfiles config is newer — updating local${NC}"
  if cp "$DOTFILES_CONFIG" "$GHOSTTY_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}Local Ghostty config updated${NC}"
  else
    echo -e "${RED}Failed to update local config${NC}"
    exit 1
  fi
fi

echo ""
echo -e "${GREEN}Ghostty config setup complete!${NC}"
