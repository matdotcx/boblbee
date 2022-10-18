#########################################################
# Title; macports
# Description; Building macports from source
# Source; https://github.com/matdotcx/
#########################################################

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until we have finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Create a working directory to build from
echo "Creating MacPorts source location"
sudo mkdir -p /opt/mports
cd /opt/mports
# Clone from the project repo
git clone https://github.com/macports/macports-base.git
cd macports-base
# Checkout the current version and build / install / clean to `/opt/local`
git checkout
echo "Building MacPorts"
./configure --enable-readline
make
sudo make install
make distclean
