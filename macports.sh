#########################################################
# Title; macports
# Description; Building macports from source
# Source; https://github.com/matdotcx/
#########################################################

# Create a working directory to build from
echo "Creating MacPorts source location"
mkdir -p /opt/mports
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