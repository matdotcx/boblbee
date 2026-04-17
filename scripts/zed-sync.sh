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
    local_file="$ZED_CONFIG_DIR/$config_file"
    dotfiles_file="$DOTFILES_ZED_DIR/$config_file"

    if [ ! -f "$dotfiles_file" ] && [ ! -f "$local_file" ]; then
        echo -e "${YELLOW}No $config_file found in dotfiles or locally — skipping${NC}"
        continue
    fi

    if [ ! -f "$local_file" ] && [ -f "$dotfiles_file" ]; then
        echo -e "${YELLOW}Installing $config_file from dotfiles${NC}"
        cp "$dotfiles_file" "$local_file" 2>/dev/null && \
            echo -e "${GREEN}$config_file installed${NC}"
        continue
    fi

    if [ -f "$local_file" ] && [ ! -f "$dotfiles_file" ]; then
        echo -e "${YELLOW}Pulling $config_file to dotfiles${NC}"
        cp "$local_file" "$dotfiles_file" 2>/dev/null && \
            echo -e "${GREEN}$config_file added to dotfiles${NC}"
        continue
    fi

    # Both exist — sync newest
    if diff -q "$dotfiles_file" "$local_file" >/dev/null 2>&1; then
        echo -e "${GREEN}$config_file is already in sync${NC}"
    else
        local_mtime=$(get_file_mtime "$local_file")
        dotfiles_mtime=$(get_file_mtime "$dotfiles_file")

        if [ "$local_mtime" -gt "$dotfiles_mtime" ]; then
            echo -e "${YELLOW}Local $config_file is newer — updating dotfiles${NC}"
            cp "$local_file" "$dotfiles_file" 2>/dev/null || { echo -e "${RED}Failed to update dotfiles${NC}"; continue; }
            echo -e "${GREEN}Dotfiles updated${NC}"
        else
            echo -e "${YELLOW}Dotfiles $config_file is newer — updating local${NC}"
            cp "$dotfiles_file" "$local_file" 2>/dev/null || { echo -e "${RED}Failed to update local config${NC}"; continue; }
            echo -e "${GREEN}Local $config_file updated${NC}"
        fi
    fi
done

# Sync themes (bidirectional)
echo ""
echo "=== Zed Theme Sync ==="
echo ""

ZED_THEMES_DIR="$ZED_CONFIG_DIR/themes"
DOTFILES_THEMES_DIR="$DOTFILES_ZED_DIR/themes"

mkdir -p "$ZED_THEMES_DIR" 2>/dev/null
mkdir -p "$DOTFILES_THEMES_DIR" 2>/dev/null

themes_updated=false

# Dotfiles → local (install new or update older)
for theme_file in "$DOTFILES_THEMES_DIR"/*; do
    [ -f "$theme_file" ] || continue
    theme_name="$(basename "$theme_file")"
    local_theme="$ZED_THEMES_DIR/$theme_name"

    if [ ! -f "$local_theme" ]; then
        cp "$theme_file" "$local_theme" 2>/dev/null && \
            echo -e "${GREEN}Installed theme: $theme_name${NC}" && themes_updated=true
    elif ! diff -q "$theme_file" "$local_theme" >/dev/null 2>&1; then
        local_mtime=$(get_file_mtime "$local_theme")
        dotfiles_mtime=$(get_file_mtime "$theme_file")
        if [ "$dotfiles_mtime" -gt "$local_mtime" ]; then
            cp "$theme_file" "$local_theme" 2>/dev/null && \
                echo -e "${GREEN}Updated local theme: $theme_name${NC}" && themes_updated=true
        fi
    fi
done

# Local → dotfiles (pull back newer local themes)
for local_theme in "$ZED_THEMES_DIR"/*; do
    [ -f "$local_theme" ] || continue
    theme_name="$(basename "$local_theme")"
    dotfiles_theme="$DOTFILES_THEMES_DIR/$theme_name"

    if [ ! -f "$dotfiles_theme" ]; then
        cp "$local_theme" "$dotfiles_theme" 2>/dev/null && \
            echo -e "${GREEN}New local theme pulled to dotfiles: $theme_name${NC}" && themes_updated=true
    elif ! diff -q "$local_theme" "$dotfiles_theme" >/dev/null 2>&1; then
        local_mtime=$(get_file_mtime "$local_theme")
        dotfiles_mtime=$(get_file_mtime "$dotfiles_theme")
        if [ "$local_mtime" -gt "$dotfiles_mtime" ]; then
            cp "$local_theme" "$dotfiles_theme" 2>/dev/null && \
                echo -e "${GREEN}Updated dotfiles theme: $theme_name${NC}" && themes_updated=true
        fi
    fi
done

if [ "$themes_updated" = false ]; then
    echo -e "${GREEN}Themes are already in sync${NC}"
fi

# Commit any changes
commit_dotfiles_changes "Update zed config from local" assets/zed

echo ""
echo -e "${GREEN}Zed config setup complete!${NC}"
