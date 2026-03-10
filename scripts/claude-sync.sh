#!/usr/bin/env bash

#########################################################
# Title: claude-sync
# Description: Commit Claude memory changes to git (if any)
# Source: https://github.com/matdotcx/boblbee
#########################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/lib.sh"

MEMORY_FILE="$DOTFILES_DIR/claude/memory/user.md"

if [ ! -f "$MEMORY_FILE" ]; then
    echo "No Claude memory file found at $MEMORY_FILE"
    exit 0
fi

cd "$DOTFILES_DIR" || exit 1

# Check if there are changes
if git diff --quiet claude/memory/user.md 2>/dev/null; then
    echo "No changes to Claude memory"
    exit 0
fi

# Show the changes
echo "Changes detected in Claude memory:"
git diff claude/memory/user.md

# Ask if user wants to commit
read -p "Commit these changes? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git add claude/memory/user.md
    read -p "Commit message: " msg
    git commit -m "chore: ${msg:-update claude memory}"
    echo "Changes committed!"
fi
