#!/usr/bin/env bash

#########################################################
# Title: claude
# Description: Install and setup Claude Code
# Source: https://github.com/matdotcx/
#########################################################

echo "Setting up Claude Code..."

# Check if Claude Code is already installed
if ! command -v claude &> /dev/null; then
    echo "Installing Claude Code via npm..."
    sudo npm install -g @anthropic-ai/claude-code
    
    if ! command -v claude &> /dev/null; then
        echo "✗ Failed to install Claude Code"
        exit 1
    fi
    echo "✓ Claude Code installed successfully"
else
    echo "✓ Claude Code is already installed"
fi

echo "Setting up Claude Code memory..."

# Create Claude config directory
mkdir -p ~/.config/claude/memory

# Link user memory file
if [ -f ~/.config/claude/memory/user.md ]; then
  echo "Backing up existing user.md to user.md.backup"
  mv ~/.config/claude/memory/user.md ~/.config/claude/memory/user.md.backup
fi

ln -sf "$PWD/claude/memory/user.md" ~/.config/claude/memory/user.md
echo "✓ Claude Code user memory linked"

# Check if link was successful
if [ -L ~/.config/claude/memory/user.md ]; then
  echo "✓ Claude Code setup complete!"
  echo "  Your global preferences are now synced via dotfiles"
else
  echo "✗ Failed to create symlink"
  exit 1
fi