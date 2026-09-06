#!/usr/bin/env bash

#########################################################
# Title: ghostty-sync
# Description: Sync Ghostty terminal config and themes (bidirectional)
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

if ! is_macos; then
    echo "Ghostty sync is macOS-only, skipping."
    exit 0
fi

# Paths
GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
GHOSTTY_CONFIG="$GHOSTTY_DIR/config"
GHOSTTY_THEMES_DIR="$HOME/.config/ghostty/themes"
DOTFILES_CONFIG="$DOTFILES_DIR/assets/ghostty-config"
DOTFILES_THEMES_DIR="$DOTFILES_DIR/assets/ghostty-themes"

echo "=== Ghostty Config Sync ==="
echo ""

# Check if source config exists in dotfiles
if [ ! -f "$DOTFILES_CONFIG" ]; then
    echo -e "${RED}✗ Source file not found: $DOTFILES_CONFIG${NC}"
    echo "Please ensure the ghostty-config file exists in the assets directory"
    exit 1
fi

# Ensure Ghostty config directory exists
if [ ! -d "$GHOSTTY_DIR" ]; then
    echo -e "${YELLOW}Creating Ghostty config directory${NC}"
    mkdir -p "$GHOSTTY_DIR" 2>/dev/null || { echo -e "${RED}Failed to create directory: $GHOSTTY_DIR${NC}"; exit 1; }
fi

# Sync config two ways, keeping whichever side is newer
sync_file_2way "$DOTFILES_CONFIG" "$GHOSTTY_CONFIG" "Ghostty config" || exit 1

# Sync themes (bidirectional)
echo ""
echo "=== Ghostty Theme Sync ==="
echo ""

sync_dir_2way "$DOTFILES_THEMES_DIR" "$GHOSTTY_THEMES_DIR" "theme" "Themes"

# Commit any changes
commit_dotfiles_changes "Update ghostty config from local" assets/ghostty-config assets/ghostty-themes

echo ""
echo -e "${GREEN}Ghostty config setup complete!${NC}"
