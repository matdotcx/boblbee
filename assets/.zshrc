###############################################################################
# Title: zshrc
# Description: An improved ~/.zshrc
# Enhanced prompt with consistent symbols, and modern macOS compatibility
# Source: https://github.com/matdotcx/boblbee
# Edition: Sun 25 May 2025 23:38:12 BST
###############################################################################

#!/bin/zsh
export TERM="xterm-256color"
export LANG=en_GB.UTF-8
export PATH="$HOME/bin:$HOME/.local/bin:/opt/local/bin:/usr/local/bin:$PATH"

# Basic ANSI colors for prompts
export ANSI_RESET="%f"
export ANSI_GREEN="%F{2}"
export ANSI_YELLOW="%F{3}"
export ANSI_BLUE="%F{4}"
export ANSI_RED="%F{1}"
export ANSI_CYAN="%F{6}"
export ANSI_ORANGE="%F{9}"

###############################################################################
# zsh specifics
###############################################################################

HISTFILE=~/.zsh_history
HISTSIZE=1000000
SAVEHIST=1000000
setopt autocd nomatch correct inc_append_history share_history interactivecomments
unsetopt notify beep
zstyle :compinstall filename "$HOME/.zshrc"
autoload -Uz compinit && compinit
autoload -U colors && colors # Enable colors in prompt

# Preload keys to the ssh agent; passwords are pulled from the keychain.
# Supress stderr, leave errors to come through to the term.
ssh-add --apple-use-keychain ~/.ssh/id_rsa 2>/dev/null

###############################################################################
# Prompt & motd
###############################################################################

# Echoes information about Git repository status when inside a Git repository
git_info() {
  # Exit if not inside a Git repository
  ! git rev-parse --is-inside-work-tree > /dev/null 2>&1 && return

  # Git branch/tag, or name-rev if on detached head
  local GIT_LOCATION=${$(git symbolic-ref -q HEAD || git name-rev --name-only --no-undefined --always HEAD)#(refs/heads/|tags/)}

  local AHEAD="%F{3}↑NUM%f"
  local BEHIND="%F{4}↓NUM%f"
  local MERGING="%F{5}⧂%f"
  local UNTRACKED="%F{1}⊕%f"
  local MODIFIED="%F{9}∆%f"
  local STAGED="%F{2}∙%f"

  local -a DIVERGENCES
  local -a FLAGS

  local NUM_AHEAD="$(git log --oneline @{u}.. 2> /dev/null | wc -l | tr -d ' ')"
  if [ "$NUM_AHEAD" -gt 0 ]; then
    DIVERGENCES+=( "${AHEAD//NUM/$NUM_AHEAD}" )
  fi

  local NUM_BEHIND="$(git log --oneline ..@{u} 2> /dev/null | wc -l | tr -d ' ')"
  if [ "$NUM_BEHIND" -gt 0 ]; then
    DIVERGENCES+=( "${BEHIND//NUM/$NUM_BEHIND}" )
  fi

  local GIT_DIR="$(git rev-parse --git-dir 2> /dev/null)"
  if [ -n $GIT_DIR ] && test -r $GIT_DIR/MERGE_HEAD; then
    FLAGS+=( "$MERGING" )
  fi

  if [[ -n $(git ls-files --other --exclude-standard 2> /dev/null) ]]; then
    FLAGS+=( "$UNTRACKED" )
  fi

  if ! git diff --quiet 2> /dev/null; then
    FLAGS+=( "$MODIFIED" )
  fi

  if ! git diff --cached --quiet 2> /dev/null; then
    FLAGS+=( "$STAGED" )
  fi

  local -a GIT_INFO
  GIT_INFO+=( "%F{4}[%f" )
  [[ ${#DIVERGENCES[@]} -ne 0 ]] && GIT_INFO+=( "${(j::)DIVERGENCES}" )
  [[ ${#FLAGS[@]} -ne 0 ]] && GIT_INFO+=( "${(j::)FLAGS}" )
  GIT_INFO+=( "%F{6}$GIT_LOCATION%f" )
  GIT_INFO+=( "%F{4}]%f" )
  echo "${(j::)GIT_INFO}"
}


# Export Gitub personal access token
# Add the token to macOS keychain with `security add-generic-password -a ${USER} -s gh-token -w`
# Test with `security find-generic-password -a ${USER} -s gh-token -w`

export GITHUB_TOKEN=$(security find-generic-password -a ${USER} -s gh-token -w)

# Set up `gist` function

gist() {
    [ -z "$GITHUB_TOKEN" ] && echo "Error: GITHUB_TOKEN not set" && return 1
    filename="${1:-gist.txt}"
    content="${2:-$(cat)}"
    [ "$#" -eq 1 ] && [ ! -t 0 ] && content="$(cat)" && filename="$1"  # Handle piped input with filename
    curl -s -H "Authorization: token $GITHUB_TOKEN" \
         -H "Accept: application/vnd.github.v3+json" \
         https://api.github.com/gists \
         -d "{\"public\":false,\"files\":{\"$filename\":{\"content\":\"$content\"}}}" \
         | grep -o '"html_url": *"https://gist[^"]*"' | cut -d'"' -f4
}

# Calculate and format system uptime in a human-readable string
calculate_uptime() {
    local UPTIME=$(( $(date +%s) - $(sysctl -n kern.boottime | cut -d' ' -f4 | cut -d',' -f1) ))
    local d=$((UPTIME / 86400))
    local h=$(( (UPTIME % 86400) / 3600 ))
    local m=$(( (UPTIME % 3600) / 60 ))
    local s=$((UPTIME % 60))

    local result="System Uptime:"
    local components=()

    if [ $d -gt 0 ]; then
        if [ $d -eq 1 ]; then
            components+=("$d day")
        else
            components+=("$d days")
        fi
    fi
    if [ $h -gt 0 ]; then
        if [ $h -eq 1 ]; then
            components+=("$h hour")
        else
            components+=("$h hours")
        fi
    fi
    if [ $m -gt 0 ]; then
        if [ $m -eq 1 ]; then
            components+=("$m minute")
        else
            components+=("$m minutes")
        fi
    fi
    if [ $s -gt 0 ] || [ ${#components[@]} -eq 0 ]; then
        if [ $s -eq 1 ]; then
            components+=("$s second")
        else
            components+=("$s seconds")
        fi
    fi

    local output=""
    local count=${#components[@]}

    for ((i = 1; i <= count; i++)); do
        if [ $i -eq 1 ]; then
            output="${components[$i]}"
        elif [ $i -eq $count ] && [ $count -gt 1 ]; then
            output+=" and ${components[$i]}"
        else
            output+=", ${components[$i]}"
        fi
    done

    echo "$result $output"
}

# Function to determine if the current directory is git-tracked
is_git_directory() {
  git rev-parse --is-inside-work-tree 2> /dev/null
}

# Function to truncate the path if it's too long
truncated_pwd() {
    local pwd_length=30
    local pwd_symbol="..."
    local pwd_format="%${pwd_length}<${pwd_symbol}<%~%<<"
    echo ${(%)pwd_format}
}

# Function to set the color of the path based on git status
colored_path() {
  local pwd_with_slash="$(truncated_pwd)/"
  if is_git_directory; then
    echo "%F{2}${pwd_with_slash}%f"
  else
    echo "%F{4}${pwd_with_slash}%f"
  fi
}

# Function to determine if the session is remote
is_ssh() {
  [[ -n $SSH_CLIENT ]] || [[ -n $SSH_TTY ]]
}

# Function to set the appropriate color for the host
host_color() {
  if is_ssh; then
    echo "%F{9}"  # Orange for remote
  else
    echo "%F{6}"  # Cyan for local
  fi
}

# Function to get the hostname display
host_display() {
  if is_ssh; then
    echo "%M"  # Show actual hostname for remote
  else
    echo "localhost"  # Show "localhost" for local
  fi
}

# Function to get milliseconds for timestamp
get_milliseconds() {
    if command -v gdate >/dev/null 2>&1; then
        # macOS with GNU coreutils installed
        gdate +%3N
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS without GNU coreutils - use python
        python3 -c 'import datetime; print(f"{datetime.datetime.now().microsecond // 1000:03d}")'
    else
        # Linux
        date +%3N
    fi
}

# Function to determine the appropriate arrow color and symbol
arrow_prompt() {
    if [ $? -eq 0 ]; then
        echo "%F{2}"  # Green for success
    else
        echo "%F{9}"  # Orange for failure
    fi
    if [ $UID -eq 0 ]; then
        echo "#"
    else
        echo "➜"
    fi
}

# Function to be executed before each prompt
precmd() {
  # Get git information
  git_status=$(git_info)

  # Print system information only once when the shell starts
  if [ -z "$MOTD_SHOWN" ]; then
    print -P "\n» salva nos, stella maris!"
    print -P ""

    # Display random MOTD line from file if it exists
    if [ -f "$HOME/.motd" ]; then
      local motd_line=$(sed '/^$/d' "$HOME/.motd" | sort -R | head -1)
      if [ -n "$motd_line" ]; then
        print -P "│  ${motd_line}"
        print -P ""
      fi
    fi

    print -P "│  You are connected to $(system_profiler SPHardwareDataType | awk '/Serial Number/ {print $4}') | $(sw_vers -productName) - $(sw_vers -productVersion) ($(sw_vers -buildVersion)) on $(uname -m)"
    print -P "│  All access is logged. If you are not an authorised user, disconnect now."
    print -P "│  $(calculate_uptime)"
    print -P "│  $(date "+%A, %B %d, %Y | %T %Z")\n"
    MOTD_SHOWN=1
  fi
}

# Set the prompt
setopt prompt_subst

# Main prompt
PROMPT='$(arrow_prompt)%f %F{3}%n%f @ $(host_color)$(host_display)%f $(colored_path) ${git_status}%{$'\n'%}$(arrow_prompt)%f '

# Right prompt with timestamp
RPROMPT='%F{240}[%D{%H:%M:%S}.$(get_milliseconds) %D{%Z}]%f'

# Continuation prompt for multiline commands
PROMPT2="%F{3}▶%f "

# Selection prompt used within a select loop
PROMPT3="%F{3}?#%f "

# Execution trace prompt (setopt xtrace)
PROMPT4="%F{1}+%N:%i>%f "

###############################################################################
# Terminal settings
###############################################################################

# Customize the way history is displayed and saved
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_VERIFY

# Enable case-insensitive globbing
setopt NO_CASE_GLOB

# Enable extended globbing
setopt EXTENDED_GLOB

# Enable command auto-correction
setopt CORRECT
setopt CORRECT_ALL

# LSCOLORS - Default except for normal directories
export LSCOLORS=Gxfxcxdxbxegedabagacad

###############################################################################
# Key bindings
###############################################################################

# Use emacs key bindings
bindkey -e

# Configure key bindings for command history navigation
bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search
bindkey '^R' history-incremental-search-backward

# Enable menu-style completion
zstyle ':completion:*' menu select

# Configure history search
autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search
bindkey "^[[B" down-line-or-beginning-search

###############################################################################
# Shell & Navigation
###############################################################################

# Use colors in ls
alias ls="ls -G"

# Reload the shell (i.e. invoke as a login shell)
alias bb-reload="exec ${SHELL} -l"

# Print each PATH entry on a separate line
alias path='echo -e ${PATH//:/\\n}'

# Always enable colored `grep` output
alias grep='grep --color=auto'

# Colorize man pages using less
export MANPAGER="less -R --use-color -Dd+r -Du+b"
export LESS_TERMCAP_mb=$'\E[1;31m'     # begin blink
export LESS_TERMCAP_md=$'\E[1;36m'     # begin bold
export LESS_TERMCAP_me=$'\E[0m'        # reset bold/blink
export LESS_TERMCAP_so=$'\E[01;44;33m' # begin reverse video
export LESS_TERMCAP_se=$'\E[0m'        # reset reverse video
export LESS_TERMCAP_us=$'\E[1;32m'     # begin underline
export LESS_TERMCAP_ue=$'\E[0m'        # reset underline

# Show/Hide hidden files in Finder
alias showfiles="defaults write com.apple.finder AppleShowAllFiles YES; killall Finder"
alias hidefiles="defaults write com.apple.finder AppleShowAllFiles NO; killall Finder"

# Print working directory and ls after a cd
cd() { builtin cd "$@" && pwd && ls -AlhGti; }

# Change Directory to the active Finder window (else ~/Desktop)
cdf() {
    local fPath=$(osascript -e '
    tell app "finder"
        try
            set folderPath to (folder of the front window as alias)
        on error
            set folderPath to (path to desktop folder as alias)
        end try
        POSIX path of folderPath
    end tell')
    echo "cd $fPath"
    cd "$fPath"
}

# Change Directory to the current user's home directory
alias cdh='cd ~/'

# Change Directory to the user's Developer directory
alias cdd='cd ~/Developer'

# Change Directory to the user's workspace directory
alias cdw='cd ~/Developer/workspace'

# Change Directory to the current user's iCloud Drive
alias cdic='cd ~/Library/Mobile\ Documents/com~apple~CloudDocs'

# Change Directory up to the root of a current project
up() {
  local directory=$PWD
  local slashes=${directory//[^\/]/}
  for (( n=${#slashes}; n > 0; --n )); do
    directory=${directory%/*}
    if [[ $directory == $HOME ||
          -e $directory/package.json ||
          -e $directory/Cargo.toml ||
          -e $directory/.git ]]; then
      cd "$directory" && return
    fi
  done
}

# All files, long form, short file sizes, colorized, time-order, with inodes
alias ll='ls -AlhGti'

# Generates a tree of files from the current working directory
alias tree="find . -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'"

# Alias to display prompt symbol meanings
alias prompthelp='echo "Prompt Symbol Meanings:
  ↑  : Commits ahead of remote
  ↓  : Commits behind remote
  ⧂  : Merge in progress
  ⊕  : Untracked files present
  ∆  : Modified files present
  ∙  : Staged files present
  ➜  : Normal prompt (green if last command succeeded, orange if it failed)
  #  : Root user prompt
  ▶  : Continuation prompt for multiline commands

Color Meanings:
  Yellow : Username
  Cyan   : Hostname (for local sessions)
  Orange : Hostname (for remote/SSH sessions)
  Green  : Path (for git repositories)
  Blue   : Path (for non-git directories)
  Cyan   : Git branch name
"'

###############################################################################
# Network
###############################################################################

# IP addresses
alias ip="get_public_ip"
alias ips="list_ip_addresses"

get_public_ip() {
    curl -s https://api.ipify.org; echo
}

list_ip_addresses() {
    echo "IPv4 Addresses:"
    ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}'

    echo "\nIPv6 Addresses:"
    ifconfig | grep "inet6 " | grep -v "fe80" | awk '{print $2}'
}

# Show active network interfaces
alias ifactive="list_active_interfaces"
list_active_interfaces() {
    networksetup -listallhardwareports | awk '
    function get_ip(dev) {
        cmd = "ifconfig " dev " 2>/dev/null | awk \"/inet /{print \\$2}\""
        cmd | getline ip
        close(cmd)
        return ip
    }
    function get_mac(dev) {
        cmd = "ifconfig " dev " 2>/dev/null | awk \"/ether /{print \\$2}\""
        cmd | getline mac
        close(cmd)
        return mac
    }
    /Hardware Port/,/^$/ {
        if ($0 ~ /Hardware Port/) {
            if (device != "" && active == 1) {
                print hardware_port
                print "Device: " device
                print "Status: active"
                ip = get_ip(device)
                if (ip != "") print "IP Address: " ip
                mac = get_mac(device)
                if (mac != "") print "MAC Address: " mac
                print ""
            }
            hardware_port = $0
            device = ""
            active = 0
        } else if ($0 ~ /Device/) {
            device = $2
            cmd = "ifconfig " device " 2>/dev/null | grep status"
            cmd | getline ifconfig_status
            close(cmd)
            if (ifconfig_status ~ /active/) {
                active = 1
            }
        }
    }
    END {
        if (device != "" && active == 1) {
            print hardware_port
            print "Device: " device
            print "Status: active"
            ip = get_ip(device)
            if (ip != "") print "IP Address: " ip
            mac = get_mac(device)
            if (mac != "") print "MAC Address: " mac
            print ""
        }
    }'
}

# Run `nslookup` and display the most useful info
dns() {
    local domain="$1"
    local record_types=("A" "AAAA" "CNAME" "MX" "NS" "TXT")

    echo "DNS lookup for $domain"
    echo "----------------------------------------"

    for type in "${record_types[@]}"; do
        echo "Record type: $type"
        nslookup -type=$type "$domain" | grep -v "Server:" | grep -v "Address:" | sed '/^$/d'
        echo "----------------------------------------"
    done
}

###############################################################################
# System and Shortcuts
###############################################################################

# Flush DNS cache
alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"

# Clean up LaunchServices to remove duplicates in the "Open With" menu
alias lscleanup="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"

# Rebuild the Launch Services Database
alias launchdb='/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -kill -r -domain local -domain system -user'

# Fallback for hd, md5sum, and sha1sum
command -v hd > /dev/null || alias hd="hexdump -C"
command -v md5sum > /dev/null || alias md5sum="md5"
command -v sha1sum > /dev/null || alias sha1sum="shasum"

# Generate a password using haddock, length of 28 characters
alias secret='ha-gen -l 28'

# Update system and packages
alias update='sudo softwareupdate -i -a; brew update; brew upgrade; brew cleanup; npm update -g; sudo gem update --system; sudo gem update; sudo gem cleanup'

# Lock current account - activate screensaver (which requires password on wake)
alias lock="osascript -e 'tell application \"System Events\" to keystroke \"q\" using {command down,control down}'"

# Set default editor
export EDITOR="zed"

###############################################################################
# Anthropic specific zshrc config inc. conda
###############################################################################

# Source Anthropic config if it exists
if [ -f /Users/diego/code/anthropic/config/local/zsh/zshrc ]; then
    source /Users/diego/code/anthropic/config/local/zsh/zshrc
fi

# Claude Exec - Natural language command executor using Claude Code
# This function lets you describe what you want to do in plain language,
# and Claude will generate and execute the appropriate shell command.

function claude-exec() {
    # Show help message if requested
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        cat << 'EOF'
Claude Exec - Natural Language Command Executor
---------------------------------------------
This function uses Claude Code to translate plain English descriptions into
executable zsh commands. It's like having an AI shell assistant that understands
what you want to do and creates the command for you.

Usage: claude-exec [-f] [-q] "description of command"

Options:
  -f        Force execution without confirmation
  -q        Quiet mode - only show command output, no prompts or generated command
  -h, --help    Show this help message

Examples:
  claude-exec "list all PDF files modified in the last week"
  claude-exec -f "find the largest files in my Downloads folder"
  claude-exec -q "show disk usage sorted by size" > usage.txt
  claude-exec -fq "list all files" | wc -l

Notes:
- By default, the function shows the generated command and asks for confirmation
- Use -f to execute immediately without confirmation
- Use -q for quiet mode when piping output or redirecting to files
- Combine -f and -q for pipe-friendly forced execution
- The aliases 'cx' (regular), 'cxf' (force), 'cxq' (quiet), and 'cxfq' (force+quiet) are available
- Special characters like '?' and '*' in your description are treated as
  literal characters, not shell globs, thanks to noglob
EOF
        return 0
    fi

    local force_execute=false
    local quiet_mode=false
    local description

    # Parse options
    while getopts "fqh" opt; do
        case $opt in
            f) force_execute=true ;;
            q) quiet_mode=true ;;
            h) claude-exec --help; return 0 ;;
            *) echo "Usage: claude-exec [-f] [-q] \"description of command\"" >&2
               return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    # Check if description is provided
    if [[ $# -eq 0 ]]; then
        echo "Error: Please provide a command description" >&2
        echo "Usage: claude-exec [-f] [-q] \"description of command\"" >&2
        return 1
    fi

    description="$*"

    # Craft a robust prompt for Claude
    local prompt="You are a command-line assistant that must output EXACTLY the zsh command needed to accomplish the following task. Do not include any explanations, comments, or additional text.

TASK: ${description}

Requirements:
1. Output ONLY the exact zsh command or commands (pipeline/multiline is acceptable)
2. Ensure the command is valid zsh syntax
3. Use standard zsh features like globs, functions, and built-ins where appropriate
4. Do not include any markdown formatting, code blocks, or explanations
5. Your response will be directly piped to zsh, so it must be executable as-is
6. Ensure proper escaping of special characters if needed
7. Commands should be optimized for the task, using the most efficient approach"

    # Get the command from Claude
    local command_output
    command_output=$(claude -p "$prompt" 2>/dev/null)

    # Check if Claude returned anything
    if [[ -z "$command_output" ]]; then
        [[ "$quiet_mode" = false ]] && echo "Error: Claude returned no output" >&2
        return 1
    fi

    # Check if output looks like an error message (starts with "Error:" or contains common error patterns)
    if [[ "$command_output" =~ ^Error: ]] || [[ "$command_output" =~ "I apologize" ]] || [[ "$command_output" =~ "I cannot" ]]; then
        [[ "$quiet_mode" = false ]] && echo "Claude returned an error or refusal:" >&2
        [[ "$quiet_mode" = false ]] && echo "$command_output" >&2
        return 1
    fi

    # In quiet mode, skip all prompts and just execute
    if [[ "$quiet_mode" = true ]]; then
        eval "$command_output"
        return $?
    fi

    # Display the command for review
    echo "Generated command:"
    echo "----------------"
    echo "$command_output" | bat -l zsh --style=plain --paging=never 2>/dev/null || echo "$command_output"
    echo "----------------"

    # Ask for confirmation unless -f flag is used
    if [[ "$force_execute" = true ]]; then
        echo "Executing command..."
        eval "$command_output"
    else
        echo ""
        echo -n "Execute this command? [y/N] "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "Executing command..."
            eval "$command_output"
        else
            echo "Command execution cancelled."
            return 1
        fi
    fi
}

# Aliases for convenience - using noglob to prevent special characters from being interpreted as globs
alias cx='noglob claude-exec'
alias cxf='noglob claude-exec -f'
alias cxq='noglob claude-exec -q'
alias cxfq='noglob claude-exec -fq'

# Tab completion for claude-exec
_claude_exec_complete() {
    _arguments \
        '-f[Force execution without confirmation]' \
        '-q[Quiet mode - only show command output]' \
        '1:description:_files'
}
compdef _claude_exec_complete claude-exec

###############################################################################
# Boblbee Dotfiles Management
###############################################################################

# Main commands
alias bb-help='echo "Boblbee Dotfiles Commands:

SETUP & MAINTENANCE:
  bb-setup      : Run complete system setup (new machines)
  bb-upgrade    : Upgrade existing boblbee installation
  bb-status     : Check sync status of all components

SYNC COMMANDS:
  bb-sync       : Sync all configurations (zshrc, claude, ssh)
  bb-sync-zshrc : Sync shell configuration
  bb-sync-claude: Sync Claude Code preferences
  bb-sync-ssh   : Sync SSH configuration (iCloud only)

UTILITIES:
  bb-edit       : Edit boblbee scripts directory
  bb-reload     : Reload shell (restarts with fresh prompt)

HELP:
  bb-help       : Show this help message
  prompthelp    : Show prompt symbol meanings

For detailed documentation, see:
  ~/Developer/workspace/matdotcx/boblbee/DOCUMENTATION.md
"'

# Setup and maintenance
alias bb-setup="cd $HOME/Developer/workspace/matdotcx/boblbee/scripts && ./index.sh"
alias bb-upgrade="$HOME/Developer/workspace/matdotcx/boblbee/scripts/upgrade.sh"

# Sync commands
alias bb-sync-zshrc="$HOME/Developer/workspace/matdotcx/boblbee/scripts/zshrc-sync.sh"
alias bb-sync-claude="$HOME/Developer/workspace/matdotcx/boblbee/scripts/claude-sync.sh"
alias bb-sync-ssh="$HOME/Developer/workspace/matdotcx/boblbee/scripts/ssh-sync.sh"

# Sync all function
bb-sync() {
  echo "=== Boblbee Full Sync ==="
  echo ""
  echo "Syncing zshrc..."
  bb-sync-zshrc
  echo ""
  echo "Syncing Claude preferences..."
  bb-sync-claude
  echo ""
  echo "Syncing SSH (if applicable)..."
  bb-sync-ssh
  echo ""
  echo "✓ All syncs complete!"
}

# Status check function
bb-status() {
  echo "=== Boblbee Status ==="
  echo ""

  # Check boblbee directory
  if [ -d "$HOME/Developer/workspace/matdotcx/boblbee" ]; then
    echo "✓ Boblbee directory found"
    cd "$HOME/Developer/workspace/matdotcx/boblbee"
    echo "  Git status: $(git status -s | wc -l | xargs) uncommitted changes"
  else
    echo "✗ Boblbee directory not found"
  fi

  # Check iCloud
  if [ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ]; then
    echo "✓ iCloud Drive available"
  else
    echo "✗ iCloud Drive not available"
  fi

  # Check symlinks
  echo ""
  echo "Configuration status:"
  if [ -L "$HOME/.zshrc" ]; then
    echo "  .zshrc: symlinked to $(readlink $HOME/.zshrc)"
  else
    echo "  .zshrc: regular file"
  fi

  if [ -L "$HOME/.ssh" ]; then
    echo "  .ssh: symlinked to $(readlink $HOME/.ssh)"
  else
    echo "  .ssh: regular directory"
  fi

  if [ -L "$HOME/.config/claude/memory/user.md" ]; then
    echo "  Claude: symlinked to dotfiles"
  else
    echo "  Claude: not configured"
  fi
}

# Utilities
bb-edit() {
  cd "$HOME/Developer/workspace/matdotcx/boblbee"
  if [ -n "$EDITOR" ]; then
    $EDITOR .
  elif command -v zed >/dev/null; then
    zed .
  elif command -v code >/dev/null; then
    code .
  elif command -v subl >/dev/null; then
    subl .
  elif command -v vim >/dev/null; then
    vim .
  else
    echo "No editor found. Set EDITOR environment variable or install Zed/VS Code/Sublime/Vim"
    echo "Current directory: $(pwd)"
  fi
}

###############################################################################
# Git Shortcuts
###############################################################################

# Essential git aliases - save your fingers!
alias gs='git status'                # Instead of: git status
alias ga='git add'                   # Instead of: git add
alias gaa='git add -A'               # Instead of: git add -A (add all)
alias gc='git commit -m'             # Instead of: git commit -m "message"
alias gp='git push'                  # Instead of: git push
alias gpo='git push origin'          # Instead of: git push origin
alias gl='git pull'                  # Instead of: git pull
alias gd='git diff'                  # Instead of: git diff
alias gco='git checkout'             # Instead of: git checkout
alias gb='git branch'                # Instead of: git branch
alias glog='git log --oneline --graph --decorate'  # Pretty git log

# Useful git combinations
alias gac='git add -A && git commit -m'  # Add all and commit: gac "message"
alias gst='git stash'                     # Stash changes
alias gsp='git stash pop'                 # Pop stash

# Git status shortcuts
alias g='git'                        # Even shorter git commands: g status
