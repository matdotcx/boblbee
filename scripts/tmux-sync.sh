#!/usr/bin/env bash

#########################################################
# Title: tmux-sync
# Description: Sync tmux config and themes between dotfiles and ~/.config/tmux
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source OS detection
source "$(dirname "$0")/detect-os.sh"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Paths
TMUX_CONFIG_DIR="$HOME/.config/tmux"
HOME_TMUX_CONF="$HOME/.tmux.conf"
DOTFILES_TMUX="$DOTFILES_DIR/assets/tmux.conf"
DOTFILES_TMUX_BASE="$DOTFILES_DIR/assets/tmux-base.conf"

# Theme files
DOTFILES_THEME_DARK="$DOTFILES_DIR/assets/tmux-theme-dark.conf"
DOTFILES_THEME_LIGHT="$DOTFILES_DIR/assets/tmux-theme-light.conf"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== tmux Config Sync ==="
echo ""

# Check if source config exists in dotfiles
if [ ! -f "$DOTFILES_TMUX" ]; then
  echo -e "${RED}Source file not found: $DOTFILES_TMUX${NC}"
  echo "Please ensure the tmux.conf file exists in the assets directory"
  exit 1
fi

# Function to get file modification time (returns epoch seconds)
get_file_mtime() {
  local file="$1"
  if [ -f "$file" ]; then
    if is_macos; then
      stat -f %m "$file" 2>/dev/null || echo "0"
    else
      stat -c %Y "$file" 2>/dev/null || echo "0"
    fi
  else
    echo "0"
  fi
}

# Function to commit changes to git repo
commit_dotfiles_changes() {
  local commit_msg="$1"
  cd "$DOTFILES_DIR" || return 1

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git add assets/tmux.conf assets/tmux-base.conf assets/tmux-theme-dark.conf assets/tmux-theme-light.conf 2>/dev/null; then
      if git diff --staged --quiet; then
        echo -e "${BLUE}No changes to commit${NC}"
        return 0
      else
        if git commit -m "$commit_msg" 2>/dev/null; then
          echo -e "${GREEN}Changes committed to git: $commit_msg${NC}"
          return 0
        else
          echo -e "${YELLOW}Git commit failed, but files were updated${NC}"
          return 1
        fi
      fi
    fi
  fi
}

# Function to sync a single config file
sync_file() {
  local src="$1"
  local dst="$2"
  local name="$3"

  if [ ! -f "$src" ]; then
    echo -e "${YELLOW}Skipping $name (source not found)${NC}"
    return 0
  fi

  if [ ! -f "$dst" ]; then
    if cp "$src" "$dst" 2>/dev/null; then
      echo -e "${GREEN}Installed $name${NC}"
    else
      echo -e "${RED}Failed to install $name${NC}"
      return 1
    fi
  elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
    local src_mtime
    local dst_mtime
    src_mtime=$(get_file_mtime "$src")
    dst_mtime=$(get_file_mtime "$dst")

    if [ "$dst_mtime" -gt "$src_mtime" ]; then
      echo -e "${YELLOW}Local $name is newer — updating dotfiles${NC}"
      if cp "$dst" "$src" 2>/dev/null; then
        echo -e "${GREEN}Dotfiles updated for $name${NC}"
      else
        echo -e "${RED}Failed to update dotfiles for $name${NC}"
        return 1
      fi
    else
      echo -e "${YELLOW}Dotfiles $name is newer — updating local${NC}"
      if cp "$src" "$dst" 2>/dev/null; then
        echo -e "${GREEN}Local $name updated${NC}"
      else
        echo -e "${RED}Failed to update local $name${NC}"
        return 1
      fi
    fi
  else
    echo -e "${GREEN}$name is already in sync${NC}"
  fi
}

# Ensure tmux config directory exists
mkdir -p "$TMUX_CONFIG_DIR" 2>/dev/null

# Sync main tmux.conf to ~/.tmux.conf
echo "--- Main config ---"
sync_file "$DOTFILES_TMUX" "$HOME_TMUX_CONF" "tmux.conf"

# Sync base config
echo ""
echo "--- Base config ---"
sync_file "$DOTFILES_TMUX_BASE" "$TMUX_CONFIG_DIR/tmux-base.conf" "tmux-base.conf"

# Sync themes
echo ""
echo "--- Themes ---"
sync_file "$DOTFILES_THEME_DARK" "$TMUX_CONFIG_DIR/tmux-theme-dark.conf" "tmux-theme-dark.conf"
sync_file "$DOTFILES_THEME_LIGHT" "$TMUX_CONFIG_DIR/tmux-theme-light.conf" "tmux-theme-light.conf"

# If local files were newer, commit changes back to dotfiles
commit_dotfiles_changes "Update tmux config from local"

echo ""
echo -e "${GREEN}tmux config setup complete!${NC}"

# Auto-reload any running tmux sessions
if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  tmux source-file "$HOME_TMUX_CONF" 2>/dev/null && \
    echo -e "${GREEN}Active tmux sessions reloaded${NC}" || \
    echo -e "${YELLOW}Could not reload tmux — reload manually with: tmux source-file ~/.tmux.conf${NC}"
else
  echo "No active tmux sessions to reload"
fi

echo ""
echo "To switch themes, edit ~/.tmux.conf and change the theme source line."
