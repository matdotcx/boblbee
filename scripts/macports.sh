#########################################################
# Title; macports
# Description; Building macports from source
# Source; https://github.com/matdotcx/
#########################################################

#!/bin/zsh
# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until we have finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Save original script directory for later use
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOBLBEE_DIR="$(dirname "$SCRIPT_DIR")"

# Define timestamp variable
timestamp=$(date +%d-%m-%Y_%H.%M.%S)

# MacPorts version to install (use stable release, not dev/master)
echo "Fetching latest MacPorts stable release..."
MACPORTS_VERSION=$(git ls-remote --tags https://github.com/macports/macports-base.git | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -1)

# Check if MacPorts was recently installed (less than 24 hours ago)
if [ -f "/opt/local/bin/port" ]; then
    install_time=$(stat -f %m /opt/local/bin/port 2>/dev/null)
    current_time=$(date +%s)
    time_diff=$((current_time - install_time))
    hours_old=$((time_diff / 3600))
    
    if [ $hours_old -lt 24 ]; then
        echo "MacPorts was installed $hours_old hours ago (less than 24 hours)."
        read -p "Do you want to skip MacPorts installation? (y/N): " skip_install
        if [[ $skip_install =~ ^[Yy]$ ]]; then
            echo "Skipping MacPorts installation."
            exit 0
        fi
    fi
fi

#########################################################

# Check if the mports folder exists in /opt/
if [ -d "/opt/mports" ]; then
  # If it does, tar and move the folder, then delete the original
  tar -cvzf /opt/mports$timestamp.tar.gz /opt/mports/
  mv /opt/mports$timestamp.tar.gz /opt/
  rm -rf /opt/mports
fi

# Create a new mports folder in /opt/ and cd into it
if ! sudo mkdir /opt/mports; then
    echo "Error: Failed to create /opt/mports directory"
    exit 1
fi

if ! cd /opt/mports; then
    echo "Error: Failed to change to /opt/mports directory"
    exit 1
fi

# Clone the macports-base repo
if ! git clone https://github.com/macports/macports-base.git; then
    echo "Error: Failed to clone macports-base repository"
    exit 1
fi

if ! cd macports-base; then
    echo "Error: Failed to change to macports-base directory"
    exit 1
fi

# Checkout stable release version (not dev/master)
echo "Checking out MacPorts $MACPORTS_VERSION..."
if ! git checkout "$MACPORTS_VERSION"; then
    echo "Error: Failed to checkout $MACPORTS_VERSION"
    exit 1
fi

echo "Building MacPorts $MACPORTS_VERSION"
if ! ./configure --enable-readline; then
    echo "Error: Failed to configure MacPorts"
    exit 1
fi

if ! make; then
    echo "Error: Failed to build MacPorts"
    exit 1
fi

if ! sudo make install; then
    echo "Error: Failed to install MacPorts"
    exit 1
fi

make distclean

# Adds the apropriate path for MacPorts to /etc/paths.d
echo ""
echo "Adding /opt/local as a local path"

sudo touch /etc/paths.d/macports
echo '/opt/local/bin' | sudo tee -a /etc/paths.d/macports
echo '/opt/local/sbin' | sudo tee -a /etc/paths.d/macports

# Update PATH for current session
export PATH="/opt/local/bin:/opt/local/sbin:$PATH"

#########################################################
# Runs a `port -v selfupdate` to set up for the first port installation.
# Also fix ownership in case tarball extraction creates files with wrong UIDs

echo "Port Self-update"
sudo port -v selfupdate

# Fix ownership of ports tree (tarball may have wrong UIDs)
echo "Fixing ports tree ownership..."
sudo chown -R macports:admin /opt/local/var/macports/sources/ 2>/dev/null || true

#########################################################
# Install essential packages via local Portfile

echo "Installing essential development packages..."
cd "$BOBLBEE_DIR"
sudo port install file://$PWD
