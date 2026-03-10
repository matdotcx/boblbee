#!/usr/bin/env bash

#########################################################
# Title: observability-collector
# Description: Install observability collector and register with helium
# Source: https://github.com/matdotcx/boblbee
#########################################################

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

echo "=== Observability Collector Setup ==="
echo ""

INSTALLER_SCRIPT="$SCRIPT_DIR/install-collector.sh"

# Function to get local IP address
# Prefers Tailscale IP if available (for remote machines)
get_local_ip() {
    # Try Tailscale IP first (works for remote machines)
    local tailscale_ip
    tailscale_ip=$(tailscale ip -4 2>/dev/null)
    if [[ -n "$tailscale_ip" ]]; then
        echo "$tailscale_ip"
        return 0
    fi

    # Fall back to primary interface IP
    if is_macos; then
        ipconfig getifaddr en0 2>/dev/null
    elif is_ubuntu; then
        hostname -I 2>/dev/null | awk '{print $1}'
    fi
}

# Function to detect which port the exporter is running on
detect_exporter_port() {
    if curl -s --connect-timeout 2 "http://localhost:9100/metrics" > /dev/null 2>&1; then
        echo "9100"
        return 0
    fi
    return 1
}

# Function to check if exporter is installed AND serving metrics
check_existing_exporter() {
    curl -s --connect-timeout 2 "http://localhost:9100/metrics" > /dev/null 2>&1
}

# Function to determine reachable helium address
get_helium_address() {
    # Try FQDN first (works via Tailscale Split DNS)
    if ping -c 1 -W 2 "$HELIUM_FQDN" > /dev/null 2>&1; then
        echo "$HELIUM_FQDN"
        return 0
    fi

    # Fallback to IP if on local network
    if ping -c 1 -W 2 "$HELIUM_IP" > /dev/null 2>&1; then
        echo "$HELIUM_IP"
        return 0
    fi

    # Neither reachable
    return 1
}

# Function to register with helium
register_with_helium() {
    local helium_addr="$1"
    local exporter_port="${2:-9100}"
    local hostname
    local local_ip

    hostname=$(hostname -s 2>/dev/null || hostname)
    local_ip=$(get_local_ip)

    if [ -z "$local_ip" ]; then
        echo -e "${YELLOW}Could not determine local IP address${NC}"
        return 1
    fi

    echo -e "${BLUE}Registering with helium (${helium_addr})...${NC}"
    echo "  Hostname: $hostname"
    echo "  IP: $local_ip"
    echo "  Exporter Port: $exporter_port"

    # Use SSH agent forwarding to register
    if ssh -A -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$helium_addr" \
        "$HELIUM_REGISTER_SCRIPT '$hostname' '$local_ip' '$exporter_port'" 2>/dev/null; then
        echo -e "${GREEN}Registered with helium${NC}"
        return 0
    else
        echo -e "${YELLOW}Could not register with helium (script may not exist yet)${NC}"
        return 1
    fi
}

# Check if collector is already installed
if check_existing_exporter; then
    exporter_port=$(detect_exporter_port)
    echo -e "${GREEN}Exporter already installed and running on port ${exporter_port}${NC}"
    echo ""

    # Still try to register in case this is a re-run
    if helium=$(get_helium_address); then
        register_with_helium "$helium" "$exporter_port" || true
    fi

    echo -e "${GREEN}Observability collector setup complete!${NC}"
    exit 0
fi

# Install the collector
echo -e "${BLUE}Installing observability collector...${NC}"
echo ""

# Run the bundled installer
if [[ -f "$INSTALLER_SCRIPT" ]]; then
    if bash "$INSTALLER_SCRIPT"; then
        echo -e "${GREEN}Collector installed successfully${NC}"
    else
        echo -e "${RED}Collector installation failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}Installer script not found:${NC}"
    echo "  $INSTALLER_SCRIPT"
    echo ""
    echo -e "${YELLOW}Skipping collector installation.${NC}"
    # Don't fail - allow boblbee to continue
fi

# Try to register with helium (install-collector.sh uses port 9100)
echo ""
if helium=$(get_helium_address); then
    register_with_helium "$helium" "9100" || true
else
    echo -e "${YELLOW}Helium not reachable${NC}"
    echo "This machine will not be monitored until registered."
    echo ""
    echo "To register later, ensure connectivity to helium and run:"
    echo "  ssh -A $HELIUM_FQDN '$HELIUM_REGISTER_SCRIPT \$(hostname) \$(hostname -I | awk \"{print \\\$1}\")'"
fi

echo ""
echo -e "${GREEN}Observability collector setup complete!${NC}"
