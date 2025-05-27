#!/usr/bin/env bash

#########################################################
# Title: claude
# Description: Setup Claude Code memory and preferences
# Source: https://github.com/matdotcx/
#########################################################

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