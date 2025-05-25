#!/usr/bin/env bash

#########################################################
# Title: new-machine
# Description: Quick setup for new machines with iCloud
# Source: https://github.com/matdotcx/
#########################################################

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== New Machine Setup ==="
echo ""

# Check if iCloud Drive is available
ICLOUD_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
if [ ! -d "$ICLOUD_PATH" ]; then
  echo -e "${RED}iCloud Drive not found!${NC}"
  echo "Please sign in to iCloud first, or use the standard setup:"
  echo "  ./scripts/index.sh"
  exit 1
fi

echo -e "${GREEN}✓ iCloud Drive detected${NC}"
echo ""

# Function to create symlink with backup
create_symlink() {
  local source="$1"
  local target="$2"
  local name="$3"
  
  echo "Setting up $name..."
  
  # Check if source exists
  if [ ! -e "$source" ]; then
    echo -e "${YELLOW}Warning: $source not found in iCloud${NC}"
    return 1
  fi
  
  # Backup existing file/directory if it exists and isn't a symlink
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    local backup="${target}.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Backing up existing $name to $backup${NC}"
    mv "$target" "$backup"
  fi
  
  # Remove existing symlink if it points elsewhere
  if [ -L "$target" ]; then
    existing_link=$(readlink "$target")
    if [ "$existing_link" != "$source" ]; then
      echo -e "${YELLOW}Updating existing symlink${NC}"
      rm "$target"
    else
      echo -e "${GREEN}✓ $name already correctly linked${NC}"
      return 0
    fi
  fi
  
  # Create the symlink
  ln -s "$source" "$target"
  echo -e "${GREEN}✓ $name linked to iCloud${NC}"
}

# Note about automatic setup
echo -e "${BLUE}Note:${NC}"
echo "SSH and .zshrc will be automatically configured"
echo "when you run the main setup script."
echo ""

# Check for boblbee installation
if [ -d "$HOME/Developer/workspace/gl52/boblbee" ]; then
  echo -e "${BLUE}Boblbee detected. Would you like to run the full setup? (y/n)${NC}"
  read -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd "$HOME/Developer/workspace/gl52/boblbee"
    ./scripts/index.sh
  else
    echo ""
    echo "To complete setup manually, run:"
    echo "  cd ~/Developer/workspace/gl52/boblbee"
    echo "  ./scripts/index.sh"
  fi
else
  echo -e "${YELLOW}Boblbee not found at expected location${NC}"
  echo ""
  echo "To complete setup:"
  echo "1. Clone boblbee:"
  echo "   git clone https://github.com/yourusername/boblbee.git ~/Developer/workspace/gl52/boblbee"
  echo ""
  echo "2. Run setup:"
  echo "   cd ~/Developer/workspace/gl52/boblbee"
  echo "   ./scripts/index.sh"
fi

echo ""
echo -e "${GREEN}✓ Initial setup complete!${NC}"
echo ""
echo "Next steps:"
echo "- Run the boblbee setup scripts as shown above"
echo "- Source your shell: source ~/.zshrc"
echo "- Test aliases: dots, claude-sync"