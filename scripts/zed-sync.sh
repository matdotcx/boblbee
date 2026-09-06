#!/usr/bin/env bash

#########################################################
# Title: zed-sync
# Description: Sync Zed editor config and themes (bidirectional)
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

if ! is_macos; then
    echo "Zed sync is macOS-only, skipping."
    exit 0
fi

# Paths
ZED_CONFIG_DIR="$HOME/.config/zed"
DOTFILES_ZED_DIR="$DOTFILES_DIR/assets/zed"

# Config files to sync (relative to their respective root dirs)
CONFIG_FILES=(
    "settings.json"
    "keymap.json"
)

echo "=== Zed Config Sync ==="
echo ""

# Ensure local Zed config directory exists
mkdir -p "$ZED_CONFIG_DIR" 2>/dev/null

# Ensure dotfiles Zed directory exists
mkdir -p "$DOTFILES_ZED_DIR" 2>/dev/null

# Sync each config file (bidirectional, newest wins)
for config_file in "${CONFIG_FILES[@]}"; do
    sync_file_2way "$DOTFILES_ZED_DIR/$config_file" \
                   "$ZED_CONFIG_DIR/$config_file" \
                   "$config_file"
done

# Sync themes (bidirectional)
echo ""
echo "=== Zed Theme Sync ==="
echo ""

mkdir -p "$DOTFILES_ZED_DIR/themes" 2>/dev/null
sync_dir_2way "$DOTFILES_ZED_DIR/themes" "$ZED_CONFIG_DIR/themes" "theme" "Themes"

# Commit any changes
commit_dotfiles_changes "Update zed config from local" assets/zed

echo ""
echo -e "${GREEN}Zed config setup complete!${NC}"
