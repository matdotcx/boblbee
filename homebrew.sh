#########################################################
# Title; homebrew
# Description; Homebrew and binaries installer
# Credits; Diego Iaconelli
# Source; https://github.com/matdotcx/
# Initial Version; Sun Oct 25 12:05:41 GMT 2015
#########################################################

# Check for Homebrew
if test ! $(which brew); then
  echo "Installing homebrew..."
  ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# Make sure we’re using the latest Homebrew.
brew update

# Upgrade any already-installed formulae.
brew upgrade

# Install GNU core utilities (those that come with macOS are outdated).
# Don’t forget to add `$(brew --prefix coreutils)/libexec/gnubin` to `$PATH`.
brew install coreutils

# Install GNU `find`, `locate`, `updatedb`, and `xargs`, g-prefixed
brew install findutils

# Install Bash 4
brew install bash

# Switch to using brew-installed bash as default shell
if ! fgrep -q '/usr/local/bin/bash' /etc/shells; then
  echo '/usr/local/bin/bash' | sudo tee -a /etc/shells;
  chsh -s /usr/local/bin/bash;
fi;

# Install more recent versions of some macOS tools.
brew install vim --with-override-system-vi
brew install grep
brew install openssh
brew install screen
brew install homebrew/php/php56 --with-gmp

# Install other useful binaries
brew install ack
brew install git
brew install git-lfs
brew install lynx
brew install p7zip
brew install pv
brew install rename
brew install ssh-copy-id
brew install tree
brew install grc

# Remove outdated versions from the cellar
brew cleanup

exit 0
