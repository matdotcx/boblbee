#!/usr/bin/env bash

#########################################################
# Title: upgrade
# Description: Safely upgrade existing boblbee installations
# Source: https://github.com/matdotcx/
#########################################################

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Boblbee Upgrade Script ==="
echo ""
echo "This script will safely upgrade your existing boblbee installation"
echo "to support the new intelligent sync features."
echo ""

# Get the directory where this script is located
if [ -n "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  # Fallback for when script is run via alias
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# Check if we're in the right place
if [ ! -f "$DOTFILES_DIR/README.md" ] || [ ! -d "$DOTFILES_DIR/scripts" ]; then
  echo -e "${RED}Error: This doesn't appear to be a boblbee directory${NC}"
  echo "Please run this from within your boblbee/scripts directory"
  exit 1
fi

echo -e "${BLUE}Checking current setup...${NC}"
echo ""

# Function to backup files
backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    local backup="${file}.pre-upgrade.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Backing up $file to $backup${NC}"
    cp "$file" "$backup"
  fi
}

# 1. Update git repository
echo "1. Updating boblbee repository..."
cd "$DOTFILES_DIR"
git stash push -m "Pre-upgrade stash $(date)"
git pull origin gold
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
  link_target=$(readlink "$HOME/.zshrc")
  if [[ "$link_target" == *"iCloud"* ]]; then
    echo -e "${GREEN}✓ .zshrc already linked to iCloud${NC}"
  else
    echo -e "${YELLOW}.zshrc is symlinked elsewhere: $link_target${NC}"
  fi
elif [ -f "$HOME/.zshrc" ]; then
  echo "Found regular .zshrc file"
  backup_file "$HOME/.zshrc"
fi
echo ""

# 4. Check for missing scripts
echo "4. Checking for new scripts..."
missing_scripts=()
for script in "claude.sh" "claude-sync.sh" "zshrc-sync.sh" "new-machine.sh" "upgrade.sh"; do
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
echo "- Set up Claude Code memory sync"
echo "- Configure smart .zshrc sync"
echo "- Add new aliases (dots, claude-sync)"
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

echo "Setting up SSH sync (if iCloud available)..."
"$SCRIPT_DIR/ssh-sync.sh"
echo ""

# Clean up old aliases
echo "Cleaning up old aliases..."
if grep -q "^alias dots=" "$HOME/.zshrc" 2>/dev/null || grep -q "^alias claude-sync=" "$HOME/.zshrc" 2>/dev/null; then
  echo -e "${YELLOW}Note: Old aliases (dots, claude-sync) detected${NC}"
  echo "These have been replaced with the bb-* command structure"
  echo "Please run 'bb-sync-zshrc' after upgrade to get the new commands"
fi

# Check for new boblbee section
if ! grep -q "Boblbee Dotfiles Management" "$HOME/.zshrc" 2>/dev/null; then
  echo -e "${YELLOW}New boblbee commands will be added on next zshrc sync${NC}"
fi

echo ""
echo -e "${GREEN}=== Upgrade Complete! ===${NC}"
echo ""
echo "New boblbee command structure:"
echo "- ${BLUE}bb-help${NC}       - Show all available commands"
echo "- ${BLUE}bb-sync${NC}       - Sync all configurations"
echo "- ${BLUE}bb-status${NC}     - Check sync status"
echo "- ${BLUE}bb-sync-zshrc${NC} - Sync shell configuration"
echo "- ${BLUE}bb-sync-claude${NC}- Sync Claude preferences"
echo ""
echo "Next steps:"
echo "1. Sync your zshrc: ${BLUE}$SCRIPT_DIR/zshrc-sync.sh${NC}"
echo "2. Source your shell: ${BLUE}source ~/.zshrc${NC}"
echo "3. Try the new help: ${BLUE}bb-help${NC}"
echo "4. Check status: ${BLUE}bb-status${NC}"
echo ""
echo "If you had any git stashes created, retrieve them with:"
echo "  ${BLUE}git stash list${NC} and ${BLUE}git stash pop${NC}"