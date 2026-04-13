#!/usr/bin/env bash

#########################################################
# Title: tailscale-setup
# Description: Install and configure Tailscale for VPN connectivity
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

echo "=== Tailscale Setup ==="
echo ""

# Get Tailscale IP by grepping network interfaces for the CGNAT range.
# Works regardless of whether the CLI is available (covers App Store installs).
get_tailscale_ip_from_interfaces() {
    if is_macos; then
        ifconfig 2>/dev/null | grep -A1 'utun' | grep 'inet ' | grep -oE '100\.[0-9]+\.[0-9]+\.[0-9]+' | head -1
    else
        ip -4 addr show 2>/dev/null | grep -oE '100\.[0-9]+\.[0-9]+\.[0-9]+' | head -1
    fi
}

# Function to check if Tailscale is installed
check_tailscale_installed() {
    if command -v tailscale >/dev/null 2>&1; then
        return 0
    fi

    # macOS may have it in /Applications (App Store version)
    if is_macos && [ -d "/Applications/Tailscale.app" ]; then
        return 0
    fi

    return 1
}

# Function to check if the tailscale CLI is usable
check_tailscale_cli() {
    command -v tailscale >/dev/null 2>&1 && tailscale version >/dev/null 2>&1
}

# Function to check if Tailscale is connected
check_tailscale_connected() {
    # Try the CLI first
    if check_tailscale_cli; then
        local status
        status=$(tailscale status --json 2>/dev/null | grep -o '"BackendState":"[^"]*"' | cut -d'"' -f4)
        if [ "$status" = "Running" ]; then
            return 0
        fi
    fi

    # Fall back to checking for a Tailscale IP on the interfaces
    # (covers App Store installs where the CLI is not available)
    local ts_ip
    ts_ip=$(get_tailscale_ip_from_interfaces)
    if [[ -n "$ts_ip" ]]; then
        return 0
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

# Warn about App Store CLI limitations and explain how boblbee handles it
warn_appstore_cli() {
    echo ""
    echo -e "${YELLOW}Note: The Mac App Store version of Tailscale does not provide a${NC}"
    echo -e "${YELLOW}CLI binary on the PATH. The embedded binary inside the .app bundle${NC}"
    echo -e "${YELLOW}crashes when invoked directly due to sandbox/bundle-identifier issues.${NC}"
    echo ""
    echo -e "${BLUE}Boblbee scripts work around this by detecting the Tailscale IP from${NC}"
    echo -e "${BLUE}network interfaces (looking for addresses in the 100.x.x.x CGNAT range)${NC}"
    echo -e "${BLUE}rather than relying on the tailscale CLI. No action is required.${NC}"
    echo ""
    echo "If you need the CLI for manual use, consider the standalone installer:"
    echo "  https://tailscale.com/download/mac"
    echo ""
}

# Main logic
if check_tailscale_installed; then
    echo -e "${GREEN}Tailscale is installed${NC}"

    # Warn if this is the App Store version without a working CLI
    if is_macos && [ -d "/Applications/Tailscale.app" ] && ! check_tailscale_cli; then
        warn_appstore_cli
    fi

    if check_tailscale_connected; then
        echo -e "${GREEN}Tailscale is connected${NC}"
        echo ""

        # Show status
        echo -e "${BLUE}Tailscale Status:${NC}"
        if check_tailscale_cli; then
            tailscale status 2>/dev/null || echo "  (run 'tailscale status' to see details)"
        else
            local ts_ip
            ts_ip=$(get_tailscale_ip_from_interfaces)
            echo "  Tailscale IP: ${ts_ip:-unknown}"
            echo "  (CLI not available — install standalone version for full status output)"
        fi
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
    if check_tailscale_cli; then
        tailscale ip -4 2>/dev/null || echo "  (authenticate to see IP)"
    else
        local ts_ip
        ts_ip=$(get_tailscale_ip_from_interfaces)
        echo "  ${ts_ip:-  (authenticate to see IP)}"
    fi
else
    echo -e "${YELLOW}Tailscale authentication pending${NC}"
    echo "Complete authentication to finish setup."
fi
