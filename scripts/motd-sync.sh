#!/usr/bin/env bash

#########################################################
# Title: motd-sync
# Description: Smart .motd sync — copy strategy (same as zshrc-sync)
# Source: https://github.com/matdotcx/boblbee
#
# ~/.motd is a real local file (not a symlink).
# iCloud is a sync participant, not a live mount.
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

# Paths
ICLOUD_MOTD="$ICLOUD_SYNC_PATH/.motd"
DOTFILES_MOTD="$DOTFILES_DIR/assets/.motd"
HOME_MOTD="$HOME/.motd"

echo "=== Smart .motd Sync Setup ==="
echo ""

sync_dotfile ".motd" "$HOME_MOTD" "$DOTFILES_MOTD" "$ICLOUD_MOTD" "assets/.motd"

# Final check
if [ -f "$HOME_MOTD" ] || [ -L "$HOME_MOTD" ]; then
    echo ""
    echo -e "${GREEN}.motd setup complete!${NC}"
else
    echo ""
    echo -e "${RED}Setup failed - please check permissions${NC}"
    exit 1
fi
