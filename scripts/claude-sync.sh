#!/usr/bin/env bash

#########################################################
# Title: claude-sync
# Description: Sync Claude memory changes back to dotfiles
# Source: https://github.com/matdotcx/
#########################################################

cd "$(dirname "${BASH_SOURCE}")"/../

# Check if the source file exists
if [ ! -f ~/.config/claude/memory/user.md ]; then
  echo "No Claude memory file found at ~/.config/claude/memory/user.md"
  exit 1
fi

# Copy the current memory to dotfiles
cp ~/.config/claude/memory/user.md claude/memory/user.md

# Check if there are changes
if git diff --quiet claude/memory/user.md; then
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