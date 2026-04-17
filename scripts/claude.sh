#!/usr/bin/env bash

#########################################################
# Title: claude
# Description: Install and setup Claude Code
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Resolve the repo root regardless of where we're invoked from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
BOBLBEE_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

echo "Setting up Claude Code..."

# Check if Claude Code is already installed
if ! command -v claude &> /dev/null; then
    echo "Installing Claude Code via native installer..."
    curl -fsSL https://cli.anthropic.com/install.sh | sh

    if ! command -v claude &> /dev/null; then
        echo "✗ Failed to install Claude Code"
        echo "  See https://docs.anthropic.com/en/docs/claude-code/getting-started for options"
        exit 1
    fi
    echo "✓ Claude Code installed successfully"
else
    echo "✓ Claude Code is already installed"
fi

echo "Setting up Claude Code memory..."

# Paths
REPO_MEMORY="$BOBLBEE_DIR/claude/memory/user.md"
LOCAL_MEMORY="$HOME/.config/claude/memory/user.md"

# Create Claude config directory
mkdir -p ~/.config/claude/memory

# Migrate from symlink to copy if needed
if [ -L "$LOCAL_MEMORY" ]; then
    echo -e "${YELLOW}Migrating: replacing symlink with local copy${NC}"
    link_target="$(readlink "$LOCAL_MEMORY")"
    rm -f "$LOCAL_MEMORY"
    if [ -f "$link_target" ]; then
        cp "$link_target" "$LOCAL_MEMORY"
    elif [ -f "$REPO_MEMORY" ]; then
        cp "$REPO_MEMORY" "$LOCAL_MEMORY"
    fi
    echo -e "${GREEN}✓ Claude memory is now a local copy${NC}"
elif [ -f "$LOCAL_MEMORY" ]; then
    echo "✓ Claude memory file exists (local copy)"
elif [ -f "$REPO_MEMORY" ]; then
    cp "$REPO_MEMORY" "$LOCAL_MEMORY"
    echo "✓ Claude memory installed from dotfiles"
else
    echo -e "${YELLOW}No Claude memory source found — skipping${NC}"
fi

echo "✓ Claude Code setup complete!"
echo "  Run bb-sync-claude to sync memory between local and dotfiles"