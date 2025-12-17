#!/usr/bin/env bash

#########################################################
# Title: tailscale-setup
# Description: Install and configure Tailscale for VPN connectivity
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source OS detection
source "$(dirname "$0")/detect-os.sh"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Tailscale Setup ==="
echo ""

# Function to check if Tailscale is installed
check_tailscale_installed() {
    if command -v tailscale >/dev/null 2>&1; then
        return 0
    fi

    # macOS may have it in /Applications
    if is_macos && [ -d "/Applications/Tailscale.app" ]; then
        return 0
    fi

    return 1
}

# Function to check if Tailscale is connected
check_tailscale_connected() {
    if tailscale status >/dev/null 2>&1; then
        local status
        status=$(tailscale status --json 2>/dev/null | grep -o '"BackendState":"[^"]*"' | cut -d'"' -f4)
        if [ "$status" = "Running" ]; then
            return 0
        fi
    fi
    return 1
}

# Function to install Tailscale on macOS
install_macos() {
    echo -e "${BLUE}Installing Tailscale for macOS...${NC}"
    echo ""

    # Check if already installed via App Store or direct download
    if [ -d "/Applications/Tailscale.app" ]; then
        echo -e "${GREEN}Tailscale.app already installed${NC}"
        return 0
    fi

    echo "Tailscale can be installed via:"
    echo "  1. Mac App Store (recommended)"
    echo "  2. Direct download from https://tailscale.com/download/mac"
    echo ""

    # Try to open App Store page
    echo -e "${BLUE}Opening Mac App Store...${NC}"
    if open "macappstore://apps.apple.com/app/tailscale/id1475387142" 2>/dev/null; then
        echo ""
        echo "Please install Tailscale from the App Store, then run this script again."
        echo ""
        return 1
    else
        echo "Could not open App Store. Please install Tailscale manually:"
        echo "  https://apps.apple.com/app/tailscale/id1475387142"
        echo "  or"
        echo "  https://tailscale.com/download/mac"
        return 1
    fi
}

# Function to install Tailscale on Ubuntu
install_ubuntu() {
    echo -e "${BLUE}Installing Tailscale for Ubuntu...${NC}"
    echo ""

    # Use official Tailscale installer
    if curl -fsSL https://tailscale.com/install.sh | sh; then
        echo -e "${GREEN}Tailscale installed successfully${NC}"
        return 0
    else
        echo -e "${RED}Failed to install Tailscale${NC}"
        return 1
    fi
}

# Function to authenticate and connect
connect_tailscale() {
    echo ""
    echo -e "${BLUE}Connecting to Tailscale...${NC}"
    echo ""

    if is_macos; then
        # On macOS, Tailscale.app handles authentication via GUI
        echo "Please complete authentication in the Tailscale menu bar app."
        echo ""

        # Open Tailscale app if not running
        if ! pgrep -x "Tailscale" >/dev/null 2>&1; then
            open -a Tailscale 2>/dev/null || true
        fi

        echo "After authenticating, Tailscale will automatically connect."
        echo ""
    elif is_ubuntu; then
        # On Ubuntu, use tailscale up with SSH enabled
        echo "Running: tailscale up --ssh"
        echo ""
        echo "This will open a browser for authentication."
        echo "If running headless, copy the provided URL to authenticate."
        echo ""

        if sudo tailscale up --ssh; then
            echo -e "${GREEN}Tailscale connected${NC}"
        else
            echo -e "${YELLOW}Please complete authentication manually${NC}"
            echo "Run: sudo tailscale up --ssh"
        fi
    fi
}

# Main logic
if check_tailscale_installed; then
    echo -e "${GREEN}Tailscale is installed${NC}"

    if check_tailscale_connected; then
        echo -e "${GREEN}Tailscale is connected${NC}"
        echo ""

        # Show status
        echo -e "${BLUE}Tailscale Status:${NC}"
        tailscale status 2>/dev/null || echo "  (run 'tailscale status' to see details)"
        echo ""

        echo -e "${GREEN}Tailscale setup complete!${NC}"
        exit 0
    else
        echo -e "${YELLOW}Tailscale is not connected${NC}"
        connect_tailscale
    fi
else
    echo -e "${YELLOW}Tailscale is not installed${NC}"
    echo ""

    # Install based on platform
    if is_macos; then
        install_macos
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}Please install Tailscale and run this script again${NC}"
            exit 0  # Don't fail boblbee setup
        fi
    elif is_ubuntu; then
        install_ubuntu
        if [ $? -ne 0 ]; then
            exit 1
        fi
        connect_tailscale
    else
        echo -e "${RED}Unsupported platform for Tailscale installation${NC}"
        exit 1
    fi
fi

# Verify connection
echo ""
if check_tailscale_connected; then
    echo -e "${GREEN}Tailscale setup complete!${NC}"
    echo ""
    echo "Your Tailscale IP:"
    tailscale ip -4 2>/dev/null || echo "  (authenticate to see IP)"
else
    echo -e "${YELLOW}Tailscale authentication pending${NC}"
    echo "Complete authentication to finish setup."
fi
