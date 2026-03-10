#!/usr/bin/env bash

#########################################################
# Title: claude-sync
# Description: Bidirectional sync of Claude memory (copy strategy)
# Source: https://github.com/matdotcx/boblbee
#
# ~/.config/claude/memory/user.md is a real local file (not a symlink).
# Newest-mtime-wins between local and repo, then auto-commits to git.
#########################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

REPO_MEMORY="$DOTFILES_DIR/claude/memory/user.md"
LOCAL_MEMORY="$HOME/.config/claude/memory/user.md"

echo "=== Claude Memory Sync ==="
echo ""

# Ensure local directory exists
mkdir -p "$(dirname "$LOCAL_MEMORY")"

# Migrate symlink to copy if still present
if [ -L "$LOCAL_MEMORY" ]; then
    echo -e "${YELLOW}Migrating: replacing symlink with local copy${NC}"
    link_target="$(readlink "$LOCAL_MEMORY")"
    rm -f "$LOCAL_MEMORY"
    src="$link_target"
    [ -f "$src" ] || src="$REPO_MEMORY"
    if [ -f "$src" ]; then
        cp "$src" "$LOCAL_MEMORY"
        echo -e "${GREEN}✓ Migrated to local copy${NC}"
    fi
fi

# Check we have at least one source
if [ ! -f "$REPO_MEMORY" ] && [ ! -f "$LOCAL_MEMORY" ]; then
    echo "No Claude memory file found in repo or locally"
    exit 0
fi

# If only one exists, copy to the other
if [ ! -f "$LOCAL_MEMORY" ] && [ -f "$REPO_MEMORY" ]; then
    cp "$REPO_MEMORY" "$LOCAL_MEMORY"
    echo -e "${GREEN}Installed Claude memory from dotfiles${NC}"
    exit 0
fi
if [ ! -f "$REPO_MEMORY" ] && [ -f "$LOCAL_MEMORY" ]; then
    cp "$LOCAL_MEMORY" "$REPO_MEMORY"
    echo -e "${GREEN}Copied local Claude memory to dotfiles${NC}"
    commit_dotfiles_changes "Update Claude memory from local" "claude/memory/user.md"
    exit 0
fi

# Both exist — compare
if diff -q "$LOCAL_MEMORY" "$REPO_MEMORY" >/dev/null 2>&1; then
    echo -e "${GREEN}Claude memory already in sync${NC}"
    exit 0
fi

# Newest wins
local_mtime=$(get_file_mtime "$LOCAL_MEMORY")
repo_mtime=$(get_file_mtime "$REPO_MEMORY")

if [ "$local_mtime" -gt "$repo_mtime" ]; then
    echo -e "${YELLOW}Local memory is newer — updating dotfiles${NC}"
    cp "$LOCAL_MEMORY" "$REPO_MEMORY"
    echo -e "${GREEN}Dotfiles updated${NC}"
    commit_dotfiles_changes "Update Claude memory from local" "claude/memory/user.md"
elif [ "$repo_mtime" -gt "$local_mtime" ]; then
    echo -e "${YELLOW}Dotfiles memory is newer — updating local${NC}"
    cp "$REPO_MEMORY" "$LOCAL_MEMORY"
    echo -e "${GREEN}Local Claude memory updated${NC}"
else
    echo -e "${GREEN}Claude memory already in sync${NC}"
fi

echo ""
echo -e "${GREEN}Claude memory sync complete${NC}"
