#########################################################
# Title; macports
# Description; Building macports from source
# Source; https://github.com/matdotcx/
#########################################################

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until we have finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Define timestamp variable
timestamp=$(date +%d-%m-%Y_%H.%M.%S)

#########################################################

# Check if the mports folder exists in /opt/
if [ -d "/opt/mports" ]; then
  # If it does, tar and move the folder, then delete the original
  tar -cvzf /opt/mports$timestamp.tar.gz /opt/mports/
  mv /opt/mports$timestamp.tar.gz /opt/
  rm -rf /opt/mports
fi

# Create a new mports folder in /opt/ and cd into it
mkdir /opt/mports
cd /opt/mports

# Clone the macports-base repo
git clone https://github.com/macports/macports-base.git && cd macports-base

# Checkout the current version and build / install / clean to `/opt/local`
git checkout
echo "Building MacPorts"
./configure --enable-readline
make
sudo make install
make distclean
