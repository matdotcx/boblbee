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
sh sudo "touchid-sudo.sh"
sh sudo "xcode.sh"
sh sudo "macports.sh"
sh sudo "defaults.sh"
