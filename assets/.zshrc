# Basic zsh configuration - will be replaced by boblbee sync
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"

# Enable colors
autoload -U colors && colors

# Basic prompt
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '

# History configuration
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=1000
setopt autocd
