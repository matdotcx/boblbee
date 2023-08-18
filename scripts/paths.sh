#########################################################
# Title; macports
# Description; Building macports from source
# Source; https://github.com/matdotcx/
#########################################################

#!/bin/zsh
# Ask for the administrator password upfront
sudo -v

# Adds the apropriate path for MacPorts to the working profile

echo ""
echo "Adding /opt/local as a local path"

sudo touch /etc/paths.d/macports
echo '/opt/local/bin' | sudo tee -a /etc/paths.d/macports
echo '/opt/local/sbin' | sudo tee -a /etc/paths.d/macports