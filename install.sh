#########################################################
# Title; install.sh
# Description; Installer for bobblbee; an OS X dots repo.
# Credits; Diego Iaconelli
# Source; https://github.com/matdotcx/
# Initial Version; Mon 29 Aug 2013 03:12:04 BST
#########################################################


# paths
dirname=$(pwd)
lib="/usr/local/lib"
bin="/usr/local/bin"

# make in case they aren't already there
mkdir -p "/usr/local/lib"
mkdir -p "/usr/local/bin"

# Copy the path
sudo cp -R $dirname "$lib/"

# remove existing bin if it exists
if [ -e "$bin/bobblbee" ]; then
  rm "$bin/bobblbee"
fi

# symlink bobblbee
ln -s "$lib/bobblbee/bobblbee.sh" "$bin/bobblbee"