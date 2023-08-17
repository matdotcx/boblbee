#########################################################
# Title; macports
# Description; Building macports from source
# Source; https://github.com/matdotcx/
#########################################################

#!/bin/zsh
# Ask for the administrator password upfront
sudo -v

#########################################################
# Keep-alive: update existing `sudo` time stamp until we have finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

#########################################################
# Define timestamp variable
timestamp=$(date +%d-%m-%Y_%H.%M.%S)

#########################################################
# runAsUser courtesy of Armin Briegel - Scripting OS X

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# get the currently logged in user
currentUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )

# global check if there is a user logged in
if [ -z "$currentUser" -o "$currentUser" = "loginwindow" ]; then
  echo "no user logged in, cannot proceed"
  exit 1
fi
# now we know a user is logged in

# get the current user's UID
uid=$(id -u "$currentUser")

# convenience function to run a command as the current user
# usage:
#   runAsUser command arguments...
runAsUser() {  
  if [ "$currentUser" != "loginwindow" ]; then
    launchctl asuser "$uid" sudo -u "$currentUser" "$@"
  else
    echo "no user logged in"
    # uncomment the exit command
    # to make the function exit with an error when no user is logged in
    # exit 1
  fi
}

#########################################################

# Check if the mports folder exists in /opt/
if [ -d "/opt/mports" ]; then
  # If it does, tar and move the folder, then delete the original
  tar -cvzf /opt/mports$timestamp.tar.gz /opt/mports/
  mv /opt/mports$timestamp.tar.gz /opt/
  rm -rf /opt/mports
fi

# Create a new mports folder in /opt/ and cd into it
sudo mkdir /opt/mports
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


#########################################################

# Adds the apropriate path for MacPorts to the working profile

echo ""
echo "Adding /opt/local as a local path"
runAsUser export PATH=/opt/local/bin:/opt/local/sbin:$PATH