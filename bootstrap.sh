#########################################################
# Title; bootstrap
# Description; initial setup for boblbee
# Source; https://github.com/matdotcx/
#########################################################

#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE}")";

git pull origin gold;

function doIt() {
	rsync --exclude ".git/" --exclude ".DS_Store" --exclude "bootstrap.sh" \
		--exclude "README.md" --exclude "LICENSE.txt" -avh --no-perms . ~;
}

if [ "$1" == "--force" -o "$1" == "-f" ]; then
	doIt;
else
	read -p "This may overwrite existing files in your home directory. Are you sure? (y/n) " -n 1;
	echo "";
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		doIt;
	fi;
fi;
unset doIt;
