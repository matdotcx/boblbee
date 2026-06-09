#!/bin/zsh

#########################################################
# Title: macports
# Description: Building macports from source
# Source: https://github.com/matdotcx/
#########################################################

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until we have finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Define timestamp variable
timestamp=$(date +%d-%m-%Y_%H.%M.%S)

# MacPorts version to install (use stable release, not dev/master)
echo "Fetching latest MacPorts stable release..."
MACPORTS_VERSION=$(git ls-remote --tags https://github.com/macports/macports-base.git | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -1)

# Skip the (slow) build/reinstall when MacPorts is already present and recent,
# but always fall through to the package install step at the bottom — that way
# new packages added to the list reach existing hosts on the next sync.
SKIP_BUILD=
if [ -f "/opt/local/bin/port" ]; then
    install_time=$(stat -f %m /opt/local/bin/port 2>/dev/null)
    current_time=$(date +%s)
    time_diff=$((current_time - install_time))
    hours_old=$((time_diff / 3600))

    if [ $hours_old -lt 24 ] && [[ "${1:-}" != "--force" ]]; then
        echo "MacPorts was installed $hours_old hours ago — skipping rebuild."
        echo "Pass --force to rebuild from source."
        SKIP_BUILD=1
    fi
fi

#########################################################
# Build/install MacPorts (skipped when SKIP_BUILD is set)

if [ -z "$SKIP_BUILD" ]; then
    # Check if the mports folder exists in /opt/
    if [ -d "/opt/mports" ]; then
      # If it does, tar and move the folder, then delete the original
      sudo tar -cvzf /opt/mports$timestamp.tar.gz /opt/mports/
      sudo rm -rf /opt/mports
    fi

    # Create a new mports folder in /opt/ and cd into it
    if ! sudo mkdir /opt/mports; then
        echo "Error: Failed to create /opt/mports directory"
        exit 1
    fi
    sudo chown "$(id -u):$(id -g)" /opt/mports

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

    # Write /etc/paths.d/macports (overwrite, not append — prevents duplicates)
    echo ""
    echo "Adding /opt/local as a local path"

    printf '%s\n' '/opt/local/bin' '/opt/local/sbin' | sudo tee /etc/paths.d/macports > /dev/null

    # Update PATH for current session
    export PATH="/opt/local/bin:/opt/local/sbin:$PATH"

    #####################################################
    # Runs a `port -v selfupdate` to set up for the first port installation.
    # Also fix ownership in case tarball extraction creates files with wrong UIDs

    echo "Port Self-update"
    sudo port -v selfupdate
fi

# Ensure /opt/local is on PATH for the package-install step even when SKIP_BUILD
case ":$PATH:" in
    *":/opt/local/bin:"*) ;;
    *) export PATH="/opt/local/bin:/opt/local/sbin:$PATH" ;;
esac

# Fix ownership of ports tree (tarball may have wrong UIDs)
echo "Fixing ports tree ownership..."
sudo chown -R macports:admin /opt/local/var/macports/sources/ 2>/dev/null || true

#########################################################
# Install essential packages

# Install essential packages directly
echo "Installing essential packages..."
sudo /opt/local/bin/port install zsh-autosuggestions zsh-syntax-highlighting git curl gnupg2 gh ripgrep tree fzf coreutils tmux age