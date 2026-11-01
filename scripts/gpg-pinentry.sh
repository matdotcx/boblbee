#!/usr/bin/env bash

#########################################################
# Title: gpg-pinentry
# Description: Point gpg-agent at a pinentry that works both over SSH and at the console
# Source: https://github.com/matdotcx/boblbee
#
# pinentry-mac can't reach the window server in an SSH session and instantly
# cancels, which makes every signed commit fail. The pinentry-auto wrapper
# picks pinentry-curses when the calling shell set PINENTRY_USER_DATA=USE_CURSES
# (.zshrc does this over SSH) and keeps the GUI pinentry-mac, with its keychain
# integration, everywhere else. pinentry-curses itself comes from MacPorts
# (macports.sh installs the `pinentry` port).
#########################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

echo "=== GPG pinentry Setup ==="
echo ""

if ! is_macos; then
    # Ubuntu's default pinentry is already terminal-capable; nothing to wire up.
    echo "Not macOS — skipping (the wrapper only matters where pinentry-mac is the default)."
    exit 0
fi

REPO_WRAPPER="$DOTFILES_DIR/assets/pinentry-auto"
LOCAL_WRAPPER="$HOME/.local/bin/pinentry-auto"
AGENT_CONF="$HOME/.gnupg/gpg-agent.conf"

CHANGED=0

# The wrapper is code: repo is the source of truth, local edits are overwritten.
mkdir -p "$HOME/.local/bin"
if cmp -s "$REPO_WRAPPER" "$LOCAL_WRAPPER"; then
    echo -e "${GREEN}✓ pinentry-auto already up to date${NC}"
else
    cp "$REPO_WRAPPER" "$LOCAL_WRAPPER"
    CHANGED=1
    echo -e "${GREEN}✓ Installed pinentry-auto${NC}"
fi
chmod +x "$LOCAL_WRAPPER"

# Point gpg-agent at the wrapper and keep the passphrase cached for an hour —
# the stock 10 minutes means re-typing it mid-session. Any other lines in
# gpg-agent.conf are preserved.
mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"
touch "$AGENT_CONF"
set_agent_option() {
    local key="$1" line="$1 $2"
    if grep -qxF "$line" "$AGENT_CONF"; then
        echo -e "${GREEN}✓ gpg-agent.conf: $key already set${NC}"
    elif grep -q "^$key " "$AGENT_CONF"; then
        sed -i '' "s|^$key .*|$line|" "$AGENT_CONF"
        CHANGED=1
        echo -e "${GREEN}✓ gpg-agent.conf: updated $key${NC}"
    else
        echo "$line" >> "$AGENT_CONF"
        CHANGED=1
        echo -e "${GREEN}✓ gpg-agent.conf: added $key${NC}"
    fi
}
set_agent_option "pinentry-program" "$LOCAL_WRAPPER"
set_agent_option "default-cache-ttl" "3600"

# The curses half of the wrapper comes from MacPorts; warn rather than fail,
# since pinentry-mac still covers console use until it's installed.
if [ ! -x /opt/local/bin/pinentry-curses ]; then
    echo -e "${YELLOW}pinentry-curses not found — signing over SSH won't work until macports.sh installs the pinentry port${NC}"
fi

if [ "$CHANGED" = 1 ] && command -v gpgconf >/dev/null 2>&1; then
    gpgconf --kill gpg-agent 2>/dev/null || true
    echo -e "${GREEN}✓ Restarted gpg-agent${NC}"
fi

echo ""
echo -e "${GREEN}GPG pinentry setup complete!${NC}"
