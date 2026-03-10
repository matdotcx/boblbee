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

# If no local config exists yet, install from dotfiles
if [ ! -f "$GHOSTTY_CONFIG" ]; then
    echo -e "${YELLOW}Installing Ghostty config from dotfiles${NC}"
    if cp "$DOTFILES_CONFIG" "$GHOSTTY_CONFIG" 2>/dev/null; then
        echo -e "${GREEN}Ghostty config installed${NC}"
    else
        echo -e "${RED}Failed to install Ghostty config${NC}"
        exit 1
    fi
else
    # Both files exist — sync the newest
    if diff -q "$DOTFILES_CONFIG" "$GHOSTTY_CONFIG" >/dev/null 2>&1; then
        echo -e "${GREEN}Ghostty config is already in sync${NC}"
    else
        local_mtime=$(get_file_mtime "$GHOSTTY_CONFIG")
        dotfiles_mtime=$(get_file_mtime "$DOTFILES_CONFIG")

        if [ "$local_mtime" -gt "$dotfiles_mtime" ]; then
            echo -e "${YELLOW}Local config is newer — updating dotfiles${NC}"
            cp "$GHOSTTY_CONFIG" "$DOTFILES_CONFIG" 2>/dev/null || { echo -e "${RED}Failed to update dotfiles${NC}"; exit 1; }
            echo -e "${GREEN}Dotfiles updated${NC}"
        else
            echo -e "${YELLOW}Dotfiles config is newer — updating local${NC}"
            cp "$DOTFILES_CONFIG" "$GHOSTTY_CONFIG" 2>/dev/null || { echo -e "${RED}Failed to update local config${NC}"; exit 1; }
            echo -e "${GREEN}Local Ghostty config updated${NC}"
        fi
    fi
fi

# Sync themes (bidirectional)
echo ""
echo "=== Ghostty Theme Sync ==="
echo ""

if [ -d "$DOTFILES_THEMES_DIR" ]; then
    mkdir -p "$GHOSTTY_THEMES_DIR" 2>/dev/null
    themes_updated=false

    # Dotfiles → local (install new or update older)
    for theme_file in "$DOTFILES_THEMES_DIR"/*; do
        [ -f "$theme_file" ] || continue
        theme_name="$(basename "$theme_file")"
        local_theme="$GHOSTTY_THEMES_DIR/$theme_name"

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
    for local_theme in "$GHOSTTY_THEMES_DIR"/*; do
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
else
    echo -e "${YELLOW}No themes directory in dotfiles, skipping${NC}"
fi

# Commit any changes
commit_dotfiles_changes "Update ghostty config from local" assets/ghostty-config assets/ghostty-themes

echo ""
echo -e "${GREEN}Ghostty config setup complete!${NC}"
