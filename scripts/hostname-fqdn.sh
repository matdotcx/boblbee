#!/usr/bin/env bash

#########################################################
# Title: hostname-fqdn
# Description: Set macOS HostName to FQDN using DNS search domain
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

echo "=== Hostname Setup ==="
echo ""

if ! is_macos; then
  echo -e "${YELLOW}Skipping - macOS only${NC}"
  exit 0
fi

# Accept optional short name argument (for first-run renaming)
if [ -n "$1" ]; then
  SHORT_NAME="$1"
else
  SHORT_NAME=$(scutil --get LocalHostName 2>/dev/null)
fi

if [ -z "$SHORT_NAME" ]; then
  echo -e "${RED}Could not determine hostname${NC}"
  exit 1
fi

# Get domain from DNS search domains (skip Tailscale)
DOMAIN=$(scutil --dns | grep "search domain" | grep -v tailc | grep -oE "[a-z0-9.-]+\.[a-z]+$" | head -1)
if [ -z "$DOMAIN" ]; then
  echo -e "${YELLOW}No DNS search domain found, skipping FQDN setup${NC}"
  exit 0
fi

FQDN="${SHORT_NAME}.${DOMAIN}"

echo -e "${BLUE}ComputerName:${NC} $SHORT_NAME"
echo -e "${BLUE}LocalHostName:${NC} $SHORT_NAME"
echo -e "${BLUE}Domain:${NC} $DOMAIN"
echo -e "${BLUE}HostName (FQDN):${NC} $FQDN"
echo ""

# Set all hostname variants
sudo scutil --set ComputerName "$SHORT_NAME"
sudo scutil --set LocalHostName "$SHORT_NAME"
sudo scutil --set HostName "$FQDN"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$SHORT_NAME"

echo -e "${GREEN}All hostnames set (FQDN: $FQDN)${NC}"
