###############################################################################
# Title: zshrc
# Description: An improved ~/.zshrc
# Enhanced prompt with consistent symbols, and modern macOS compatibility
# Source: https://github.com/matdotcx/boblbee
# Edition: Unified version with optimizations
###############################################################################

export TERM="xterm-256color"
export LANG=en_GB.UTF-8
export EDITOR="zed --wait"

###############################################################################
# Platform Detection
###############################################################################

is_macos() { [[ "$OSTYPE" == "darwin"* ]]; }
is_ubuntu() { [[ -f /etc/lsb-release ]] && grep -q "Ubuntu" /etc/lsb-release; }

###############################################################################
# Path Configuration
###############################################################################

if is_ubuntu; then
    export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"
else
    # macOS PATH
    export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

    # Package manager paths (optimized - skip brew --prefix call)
    if [[ -d "/opt/homebrew" ]]; then
        # Homebrew Apple Silicon - direct path
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
    elif [[ -d "/usr/local/Homebrew" ]]; then
        # Homebrew Intel - direct path
        export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
    elif [[ -d "/opt/local/bin" ]]; then
        # MacPorts
        export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
    fi
fi

# Bun
export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL" ]] && export PATH="$BUN_INSTALL/bin:$PATH"

###############################################################################
# Auto-attach tmux on SSH sessions
###############################################################################

if [[ -n "$SSH_CONNECTION" || -n "$SSH_TTY" ]] && [[ -z "$TMUX" ]] && command -v tmux &>/dev/null; then
    # Attach to existing session named 'ssh', or create one
    tmux attach-session -t ssh 2>/dev/null || tmux new-session -s ssh
fi

###############################################################################
# History Configuration
###############################################################################

HISTFILE=~/.zsh_history
HISTSIZE=10000000                # 10 million like eli
SAVEHIST=$HISTSIZE
setopt INC_APPEND_HISTORY        # Write immediately
setopt SHARE_HISTORY             # Share between sessions
setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks
setopt HIST_VERIFY               # Don't execute immediately on expansion
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicates first
setopt HIST_IGNORE_DUPS          # Don't record duplicates
setopt HIST_IGNORE_ALL_DUPS      # Delete old duplicates
setopt HIST_FIND_NO_DUPS         # Don't display duplicates
setopt HIST_SAVE_NO_DUPS         # Don't save duplicates
setopt HIST_IGNORE_SPACE         # Don't record lines starting with space

###############################################################################
# Shell Options
###############################################################################

setopt NO_CASE_GLOB              # Case-insensitive globbing
setopt EXTENDED_GLOB             # Extended globbing patterns
setopt AUTO_PUSHD                # Push directories onto stack
setopt PUSHD_IGNORE_DUPS         # Don't duplicate directories
setopt PUSHD_MINUS               # Reverse +/- meanings
setopt AUTO_CD                   # cd by typing directory name
setopt NO_MATCH                  # No error on no matches
setopt CORRECT                   # Spelling correction for commands
setopt INTERACTIVE_COMMENTS      # Allow comments in interactive shell
unsetopt CORRECT_ALL             # Don't correct arguments
unsetopt NOTIFY                  # Report status of background jobs immediately
unsetopt BEEP                    # No beeping

###############################################################################
# Completion System (Lazy loaded for faster startup - saves ~50-80ms)
###############################################################################

# Completion options
setopt COMPLETE_IN_WORD          # Complete from cursor position
setopt AUTO_MENU                 # Use menu completion after second tab
setopt ALWAYS_TO_END             # Move cursor to end after completion
setopt NO_BEEP                   # Don't beep on errors

# Defer compinit to first tab press
__init_completion() {
    autoload -Uz compinit
    # Use dump file to speed up initialization
    if [[ -f "$HOME/.zcompdump" ]]; then
        # Check if dump file is older than 24 hours
        if [[ $(find "$HOME/.zcompdump" -mtime +1 -print 2>/dev/null) ]]; then
            compinit -C
            compdump
        else
            compinit -C
        fi
    else
        compinit -C
        compdump
    fi

    autoload -U colors && colors

    # Setup completion styles
    zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
    zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
    zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
    zstyle ':completion:*:warnings' format '%F{red}No matches found%f'
    zstyle ':completion:*' group-name ''
    zstyle ':completion:*' use-cache on
    zstyle ':completion:*' cache-path ~/.zsh/cache
    zstyle ':completion:*' menu select

    # Unbind and rebind to use real completion
    bindkey '^I' complete-word
    bindkey '^[[Z' reverse-menu-complete
}

# Lazy load on first tab
__lazy_complete() {
    unset -f __lazy_complete
    __init_completion
    zle complete-word
}
zle -N __lazy_complete
bindkey '^I' __lazy_complete

###############################################################################
# SSH Configuration (Lazy loaded for faster startup)
###############################################################################

# Function to initialize SSH when needed
init_ssh() {
    if [[ -z "$SSH_INITIALIZED" ]]; then
        if is_macos; then
            ssh-add --apple-use-keychain ~/.ssh/id_rsa 2>/dev/null
        elif is_ubuntu; then
            if command -v keychain &>/dev/null; then
                eval $(keychain --eval --agents ssh --quiet id_rsa)
            elif [[ -z "$SSH_AUTH_SOCK" ]]; then
                eval $(ssh-agent -s)
                ssh-add ~/.ssh/id_rsa 2>/dev/null
            fi
        fi
        export SSH_INITIALIZED=1
    fi
}

# Auto-init SSH only when using git or ssh commands
ssh() { init_ssh; command ssh "$@"; }
git() { init_ssh; command git "$@"; }
gh() { init_ssh; command gh "$@"; }

###############################################################################
# Plugins (zsh-syntax-highlighting & zsh-autosuggestions)
###############################################################################

# Lazy load plugins for faster startup
__load_plugins() {
    local plugin_base=""

    # Use direct paths instead of brew --prefix (saves ~30-50ms)
    if [[ -d "/opt/homebrew/share" ]]; then
        # Homebrew Apple Silicon
        plugin_base="/opt/homebrew/share"
    elif [[ -d "/usr/local/share" ]]; then
        # Homebrew Intel
        plugin_base="/usr/local/share"
    elif [[ -d "/opt/local/share" ]]; then
        # MacPorts
        plugin_base="/opt/local/share"
    else
        return 1
    fi

    # Load plugins if they exist
    local syntax_hl="$plugin_base/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    local autosugg="$plugin_base/zsh-autosuggestions/zsh-autosuggestions.zsh"

    [[ -f "$syntax_hl" ]] && source "$syntax_hl"
    [[ -f "$autosugg" ]] && source "$autosugg"

    # Configure autosuggestions
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=240'
    bindkey '^ ' autosuggest-accept  # Ctrl+Space to accept

    export PLUGINS_LOADED=1
}

# Load plugins on first prompt
precmd_functions+=(__lazy_load_plugins)
__lazy_load_plugins() {
    if [[ -z "$PLUGINS_LOADED" ]]; then
        __load_plugins
    fi
    # Remove from precmd after first run
    precmd_functions=(${precmd_functions:#__lazy_load_plugins})
}


###############################################################################
# Key Bindings
###############################################################################

bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search
bindkey '^R' history-incremental-search-backward

autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search
bindkey "^[[B" down-line-or-beginning-search

###############################################################################
# Git Prompt Functions
###############################################################################

git_info() {
    ! command git rev-parse --is-inside-work-tree > /dev/null 2>&1 && return

    local GIT_LOCATION=${$(command git symbolic-ref -q HEAD || command git name-rev --name-only --no-undefined --always HEAD)#(refs/heads/|tags/)}

    local AHEAD="%F{3}↑NUM%f"
    local BEHIND="%F{4}↓NUM%f"
    local MERGING="%F{5}⧂%f"
    local UNTRACKED="%F{1}⊕%f"
    local MODIFIED="%F{9}∆%f"
    local STAGED="%F{2}∙%f"

    local -a DIVERGENCES
    local -a FLAGS

    local NUM_AHEAD="$(command git log --oneline @{u}.. 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$NUM_AHEAD" -gt 0 ]] && DIVERGENCES+=("${AHEAD//NUM/$NUM_AHEAD}")

    local NUM_BEHIND="$(command git log --oneline ..@{u} 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$NUM_BEHIND" -gt 0 ]] && DIVERGENCES+=("${BEHIND//NUM/$NUM_BEHIND}")

    local GIT_DIR="$(command git rev-parse --git-dir 2>/dev/null)"
    [[ -n $GIT_DIR ]] && test -r $GIT_DIR/MERGE_HEAD && FLAGS+=("$MERGING")

    [[ -n $(command git ls-files --other --exclude-standard 2>/dev/null) ]] && FLAGS+=("$UNTRACKED")
    ! command git diff --quiet 2>/dev/null && FLAGS+=("$MODIFIED")
    ! command git diff --cached --quiet 2>/dev/null && FLAGS+=("$STAGED")

    local -a GIT_INFO
    GIT_INFO+=("%F{4}[%f")
    [[ ${#DIVERGENCES[@]} -ne 0 ]] && GIT_INFO+=("${(j::)DIVERGENCES}")
    [[ ${#FLAGS[@]} -ne 0 ]] && GIT_INFO+=("${(j::)FLAGS}")
    GIT_INFO+=("%F{6}$GIT_LOCATION%f")
    GIT_INFO+=("%F{4}]%f")
    echo "${(j::)GIT_INFO}"
}

is_git_directory() {
    command git rev-parse --is-inside-work-tree 2>/dev/null
}

truncated_pwd() {
    local pwd_length=30
    local pwd_symbol="..."
    local pwd_format="%${pwd_length}<${pwd_symbol}<%~%<<"
    echo ${(%)pwd_format}
}

colored_path() {
    local pwd_with_slash="$(truncated_pwd)/"
    if is_git_directory; then
        echo "%F{2}${pwd_with_slash}%f"
    else
        echo "%F{4}${pwd_with_slash}%f"
    fi
}

is_ssh() {
    [[ -n $SSH_CLIENT ]] || [[ -n $SSH_TTY ]]
}

host_color() {
    if is_ssh; then
        echo "%F{9}"  # Orange for remote
    else
        echo "%F{6}"  # Cyan for local
    fi
}

host_display() {
    if is_ssh; then
        echo "%M"
    else
        echo "%m\\\\local"
    fi
}

# Fast milliseconds function (optimized)
get_milliseconds() {
    if command -v gdate >/dev/null 2>&1; then
        gdate +%3N
    else
        # Just return 000 on macOS without gdate - faster than python
        echo "000"
    fi
}

arrow_prompt() {
    if [[ $? -eq 0 ]]; then
        echo "%F{2}"  # Green for success
    else
        echo "%F{9}"  # Orange for failure
    fi
    if [[ $UID -eq 0 ]]; then
        echo "#"
    else
        echo "➜"
    fi
}

###############################################################################
# Command Timing & Prompt Setup
###############################################################################

preexec() {
    timer=$(($(print -P %D{%s%6.}) / 1000))
    _last_command="$1"
}

precmd() {
    local exit_code=$?

    # Handle command timing
    if [[ -n $timer ]]; then
        local now=$(($(print -P %D{%s%6.}) / 1000))
        local elapsed=$(($now - $timer))

        if (( elapsed > 15000 )); then
            local d_s=$((elapsed / 1000))
            local hours=$((d_s / 3600))
            local minutes=$(((d_s / 60) % 60))
            local seconds=$((d_s % 60))
            local time_str=""

            (( hours > 0 )) && time_str="${hours}h "
            (( minutes > 0 )) && time_str="${time_str}${minutes}m "
            time_str="${time_str}${seconds}s"

            local color
            if (( d_s > 300 )); then
                color="%F{red}"
            elif (( d_s > 60 )); then
                color="%F{yellow}"
            else
                color="%F{green}"
            fi

            local cmd_name="${_last_command%% *}"
            if (( ${#cmd_name} > 30 )); then
                cmd_name="${cmd_name:0:27}..."
            fi

            print -P "${color}⏱  %B${cmd_name}%b took: %B${time_str}%b%f"
        fi

        unset timer
        unset _last_command
    fi

    # Get git information
    git_status=$(git_info)

    # Set terminal title
    echo -ne "\033]0;${HOST%%.*} - $(basename $SHELL)\007"

    # Show MOTD once with cached system info
    if [[ -z "$MOTD_SHOWN" ]]; then
        print -P "\n» salva nos, stella maris!"
        print -P ""

        if [[ -f "$HOME/.motd" ]]; then
            local motd_line=$(sed '/^$/d' "$HOME/.motd" | sort -R | head -1)
            if [[ -n "$motd_line" ]]; then
                local wrap_width=$((${COLUMNS:-80} - 5))
                local wrapped=$(print -r -- "$motd_line" | fold -s -w $wrap_width)
                while IFS= read -r line; do
                    print "│  $line"
                done <<< "$wrapped"
                print ""
            fi
        fi

        # Cache system info for fast retrieval (saves ~350-400ms)
        local cache_file="$HOME/.zsh_sysinfo_cache"
        local cache_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || echo 0)))

        if [[ ! -f "$cache_file" ]] || [[ $cache_age -gt 86400 ]]; then
            # Cache is old or missing, regenerate in background
            (
                if is_macos; then
                    local serial=$(system_profiler SPHardwareDataType | awk '/Serial Number/ {print $4}')
                    local os_info="$(sw_vers -productName) - $(sw_vers -productVersion) ($(sw_vers -buildVersion)) on $(uname -m)"
                    echo "$serial|$os_info" > "$cache_file"
                elif is_ubuntu; then
                    echo "$(hostname)|Ubuntu $(lsb_release -rs 2>/dev/null || echo 'Unknown') on $(uname -m)" > "$cache_file"
                fi
            ) &!

            # Use placeholder while cache updates
            if is_macos; then
                print -P "│  You are connected to $(hostname -s) | macOS on $(uname -m)"
            elif is_ubuntu; then
                print -P "│  You are connected to $(hostname) | Ubuntu on $(uname -m)"
            fi
        else
            # Use cached info
            local cached_info=$(cat "$cache_file")
            local serial="${cached_info%%|*}"
            local os_info="${cached_info#*|}"
            print -P "│  You are connected to $serial | $os_info"
        fi

        print -P "│  All access is logged. If you are not an authorised user, disconnect now."
        print -P "│  System Uptime: $(calculate_uptime)"
        print -P "│  $(date '+%A, %B %d, %Y | %T %Z')\n"
        MOTD_SHOWN=1
    fi
}

calculate_uptime() {
    local UPTIME
    if is_macos; then
        UPTIME=$(( $(date +%s) - $(sysctl -n kern.boottime | cut -d' ' -f4 | cut -d',' -f1) ))
    elif is_ubuntu; then
        UPTIME=$(awk '{print int($1)}' /proc/uptime)
    else
        UPTIME=0
    fi

    local d=$((UPTIME / 86400))
    local h=$(( (UPTIME % 86400) / 3600 ))
    local m=$(( (UPTIME % 3600) / 60 ))
    local s=$((UPTIME % 60))

    local components=()
    [[ $d -gt 0 ]] && components+=("$d day$([ $d -ne 1 ] && echo 's')")
    [[ $h -gt 0 ]] && components+=("$h hour$([ $h -ne 1 ] && echo 's')")
    [[ $m -gt 0 ]] && components+=("$m minute$([ $m -ne 1 ] && echo 's')")
    [[ $s -gt 0 || ${#components[@]} -eq 0 ]] && components+=("$s second$([ $s -ne 1 ] && echo 's')")

    local output=""
    local count=${#components[@]}
    for ((i = 1; i <= count; i++)); do
        if [[ $i -eq 1 ]]; then
            output="${components[$i]}"
        elif [[ $i -eq $count && $count -gt 1 ]]; then
            output+=" and ${components[$i]}"
        else
            output+=", ${components[$i]}"
        fi
    done

    echo "$output"
}

# Set prompts
setopt prompt_subst
PROMPT='$(arrow_prompt)%f %F{3}%n%f @ $(host_color)$(host_display)%f $(colored_path) ${git_status}%{$'\n'%}$(arrow_prompt)%f '
RPROMPT='%F{240}[%D{%H:%M:%S}.$(get_milliseconds) %D{%Z}]%f'
PROMPT2="%F{3}▶%f "
PROMPT3="%F{3}?#%f "
PROMPT4="%F{1}+%N:%i>%f "

###############################################################################
# Navigation Aliases & Functions
###############################################################################

# Basic navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'
alias cdh='cd ~/'
alias cdd='cd ~/Developer'
alias cdw='cd ~/Developer/workspace'
alias cdm='cd ~/Developer/workspace/matdotcx'

# macOS-specific navigation
if is_macos; then
    alias cdic='cd ~/Library/Mobile\ Documents/com~apple~CloudDocs'

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
fi

# Directory stack shortcuts
alias d='dirs -v'
for index ({1..9}) alias "$index"="cd +${index}"; unset index

# Enhanced cd - shows content after changing
cd() {
    if builtin cd "$@" 2>/dev/null; then
        pwd && ls -AlhGti
    else
        echo "cd: no such file or directory: $@"
        return 1
    fi
}

# Create and enter directory
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Go up to project root
up() {
    local directory=$PWD
    local slashes=${directory//[^\/]/}
    for (( n=${#slashes}; n > 0; --n )); do
        directory=${directory%/*}
        if [[ $directory == $HOME ||
              -e $directory/package.json ||
              -e $directory/Cargo.toml ||
              -e $directory/.git ||
              -e $directory/pyproject.toml ]]; then
            cd "$directory" && return
        fi
    done
}

###############################################################################
# Directory Bookmarks
###############################################################################

BOOKMARKS_FILE="${HOME}/.zsh_bookmarks"
[[ ! -f "$BOOKMARKS_FILE" ]] && touch "$BOOKMARKS_FILE"
source "$BOOKMARKS_FILE" 2>/dev/null || true

bookmark() {
    local cmd=$1
    shift

    case "$cmd" in
        add)
            local name=$1
            if [[ -z "$name" ]]; then
                echo "Usage: bookmark add <name>"
                return 1
            fi
            local escaped_path="${PWD//\$/\\\$}"
            escaped_path="${escaped_path//\`/\\\`}"
            echo "alias jump_${name}='cd \"${escaped_path}\"'" >> "$BOOKMARKS_FILE"
            alias "jump_${name}=cd \"${escaped_path}\""
            echo "Bookmarked current directory as '${name}'"
            ;;
        list)
            echo "Directory bookmarks:"
            grep "^alias jump_" "$BOOKMARKS_FILE" 2>/dev/null | \
                sed 's/alias jump_/  /;s/=.*cd "/: /;s/"$//' || echo "  No bookmarks yet"
            ;;
        remove)
            local name=$1
            if [[ -z "$name" ]]; then
                echo "Usage: bookmark remove <name>"
                return 1
            fi
            grep -v "^alias jump_${name}=" "$BOOKMARKS_FILE" > "${BOOKMARKS_FILE}.tmp" && \
                mv "${BOOKMARKS_FILE}.tmp" "$BOOKMARKS_FILE"
            unalias "jump_${name}" 2>/dev/null
            echo "Removed bookmark '${name}'"
            ;;
        *)
            echo "Usage: bookmark <add|list|remove> [name]"
            ;;
    esac
}

jump() {
    local name=$1
    if [[ -z "$name" ]]; then
        echo "Usage: jump <bookmark_name>"
        bookmark list
        return 1
    fi

    if alias "jump_${name}" &>/dev/null; then
        eval "jump_${name}"
    else
        echo "Bookmark '${name}' not found"
        bookmark list
        return 1
    fi
}

if (( $+functions[compdef] )); then
    _jump_completion() {
        local bookmarks=($(grep "^alias jump_" "$BOOKMARKS_FILE" 2>/dev/null | \
            sed 's/alias jump_//;s/=.*//' || true))
        _describe 'bookmark' bookmarks
    }
    compdef _jump_completion jump
fi

###############################################################################
# Listing Functions
###############################################################################

# Platform-specific ls colors
export LSCOLORS=Gxfxcxdxbxegedabagacad
unalias ls 2>/dev/null
if is_macos; then
    alias ls="ls -G"
else
    alias ls="ls --color=auto"
fi

# Enhanced listing
unalias ll 2>/dev/null
ll() {
    if is_macos; then
        local ls_output=$(CLICOLOR_FORCE=1 ls -lhAFGT "$@")
        local total_line=""
        local dirs=()
        local files=()

        while IFS= read -r line; do
            if [[ $line == total* ]]; then
                total_line="$line"
            elif [[ $line == d* ]]; then
                dirs+=("$line")
            else
                files+=("$line")
            fi
        done <<< "$ls_output"

        [[ -n $total_line ]] && echo "$total_line"
        for line in "${dirs[@]}"; do echo "$line"; done
        for line in "${files[@]}"; do echo "$line"; done
    else
        ls -lhAF --group-directories-first "$@"
    fi
}

# Tree view
if command -v tree > /dev/null; then
    alias tree='tree -C'
else
    alias tree="find . -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'"
fi

###############################################################################
# Git Functions & Aliases
###############################################################################

# Essential git aliases
alias g='git'
alias gs='git status'
alias ga='git add'
alias gaa='git add -A'
alias gc='git commit -m'
alias gp='git push'
alias gpo='git push origin'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate'
alias gac='git add -A && git commit -m'
alias gst='git stash'
alias gsp='git stash pop'

# Smart commit with pre-commit handling
gcauto() {
    local message="${1:-Update}"
    git add -A

    if git commit -m "$message"; then
        echo "✓ Commit successful"
    else
        if git status --porcelain | grep -q "^[AM]"; then
            echo "Pre-commit made changes, retrying..."
            git add -A
            git commit -m "$message"
        fi
    fi
}

# Create feature branch with GitHub username
feature() {
    set -e
    local feature_name=$1

    local GH_USER
    if command -v gh &>/dev/null && gh auth status &>/dev/null; then
        GH_USER=$(gh api user --jq .login)
    else
        GH_USER=$(git config user.name | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        [[ -z "$GH_USER" ]] && GH_USER=$(whoami)
    fi

    local stash_output="$(git stash)"

    git checkout master || git checkout main
    git pull --rebase origin master || git pull --rebase origin main
    git checkout -b "${GH_USER}/${feature_name}"

    if [[ $stash_output != "No local changes to save" ]]; then
        git stash apply
    fi

    echo "Created branch: ${GH_USER}/${feature_name}"
}

# GitHub activity reporter
repo-man() {
    local GH_USER=$(gh api user --jq .login)
    local DATE_FILTER
    if is_macos; then
        DATE_FILTER=">$(date -v-7d '+%Y-%m-%d')"
    else
        DATE_FILTER=">$(date -d '7 days ago' '+%Y-%m-%d')"
    fi

    echo "Activity for: $GH_USER (last 7 days)"
    echo ""

    echo "• PRs Authored"
    gh search prs --author="$GH_USER" --created="$DATE_FILTER" --limit 50

    echo -e "\n• PRs Reviewed"
    gh search prs --reviewed-by="$GH_USER" --updated="$DATE_FILTER" --limit 50

    echo -e "\n• Issues Created"
    gh search issues --author="$GH_USER" --updated="$DATE_FILTER" --limit 50

    echo -e "\n• All Activity"
    gh search issues --involves="$GH_USER" --updated="$DATE_FILTER" --sort=updated --limit 50

    echo -e "\n• Commits"
    gh search commits --author="$GH_USER" --author-date="$DATE_FILTER" --limit 1000
}

# Ship changes: create feature branch, push, and create auto-merge PR
shipit() {
    if [[ -z "$1" ]]; then
        echo "Usage: shipit <description>"
        echo "Example: shipit add-new-aliases"
        return 1
    fi

    local description="$1"
    local GH_USER
    if command -v gh &>/dev/null && gh auth status &>/dev/null; then
        GH_USER=$(gh api user --jq .login 2>/dev/null)
    fi
    GH_USER="${GH_USER:-$(whoami)}"
    local branch_name="${GH_USER}/${description}"

    git checkout -b "$branch_name"
    git add -A

    if git commit -m "feat: ${description}"; then
        echo "✓ Commit successful"
    else
        if git status --porcelain | grep -q "^[AM]"; then
            echo "Pre-commit made changes, retrying..."
            git add -A
            git commit -m "feat: ${description}"
        fi
    fi

    git push -u origin "$branch_name"
    gh pr create --fill --web

    echo "✓ PR created"
}

# GitHub token setup
if is_macos; then
    export GITHUB_TOKEN=$(security find-generic-password -a ${USER} -s gh-token -w 2>/dev/null)
elif is_ubuntu && [[ -f "$HOME/.github_token" ]]; then
    export GITHUB_TOKEN=$(cat "$HOME/.github_token")
fi

# Gist creator
gist() {
    [[ -z "$GITHUB_TOKEN" ]] && echo "Error: GITHUB_TOKEN not set" && return 1
    filename="${1:-gist.txt}"
    content="${2:-$(cat)}"
    [[ "$#" -eq 1 ]] && [[ ! -t 0 ]] && content="$(cat)" && filename="$1"

    curl -s -H "Authorization: token $GITHUB_TOKEN" \
         -H "Accept: application/vnd.github.v3+json" \
         https://api.github.com/gists \
         -d "{\"public\":false,\"files\":{\"$filename\":{\"content\":\"$content\"}}}" \
         | grep -o '"html_url": *"https://gist[^"]*"' | cut -d'"' -f4
}

###############################################################################
# Python & Testing
###############################################################################

alias py='python'
alias pytest='pytest -v'
alias ruff='ruff check --fix'
alias act="source .venv/bin/activate"

# Pre-commit on PR files
fmt() {
    local files=()
    git diff --name-only $(git merge-base master HEAD) | while read line; do
        files+=("$line")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No files changed"
        return 0
    fi

    echo "Running ruff/pyright on:"
    printf '* %s\n' "${files[@]}"
    echo ""

    pre-commit run ruff --hook-stage pre-push --color=always --files "${files[@]}"
    pre-commit run pyright --hook-stage manual --color=always --files "${files[@]}"
}

alias pre-commit-pr='pre-commit run --from-ref $(git merge-base master HEAD) --to-ref HEAD'

# Python calculator
pycalc() {
    python3 -c "from math import *; print($*)"
}

###############################################################################
# Network Utilities
###############################################################################

alias ip="get_public_ip"
alias ips="list_ip_addresses"

get_public_ip() {
    curl -s https://api.ipify.org; echo
}

list_ip_addresses() {
    echo "IPv4 Addresses:"
    if is_macos; then
        ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}'
    elif is_ubuntu; then
        ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d'/' -f1
    fi

    echo "\nIPv6 Addresses:"
    if is_macos; then
        ifconfig | grep "inet6 " | grep -v "fe80" | awk '{print $2}'
    elif is_ubuntu; then
        ip -6 addr show | grep inet6 | grep -v "fe80" | awk '{print $2}' | cut -d'/' -f1
    fi
}

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

# Platform-specific network utilities
if is_macos; then
    alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
    alias ifactive="networksetup -listallhardwareports | grep -A2 'Status: active'"
elif is_ubuntu; then
    alias flushdns="sudo systemctl restart systemd-resolved"
    alias ifactive="ip link show | grep 'state UP'"
fi

###############################################################################
# Utility Functions
###############################################################################

# Extract archives
extract() {
    if [[ -f "$1" ]]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar e "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *)           echo "'$1' cannot be extracted" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Search with ripgrep
fif() {
    if [[ "$#" -eq 0 ]]; then
        echo "Usage: fif <search_term> [rg_options]"
        return 1
    fi
    rg "$@" .
}

# Track file changes
track_changes() {
    local watch_dir="$1"
    shift
    local command="$@"
    local before_file=$(mktemp)
    local after_file=$(mktemp)

    if [[ ! -d "$watch_dir" ]]; then
        echo "Error: Directory '$watch_dir' does not exist"
        rm "$before_file" "$after_file"
        return 1
    fi

    echo "=== Tracking changes in directory: $watch_dir ==="

    # Platform-specific find command
    if is_macos; then
        find "$watch_dir" -type f -exec stat -f "%N%t%m%t%z" {} \; | sort > "$before_file"
    else
        find "$watch_dir" -type f -printf '%P\t%T@\t%s\n' | sort > "$before_file"
    fi

    eval "$command"
    local cmd_exit_code=$?

    if is_macos; then
        find "$watch_dir" -type f -exec stat -f "%N%t%m%t%z" {} \; | sort > "$after_file"
    else
        find "$watch_dir" -type f -printf '%P\t%T@\t%s\n' | sort > "$after_file"
    fi

    echo "=== FILE CHANGES DETECTED ==="
    comm -13 <(cut -f1 "$before_file") <(cut -f1 "$after_file") | while read -r file; do
        echo "  + $file"
    done
    comm -23 <(cut -f1 "$before_file") <(cut -f1 "$after_file") | while read -r file; do
        echo "  - $file"
    done

    rm "$before_file" "$after_file"
    return $cmd_exit_code
}

# Generate password
alias secret='ha-gen -l 28' 2>/dev/null || alias secret='openssl rand -base64 28'

# Colored grep and man pages
alias grep='grep --color=auto'
alias path='echo -e ${PATH//:/\\n}'

export MANPAGER="less -R --use-color -Dd+r -Du+b"
export LESS_TERMCAP_mb=$'\E[1;31m'
export LESS_TERMCAP_md=$'\E[1;36m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_us=$'\E[1;32m'
export LESS_TERMCAP_ue=$'\E[0m'

# Fallback commands
command -v hd > /dev/null || alias hd="hexdump -C"
command -v md5sum > /dev/null || alias md5sum="md5"
command -v sha1sum > /dev/null || alias sha1sum="shasum"

###############################################################################
# System Maintenance
###############################################################################

# Platform-specific system utilities
if is_macos; then
    alias showfiles="defaults write com.apple.finder AppleShowAllFiles YES; killall Finder"
    alias hidefiles="defaults write com.apple.finder AppleShowAllFiles NO; killall Finder"
    alias lscleanup="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"
    alias launchdb='/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -kill -r -domain local -domain system -user'
    alias update='sudo softwareupdate -i -a; brew update; brew upgrade; brew cleanup; npm update -g'
    alias lock="osascript -e 'tell application \"System Events\" to keystroke \"q\" using {command down,control down}'"
elif is_ubuntu; then
    alias update='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && npm update -g'
    alias install='sudo apt install'
    alias search='apt search'
    alias show='apt show'

    install-deb() {
        sudo dpkg -i "$1" && sudo apt-get install -f
    }

    if command -v gnome-screensaver-command >/dev/null 2>&1; then
        alias lock="gnome-screensaver-command -l"
    elif command -v loginctl >/dev/null 2>&1; then
        alias lock="loginctl lock-session"
    fi
fi

###############################################################################
# FZF Integration
###############################################################################

if command -v fzf > /dev/null; then
    [[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh
    eval "$(fzf --zsh)" 2>/dev/null || true
    alias fim='vim $(fzf)'
fi

###############################################################################
# Claude Integration
###############################################################################


claude-exec() {
    [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]] && {
        cat << 'EOF'
Claude Exec - Natural Language Command Executor
Usage: claude-exec [-f] [-q] "description of command"

Options:
  -f        Force execution without confirmation
  -q        Quiet mode - only show command output
  -h        Show this help message

Examples:
  claude-exec "list all PDF files modified in the last week"
  claude-exec -f "find the largest files in Downloads"
EOF
        return 0
    }

    local force_execute=false
    local quiet_mode=false

    while getopts "fqh" opt; do
        case $opt in
            f) force_execute=true ;;
            q) quiet_mode=true ;;
            h) claude-exec --help; return 0 ;;
            *) echo "Usage: claude-exec [-f] [-q] \"description\"" >&2; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    [[ $# -eq 0 ]] && echo "Error: Please provide a command description" >&2 && return 1

    local description="$*"
    local prompt="Output ONLY the exact zsh command needed for: ${description}. No explanations or formatting."

    local command_output=$(claude -p "$prompt" 2>/dev/null)
    [[ -z "$command_output" ]] && [[ "$quiet_mode" = false ]] && echo "Error: Claude returned no output" >&2 && return 1

    if [[ "$quiet_mode" = true ]]; then
        eval "$command_output"
        return $?
    fi

    echo "Generated command:"
    echo "----------------"
    echo "$command_output"
    echo "----------------"

    if [[ "$force_execute" = true ]]; then
        echo "Executing command..."
        eval "$command_output"
    else
        echo -n "Execute this command? [y/N] "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            eval "$command_output"
        else
            echo "Command execution cancelled."
            return 1
        fi
    fi
}

alias cx='noglob claude-exec'
alias cxf='noglob claude-exec -f'
alias cxq='noglob claude-exec -q'
alias cxfq='noglob claude-exec -fq'

###############################################################################
# Anthropic/Coder Integration
###############################################################################

[[ -f $HOME/code/anthropic/config/local/zsh/zshrc ]] && \
    source $HOME/code/anthropic/config/local/zsh/zshrc

zedspace() {
    if [[ -z "$1" ]]; then
        open "zed://ssh/coder.diego/root/src/anthropic"
    else
        open "zed://ssh/main.$1.diego.coder/root/src/$1"
    fi
}

###############################################################################
# Boblbee Dotfiles Management
###############################################################################

# Auto-detect boblbee directory from common locations
if [[ -d "$HOME/Developer/workspace/matdotcx/boblbee" ]]; then
  BOBLBEE_DIR="$HOME/Developer/workspace/matdotcx/boblbee"
elif [[ -d "$HOME/workspace/matdotcx/boblbee" ]]; then
  BOBLBEE_DIR="$HOME/workspace/matdotcx/boblbee"
elif [[ -d "/workspace/matdotcx/boblbee" ]]; then
  BOBLBEE_DIR="/workspace/matdotcx/boblbee"
fi

alias bb-help='echo "Boblbee Commands: bb-setup, bb-upgrade, bb-sync, bb-sync-{zshrc,tmux,ghostty,claude,ssh,motd}, bb-status, bb-edit"'
alias bb-setup="cd $BOBLBEE_DIR/scripts && ./index.sh"
alias bb-upgrade="$BOBLBEE_DIR/scripts/upgrade.sh"
alias bb-sync-zshrc="$BOBLBEE_DIR/scripts/zshrc-sync.sh"
alias bb-sync-tmux="$BOBLBEE_DIR/scripts/tmux-sync.sh"
alias bb-sync-ghostty="$BOBLBEE_DIR/scripts/ghostty-sync.sh"
alias bb-sync-claude="$BOBLBEE_DIR/scripts/claude-sync.sh"
alias bb-sync-ssh="$BOBLBEE_DIR/scripts/ssh-sync.sh"
alias bb-sync-motd="$BOBLBEE_DIR/scripts/motd-sync.sh"
alias bb-reload="exec ${SHELL} -l"

bb-sync() {
    echo "=== Boblbee Full Sync ==="
    bb-sync-zshrc
    bb-sync-tmux
    [[ "$OSTYPE" == "darwin"* ]] && bb-sync-ghostty
    bb-sync-motd
    bb-sync-claude
    bb-sync-ssh
    # Push any commits made by the sync scripts
    if [[ -d "$BOBLBEE_DIR" ]] && git -C "$BOBLBEE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if [[ -n $(git -C "$BOBLBEE_DIR" log --oneline @{u}..HEAD 2>/dev/null) ]]; then
            echo "Pushing changes to remote..."
            git -C "$BOBLBEE_DIR" push && echo "Pushed successfully." || echo "Push failed."
        fi
    fi
    echo "All syncs complete!"
}

bb-status() {
    echo "=== Boblbee Status ==="
    [[ -d "$BOBLBEE_DIR" ]] && echo "✓ Boblbee directory found" || echo "✗ Boblbee directory not found"
    [[ -L "$HOME/.zshrc" ]] && echo "  .zshrc: symlinked" || echo "  .zshrc: regular file"
    [[ -L "$HOME/.ssh" ]] && echo "  .ssh: symlinked" || echo "  .ssh: regular directory"
}

bb-edit() {
    cd "$BOBLBEE_DIR"
    ${EDITOR:-vim} .
}

###############################################################################
# CI Debugging
###############################################################################

ci_failed() {
    gh pr view --json statusCheckRollup --jq '.statusCheckRollup[] | select(.state == "FAILURE") | .targetUrl'
}

###############################################################################
# Kubernetes (if available)
###############################################################################

if command -v kubectl > /dev/null; then
    alias k='kubectl'
    alias kgp='kubectl get pods'
    alias kl='kubectl logs'
    alias ke='kubectl exec -it'
fi

###############################################################################
# Docker (if available)
###############################################################################

if command -v docker > /dev/null; then
    alias dps='docker ps'
    alias dpsa='docker ps -a'
    alias di='docker images'
    alias dex='docker exec -it'
    alias dl='docker logs'
    alias drm='docker rm'
    alias drmi='docker rmi'
fi

###############################################################################
# Prompt Help
###############################################################################

alias prompthelp='echo "Prompt Symbols:
  ↑  : Commits ahead of remote
  ↓  : Commits behind remote
  ⧂  : Merge in progress
  ⊕  : Untracked files
  ∆  : Modified files
  ∙  : Staged files
  ➜  : Normal prompt
  #  : Root user prompt"'

###############################################################################
# END OF CONFIGURATION
###############################################################################
