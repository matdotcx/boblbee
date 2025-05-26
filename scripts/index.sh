#########################################################
# Title; index
# Description; Call and install each module
# Source; https://github.com/matdotcx/
#########################################################

# Note: Some scripts require sudo privileges.
# They will ask for password when needed.

# Run each program
echo "Starting boblbee setup..."

sudo sh touchid-sudo.sh
sleep 3
sh identity.sh
sleep 3
sh xcode.sh
sleep 3
sudo sh macports.sh
sleep 3
sh dots.sh
sleep 3
sh claude.sh
sleep 3
sh zshrc-sync.sh
sleep 3
sh ssh-sync.sh
sleep 3
