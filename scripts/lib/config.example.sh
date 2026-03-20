#!/usr/bin/env bash
#
# config.example.sh — copy to config.local.sh and fill in your values
#
# cp scripts/lib/config.example.sh scripts/lib/config.local.sh
#

###############################################################################
# iCloud layout (macOS)
###############################################################################

ICLOUD_BASE="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
ICLOUD_SYNC_DIR="CHANGEME/Sync/System"
ICLOUD_SYNC_PATH="$ICLOUD_BASE/$ICLOUD_SYNC_DIR"

###############################################################################
# Observability / monitoring
###############################################################################

HELIUM_FQDN="helium.example.com"
HELIUM_IP="10.0.0.1"
HELIUM_REGISTER_SCRIPT="~/observability/scripts/register-host.sh"
