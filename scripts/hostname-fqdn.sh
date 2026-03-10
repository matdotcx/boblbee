#!/usr/bin/env bash

#########################################################
# Title: hostname-fqdn
# Description: Set macOS HostName to FQDN using DNS search domain
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/lib.sh"

echo "=== FQDN Hostname Setup ==="
echo ""

if ! is_macos; then
  echo -e "${YELLOW}Skipping - macOS only${NC}"
  exit 0
fi

# Get current LocalHostName (short hostname)
SHORT_NAME=$(scutil --get LocalHostName 2>/dev/null)
if [ -z "$SHORT_NAME" ]; then
  echo -e "${RED}Could not determine LocalHostName${NC}"
  exit 1
fi

# Get domain from DNS search domains (skip Tailscale)
DOMAIN=$(scutil --dns | grep "search domain" | grep -v tailc | grep -oE "[a-z0-9.-]+\.[a-z]+$" | head -1)
if [ -z "$DOMAIN" ]; then
  echo -e "${YELLOW}No DNS search domain found, skipping FQDN setup${NC}"
  exit 0
fi

FQDN="${SHORT_NAME}.${DOMAIN}"
CURRENT=$(scutil --get HostName 2>/dev/null)

if [ "$CURRENT" = "$FQDN" ]; then
  echo -e "${GREEN}HostName already set to $FQDN${NC}"
  exit 0
fi

echo -e "${BLUE}LocalHostName:${NC} $SHORT_NAME"
echo -e "${BLUE}Domain:${NC} $DOMAIN"
echo -e "${BLUE}Setting HostName to:${NC} $FQDN"
echo ""

if sudo scutil --set HostName "$FQDN"; then
  echo -e "${GREEN}HostName set to $FQDN${NC}"
else
  echo -e "${RED}Failed to set HostName${NC}"
  exit 1
fi
