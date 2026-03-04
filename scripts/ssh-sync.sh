#!/usr/bin/env bash

#########################################################
# Title: ssh-sync
# Description: Set up SSH configuration - copy from iCloud Drive on macOS, local management on Ubuntu
# Source: https://github.com/matdotcx/boblbee
#
# macOS strategy: iCloud is the source of truth for portable SSH files.
# ~/.ssh is a real local directory populated by COPYING from iCloud (not symlinked).
# iCloud files are NEVER modified or deleted — only read.
#########################################################

# Source OS detection
source "$(dirname "$0")/detect-os.sh"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== SSH Configuration Sync ==="
echo ""

# Paths
ICLOUD_SSH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ark/Sync/System/.ssh"
HOME_SSH="$HOME/.ssh"

# Portable files to sync from iCloud (keys, config, authorized_keys)
PORTABLE_FILES=(
    id_rsa id_rsa.pub
    id_ed25519 id_ed25519.pub
    id_github id_github.pub
    config
    authorized_keys
)

# Local-only files to preserve during migration (not synced from iCloud)
LOCAL_FILES=(
    known_hosts
    known_hosts.old
)

# Function to check if iCloud Drive is available AND functional (macOS only)
check_icloud() {
    if ! is_macos; then
        return 1
    fi
    local icloud_base="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    if [ ! -d "$icloud_base" ]; then
        return 1
    fi
    # Test if we can actually read from iCloud
    if [ ! -d "$ICLOUD_SSH" ]; then
        return 1
    fi
    return 0
}

# Function to fix permissions on ~/.ssh and its contents
fix_permissions() {
    echo "Fixing permissions..."
    chmod 700 "$HOME_SSH"

    for f in "$HOME_SSH"/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            *.pub|known_hosts|known_hosts.old|config)
                chmod 644 "$f"
                ;;
            *)
                chmod 600 "$f"
                ;;
        esac
    done
    echo -e "${GREEN}✓ Permissions set correctly${NC}"
}

# Function to strip quarantine xattrs
strip_quarantine() {
    echo "Stripping quarantine extended attributes..."
    local count=0
    for f in "$HOME_SSH"/*; do
        [ -f "$f" ] || continue
        if xattr -l "$f" 2>/dev/null | grep -q "com.apple.quarantine"; then
            xattr -d com.apple.quarantine "$f" 2>/dev/null
            count=$((count + 1))
        fi
    done
    if [ "$count" -gt 0 ]; then
        echo -e "${GREEN}✓ Stripped quarantine from $count file(s)${NC}"
    else
        echo -e "${GREEN}✓ No quarantine attributes found${NC}"
    fi
}

# Function to clean stale agent sockets
clean_agent_sockets() {
    local agent_dir="$HOME_SSH/agent"
    if [ -d "$agent_dir" ]; then
        echo "Cleaning stale agent sockets..."
        find "$agent_dir" -type s -delete 2>/dev/null
        # Remove agent dir if empty
        rmdir "$agent_dir" 2>/dev/null && echo -e "${GREEN}✓ Removed empty agent directory${NC}" || true
    fi
}

# Function to copy portable files from iCloud to local
copy_from_icloud() {
    local dest="$1"
    local copied=0
    local skipped=0

    for fname in "${PORTABLE_FILES[@]}"; do
        local src="$ICLOUD_SSH/$fname"
        local dst="$dest/$fname"
        if [ -f "$src" ]; then
            cp -p "$src" "$dst"
            copied=$((copied + 1))
        else
            skipped=$((skipped + 1))
        fi
    done
    echo -e "${GREEN}✓ Copied $copied file(s) from iCloud ($skipped not present in source)${NC}"
}

# Function to sync newer files from iCloud into existing dir
sync_from_icloud() {
    local updated=0
    local current=0

    for fname in "${PORTABLE_FILES[@]}"; do
        local src="$ICLOUD_SSH/$fname"
        local dst="$HOME_SSH/$fname"
        if [ -f "$src" ]; then
            if [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; then
                cp -p "$src" "$dst"
                updated=$((updated + 1))
            else
                current=$((current + 1))
            fi
        fi
    done

    if [ "$updated" -gt 0 ]; then
        echo -e "${GREEN}✓ Updated $updated file(s) from iCloud ($current already current)${NC}"
    else
        echo -e "${GREEN}✓ All $current file(s) already up to date${NC}"
    fi
}

# Main logic - platform-specific behavior
if is_ubuntu; then
    echo -e "${BLUE}Ubuntu detected - local SSH management${NC}"

    if [ -d "$HOME_SSH" ]; then
        echo -e "${GREEN}✓ SSH directory exists${NC}"
        fix_permissions

        # Display SSH public keys if they exist
        echo ""
        echo -e "${BLUE}Available SSH public keys:${NC}"
        for pub_key in "$HOME_SSH"/*.pub; do
            if [ -f "$pub_key" ]; then
                echo "$(basename "$pub_key"):"
                cat "$pub_key"
                echo ""
            fi
        done
    else
        echo -e "${YELLOW}No SSH directory found${NC}"
        echo "To set up SSH keys:"
        echo "  1. Run ssh-keygen -t ed25519 -C 'your_email@example.com'"
        echo "  2. Add the public key to your Git hosting service"
        echo "  3. Run this script again to verify permissions"
    fi

    echo ""
    echo -e "${BLUE}Setup: Local SSH management${NC}"
    echo "SSH keys and config managed locally (not synced)"

elif check_icloud; then
    echo -e "${BLUE}iCloud Drive detected${NC}"

    if [ -L "$HOME_SSH" ]; then
        #############################################################
        # MIGRATION: ~/.ssh is a symlink — break it, copy to real dir
        #############################################################
        echo -e "${YELLOW}Migration: ~/.ssh is a symlink → converting to local directory${NC}"
        local_target="$(readlink "$HOME_SSH")"
        echo "  Current symlink target: $local_target"

        # Create temp staging directory
        TMPDIR_MIGRATE="$HOME/.ssh.migration.$$"
        mkdir -m 700 "$TMPDIR_MIGRATE"
        echo "  Created staging directory: $TMPDIR_MIGRATE"

        # Copy portable files from iCloud
        copy_from_icloud "$TMPDIR_MIGRATE"

        # Preserve local-only files from the symlinked location
        for fname in "${LOCAL_FILES[@]}"; do
            src="$ICLOUD_SSH/$fname"
            if [ -f "$src" ]; then
                cp -p "$src" "$TMPDIR_MIGRATE/$fname"
                echo "  Preserved local file: $fname"
            fi
        done

        # Remove the symlink (only the pointer, not the iCloud target)
        rm "$HOME_SSH"
        echo -e "${GREEN}✓ Removed symlink (iCloud files untouched)${NC}"

        # Move staging dir into place
        mv "$TMPDIR_MIGRATE" "$HOME_SSH"
        echo -e "${GREEN}✓ ~/.ssh is now a real local directory${NC}"

        # Fix up
        fix_permissions
        strip_quarantine
        clean_agent_sockets

    elif [ -d "$HOME_SSH" ]; then
        #############################################################
        # SYNC: ~/.ssh is already a real directory — update from iCloud
        #############################################################
        echo -e "${BLUE}~/.ssh is a local directory — syncing newer files from iCloud${NC}"
        sync_from_icloud
        fix_permissions
        strip_quarantine
        clean_agent_sockets

    else
        #############################################################
        # FRESH: ~/.ssh doesn't exist — create and populate
        #############################################################
        echo -e "${BLUE}No ~/.ssh found — creating from iCloud${NC}"
        mkdir -m 700 "$HOME_SSH"
        copy_from_icloud "$HOME_SSH"
        fix_permissions
        strip_quarantine
    fi

else
    echo -e "${BLUE}No iCloud Drive detected${NC}"
    echo "SSH configuration will remain local only"

    if [ -d "$HOME_SSH" ]; then
        fix_permissions
    else
        echo "No SSH configuration found"
    fi
fi

echo ""
echo -e "${GREEN}✓ SSH setup complete!${NC}"
