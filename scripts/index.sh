#########################################################
# Title; index
# Description; Call and install each module
# Source; https://github.com/matdotcx/
#########################################################

# Ask for the administrator password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until we have finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Run each program
sudo sh touchid-sudo.sh
sleep 3
sudo sh xcode.sh
sleep 3
sudo sh macports.sh
sleep 3
sudo sh defaults.sh
sleep 3
