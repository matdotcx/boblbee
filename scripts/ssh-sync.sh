#!/usr/bin/env bash

#########################################################
# Title: ssh-sync
# Description: Set up SSH configuration - copy from iCloud Drive on macOS, local management on Ubuntu
# Source: https://github.com/matdotcx/boblbee
#
# macOS strategy: iCloud is the source of truth for SSH keys (read-only seed).
# ~/.ssh is a real local directory populated by COPYING from iCloud (not symlinked).
# Keys are only copied FROM iCloud, never written back.
# Config files (config, authorized_keys) sync bidirectionally (newest wins).
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

echo "=== SSH Configuration Sync ==="
echo ""

# Paths
ICLOUD_SSH="$ICLOUD_SYNC_PATH/.ssh"
HOME_SSH="$HOME/.ssh"

# Key files: seeded from iCloud, never written back (iCloud → local only)
KEY_FILES=(
    id_rsa id_rsa.pub
    id_ed25519 id_ed25519.pub
    id_github id_github.pub
)

# Config files: synced bidirectionally (newest wins between local and iCloud)
CONFIG_FILES=(
    config
    authorized_keys
)

# All portable files (keys + config) for initial copy / migration
PORTABLE_FILES=("${KEY_FILES[@]}" "${CONFIG_FILES[@]}")

# Local-only files to preserve during migration (not synced from iCloud)
LOCAL_FILES=(
    known_hosts
    known_hosts.old
)

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
        chmod 700 "$agent_dir" 2>/dev/null
        echo "Cleaning stale agent sockets..."
        find "$agent_dir" -type s -delete 2>/dev/null
        rmdir "$agent_dir" 2>/dev/null && echo -e "${GREEN}✓ Removed empty agent directory${NC}" || true
    fi
}

# Function to copy portable files from iCloud to local
copy_from_icloud() {
    local dest="$1"
    local copied=0
    local skipped=0

    local failed=0
    for fname in "${PORTABLE_FILES[@]}"; do
        local src="$ICLOUD_SSH/$fname"
        local dst="$dest/$fname"
        if [ -f "$src" ]; then
            if cp -p "$src" "$dst" 2>/dev/null; then
                copied=$((copied + 1))
            else
                echo -e "${RED}✗ Failed to copy $fname${NC}"
                failed=$((failed + 1))
            fi
        else
            skipped=$((skipped + 1))
        fi
    done
    if [ "$failed" -gt 0 ]; then
        echo -e "${YELLOW}✓ Copied $copied file(s) from iCloud ($failed failed, $skipped not present)${NC}"
    else
        echo -e "${GREEN}✓ Copied $copied file(s) from iCloud ($skipped not present in source)${NC}"
    fi
}

# Function to sync newer files from iCloud into existing dir
sync_from_icloud() {
    local updated=0
    local current=0

    # Keys: iCloud → local only (never write back)
    local failed=0
    for fname in "${KEY_FILES[@]}"; do
        local src="$ICLOUD_SSH/$fname"
        local dst="$HOME_SSH/$fname"
        if [ -f "$src" ]; then
            if [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; then
                if cp -p "$src" "$dst" 2>/dev/null; then
                    updated=$((updated + 1))
                else
                    echo -e "${RED}✗ Failed to copy $fname${NC}"
                    failed=$((failed + 1))
                fi
            else
                current=$((current + 1))
            fi
        fi
    done

    if [ "$failed" -gt 0 ]; then
        echo -e "${YELLOW}✓ Updated $updated key file(s) from iCloud ($failed failed, $current already current)${NC}"
    elif [ "$updated" -gt 0 ]; then
        echo -e "${GREEN}✓ Updated $updated key file(s) from iCloud ($current already current)${NC}"
    else
        echo -e "${GREEN}✓ All $current key file(s) already up to date${NC}"
    fi

    # Config files: bidirectional (newest wins)
    sync_config_bidirectional
}

# Bidirectional sync for config files (newest-mtime-wins between local and iCloud)
sync_config_bidirectional() {
    local to_icloud=0
    local to_local=0
    local in_sync=0

    for fname in "${CONFIG_FILES[@]}"; do
        local icloud_file="$ICLOUD_SSH/$fname"
        local local_file="$HOME_SSH/$fname"

        # Neither exists — skip
        if [ ! -f "$icloud_file" ] && [ ! -f "$local_file" ]; then
            continue
        fi

        # Only one exists — copy to the other
        if [ ! -f "$icloud_file" ] && [ -f "$local_file" ]; then
            cp -p "$local_file" "$icloud_file" 2>/dev/null && to_icloud=$((to_icloud + 1))
            continue
        fi
        if [ ! -f "$local_file" ] && [ -f "$icloud_file" ]; then
            cp -p "$icloud_file" "$local_file" 2>/dev/null && to_local=$((to_local + 1))
            continue
        fi

        # Both exist — compare
        if diff -q "$local_file" "$icloud_file" >/dev/null 2>&1; then
            in_sync=$((in_sync + 1))
            continue
        fi

        local local_mtime icloud_mtime
        local_mtime=$(get_file_mtime "$local_file")
        icloud_mtime=$(get_file_mtime "$icloud_file")

        if [ "$local_mtime" -gt "$icloud_mtime" ]; then
            echo -e "${YELLOW}Local $fname is newer — pushing to iCloud${NC}"
            cp -p "$local_file" "$icloud_file" 2>/dev/null && to_icloud=$((to_icloud + 1))
        else
            echo -e "${YELLOW}iCloud $fname is newer — pulling to local${NC}"
            cp -p "$icloud_file" "$local_file" 2>/dev/null && to_local=$((to_local + 1))
        fi
    done

    if [ "$to_icloud" -gt 0 ] || [ "$to_local" -gt 0 ]; then
        echo -e "${GREEN}✓ Config sync: $to_local pulled from iCloud, $to_icloud pushed to iCloud ($in_sync already current)${NC}"
    else
        echo -e "${GREEN}✓ Config files already in sync${NC}"
    fi
}

# Function to ensure SSH keys are stored in macOS Keychain
store_keys_in_keychain() {
    if ! is_macos; then
        return 0
    fi
    echo ""
    echo -e "${BLUE}Ensuring SSH keys are in macOS Keychain...${NC}"

    local keys_added=0
    for key in id_rsa id_ed25519 id_github; do
        local keyfile="$HOME_SSH/$key"
        [ -f "$keyfile" ] || continue

        # Check if this key is already loaded in the agent
        local key_fingerprint
        key_fingerprint=$(ssh-keygen -lf "$keyfile" 2>/dev/null | awk '{print $2}')
        if [ -n "$key_fingerprint" ] && ssh-add -l 2>/dev/null | grep -q "$key_fingerprint"; then
            echo -e "${GREEN}✓ $key already in agent${NC}"
            continue
        fi

        # Try to add with Keychain (will prompt for passphrase if not stored)
        echo -e "${YELLOW}Adding $key to agent (you may be prompted for the passphrase once)${NC}"
        if ssh-add --apple-use-keychain "$keyfile" 2>/dev/null; then
            echo -e "${GREEN}✓ $key added to Keychain — passphrase stored permanently${NC}"
            keys_added=$((keys_added + 1))
        else
            echo -e "${YELLOW}Could not add $key (passphrase may be needed interactively)${NC}"
        fi
    done

    if [ "$keys_added" -gt 0 ]; then
        echo -e "${GREEN}✓ $keys_added key(s) stored in Keychain — no more passphrase prompts${NC}"
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

        TMPDIR_MIGRATE="$HOME/.ssh.migration.$$"
        mkdir -m 700 "$TMPDIR_MIGRATE"
        echo "  Created staging directory: $TMPDIR_MIGRATE"

        copy_from_icloud "$TMPDIR_MIGRATE"

        for fname in "${LOCAL_FILES[@]}"; do
            src="$ICLOUD_SSH/$fname"
            if [ -f "$src" ]; then
                cp -p "$src" "$TMPDIR_MIGRATE/$fname"
                echo "  Preserved local file: $fname"
            fi
        done

        rm "$HOME_SSH"
        echo -e "${GREEN}✓ Removed symlink (iCloud files untouched)${NC}"

        mv "$TMPDIR_MIGRATE" "$HOME_SSH"
        echo -e "${GREEN}✓ ~/.ssh is now a real local directory${NC}"

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

    # Store keys in Keychain so future SSH sessions don't prompt
    store_keys_in_keychain

elif check_ark_config; then
    #############################################################
    # NON-iCLOUD FALLBACK: pull SSH config + keys from ark-config
    #############################################################
    echo -e "${BLUE}No iCloud Drive — using ark-config as the SSH source${NC}"
    if "$DOTFILES_DIR/script/bootstrap"; then
        fix_permissions
        strip_quarantine
        clean_agent_sockets
        store_keys_in_keychain
    else
        echo -e "${YELLOW}Bootstrap could not provision SSH from ark-config — leaving ~/.ssh untouched${NC}"
        [ -d "$HOME_SSH" ] && fix_permissions
    fi

else
    echo -e "${BLUE}No iCloud Drive and no ark-config detected${NC}"
    echo "SSH configuration will remain local only"
    echo "  (clone ark-config beside boblbee to enable the non-iCloud fallback)"

    if [ -d "$HOME_SSH" ]; then
        fix_permissions
    else
        echo "No SSH configuration found"
    fi
fi

echo ""
echo -e "${GREEN}✓ SSH setup complete!${NC}"
