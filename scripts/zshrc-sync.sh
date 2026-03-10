#!/usr/bin/env bash

#########################################################
# Title: zshrc-sync
# Description: Smart .zshrc sync that handles iCloud Drive on macOS and simple sync on Ubuntu
# Source: https://github.com/matdotcx/boblbee
#
# macOS + iCloud strategy: ~/.zshrc is a real local file (not a symlink).
# iCloud is a sync participant for cross-host sharing, not a live mount —
# live symlinks break when iCloud evicts/delays the file on boot.
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

# Paths
ICLOUD_ZSHRC="$ICLOUD_SYNC_PATH/.zshrc"
DOTFILES_ZSHRC="$DOTFILES_DIR/assets/.zshrc"
HOME_ZSHRC="$HOME/.zshrc"

echo "=== Smart .zshrc Sync Setup ==="
echo ""

sync_dotfile ".zshrc" "$HOME_ZSHRC" "$DOTFILES_ZSHRC" "$ICLOUD_ZSHRC" "assets/.zshrc"

# Final check
if [ -f "$HOME_ZSHRC" ] || [ -L "$HOME_ZSHRC" ]; then
    echo ""
    echo -e "${GREEN}.zshrc setup complete!${NC}"
else
    echo ""
    echo -e "${RED}Setup failed - please check permissions${NC}"
    exit 1
fi
