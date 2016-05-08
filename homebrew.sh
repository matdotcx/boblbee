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

# Update homebrew
brew update && brew upgrade brew-cask

# Install GNU core utilities (those that come with OS X are outdated)
brew install coreutils

# Install GNU `find`, `locate`, `updatedb`, and `xargs`, g-prefixed
brew install findutils

# Install Bash 4
brew install bash

# Install more recent versions of some OS X tools
brew tap homebrew/dupes
brew install homebrew/dupes/grep

# Install other useful binaries
binaries=(
  graphicsmagick
  webkit2png
  phantomjs
  rename
  zopfli
  ffmpeg
  python
  mongo
  sshfs
  trash
  tree
  ack
  git
  hub
  htop-osx
  pkg-config
  whatmask
  mtr
  grc
)

# Install the binaries
brew install ${binaries[@]}

# Remove outdated versions from the cellar
brew cleanup

exit 0
