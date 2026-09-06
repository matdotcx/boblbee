#!/usr/bin/env bash

#########################################################
# Title: tmux-sync
# Description: Sync tmux config and themes between dotfiles and ~/.config/tmux
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

# Paths
TMUX_CONFIG_DIR="$HOME/.config/tmux"
HOME_TMUX_CONF="$HOME/.tmux.conf"
DOTFILES_TMUX="$DOTFILES_DIR/assets/tmux.conf"
DOTFILES_TMUX_BASE="$DOTFILES_DIR/assets/tmux-base.conf"

# Theme files
DOTFILES_THEME_DARK="$DOTFILES_DIR/assets/tmux-theme-dark.conf"
DOTFILES_THEME_LIGHT="$DOTFILES_DIR/assets/tmux-theme-light.conf"

echo "=== tmux Config Sync ==="
echo ""

# Check if source config exists in dotfiles
if [ ! -f "$DOTFILES_TMUX" ]; then
    echo -e "${RED}Source file not found: $DOTFILES_TMUX${NC}"
    echo "Please ensure the tmux.conf file exists in the assets directory"
    exit 1
fi

# Ensure tmux config directory exists
mkdir -p "$TMUX_CONFIG_DIR" 2>/dev/null

# Sync main tmux.conf to ~/.tmux.conf
echo "--- Main config ---"
sync_file_2way "$DOTFILES_TMUX" "$HOME_TMUX_CONF" "tmux.conf"

# Sync base config
echo ""
echo "--- Base config ---"
sync_file_2way "$DOTFILES_TMUX_BASE" "$TMUX_CONFIG_DIR/tmux-base.conf" "tmux-base.conf"

# Sync themes
echo ""
echo "--- Themes ---"
sync_file_2way "$DOTFILES_THEME_DARK" "$TMUX_CONFIG_DIR/tmux-theme-dark.conf" "tmux-theme-dark.conf"
sync_file_2way "$DOTFILES_THEME_LIGHT" "$TMUX_CONFIG_DIR/tmux-theme-light.conf" "tmux-theme-light.conf"

# If local files were newer, commit changes back to dotfiles
commit_dotfiles_changes "Update tmux config from local" \
    assets/tmux.conf assets/tmux-base.conf assets/tmux-theme-dark.conf assets/tmux-theme-light.conf

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
echo "To switch themes, use prefix + t (Ctrl-b t) inside tmux."
