#!/usr/bin/env bash

#########################################################
# Title: upgrade
# Description: Safely upgrade existing boblbee installations
# Source: https://github.com/matdotcx/
#########################################################

# Get the directory where this script is located
if [ -n "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

# Check if we're in the right place
if [ ! -f "$DOTFILES_DIR/README.md" ] || [ ! -d "$DOTFILES_DIR/scripts" ]; then
    echo -e "${RED}Error: This doesn't appear to be a boblbee directory${NC}"
    echo "Please run this from within your boblbee/scripts directory"
    exit 1
fi

echo "=== Boblbee Upgrade Script ==="
echo ""
echo "This script will safely upgrade your existing boblbee installation"
echo "to support the new intelligent sync features."
echo ""

echo -e "${BLUE}Checking current setup...${NC}"
echo ""

# 1. Update git repository (auto-detect branch)
BRANCH=$(get_default_branch)
echo "1. Updating boblbee repository (branch: $BRANCH)..."
cd "$DOTFILES_DIR"
git stash push -m "Pre-upgrade stash $(date)"
git pull origin "$BRANCH"
echo -e "${GREEN}✓ Repository updated${NC}"
echo ""

# 2. Check for existing Claude setup
echo "2. Checking Claude Code integration..."
if [ -L "$HOME/.config/claude/memory/user.md" ]; then
    echo -e "${GREEN}✓ Claude memory already configured${NC}"
elif [ -f "$HOME/.config/claude/memory/user.md" ]; then
    echo -e "${YELLOW}Found existing Claude memory - will preserve${NC}"
    backup_file "$HOME/.config/claude/memory/user.md"
else
    echo "No existing Claude setup found - will configure"
fi
echo ""

# 3. Check .zshrc situation
echo "3. Analyzing .zshrc configuration..."
if [ -L "$HOME/.zshrc" ]; then
    echo -e "${YELLOW}.zshrc is a symlink (needs migration to local copy)${NC}"
    echo "  bb-sync-zshrc will handle this automatically"
elif [ -f "$HOME/.zshrc" ]; then
    echo -e "${GREEN}✓ .zshrc is a local file (correct)${NC}"
fi
echo ""

# 4. Check for missing scripts
echo "4. Checking for new scripts..."
missing_scripts=()
for script in "claude.sh" "claude-sync.sh" "zshrc-sync.sh" "tmux-sync.sh" "ghostty-sync.sh" "motd-sync.sh" "upgrade.sh"; do
    if [ ! -f "$SCRIPT_DIR/$script" ]; then
        missing_scripts+=("$script")
    fi
done

if [ ${#missing_scripts[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing scripts: ${missing_scripts[*]}${NC}"
    echo "These will be added from the repository"
else
    echo -e "${GREEN}✓ All scripts present${NC}"
fi
echo ""

# 5. Make scripts executable
echo "5. Ensuring scripts are executable..."
chmod +x "$SCRIPT_DIR"/*.sh
echo -e "${GREEN}✓ Script permissions updated${NC}"
echo ""

# Ask for confirmation
echo -e "${BLUE}Ready to upgrade. This will:${NC}"
echo "- Ensure Claude Code memory sync is configured"
echo "- Verify smart .zshrc sync setup"
echo "- Sync tmux configuration and themes"
if is_macos; then
    echo "- Sync Ghostty terminal configuration"
fi
echo "- Sync message of the day"
echo "- Verify SSH sync setup"
echo "- Update to new bb-* command structure"
echo "- Preserve all your existing configurations"
echo ""
echo -e "${YELLOW}Continue? (y/n)${NC}"
read -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Upgrade cancelled"
    exit 0
fi

echo ""
echo -e "${BLUE}Running upgrade...${NC}"
echo ""

# Run the setup scripts
echo "Setting up Claude Code integration..."
"$SCRIPT_DIR/claude.sh"
echo ""

echo "Setting up smart .zshrc sync..."
"$SCRIPT_DIR/zshrc-sync.sh"
echo ""

echo "Setting up tmux configuration..."
"$SCRIPT_DIR/tmux-sync.sh"
echo ""

if is_macos; then
    echo "Setting up Ghostty terminal configuration..."
    "$SCRIPT_DIR/ghostty-sync.sh"
    echo ""
fi

echo "Setting up message of the day..."
"$SCRIPT_DIR/motd-sync.sh"
echo ""

echo "Setting up SSH sync (if iCloud available)..."
"$SCRIPT_DIR/ssh-sync.sh"
echo ""

echo ""
echo "=== Upgrade Complete! ==="
echo ""
echo "Your boblbee installation is now up to date."
echo ""
echo "Available commands:"
echo "  bb-help        - Show all available commands"
echo "  bb-sync        - Sync all configurations"
echo "  bb-status      - Check sync status"
echo "  bb-sync-zshrc  - Sync shell configuration"
echo "  bb-sync-tmux   - Sync tmux configuration"
echo "  bb-sync-claude - Sync Claude preferences"
echo "  bb-sync-ssh    - Sync SSH configuration"
echo ""
echo "Next steps:"
echo "1. Reload your shell: source ~/.zshrc"
echo "2. Try the help command: bb-help"
echo "3. Check your status: bb-status"
echo ""
echo "If you had any git stashes created, retrieve them with:"
echo "  git stash list"
echo "  git stash pop"
