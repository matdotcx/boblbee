###############################################################################
# Title: zshrc (OPTIMIZED VERSION)
# Description: Fast-loading zshrc with lazy loading for slow operations
# Source: https://github.com/matdotcx/boblbee
# Edition: Optimized for fast startup
###############################################################################

export TERM="xterm-256color"
export LANG=en_GB.UTF-8
export EDITOR="zed"

###############################################################################
# Platform Detection
###############################################################################

is_macos() { [[ "$OSTYPE" == "darwin"* ]]; }
is_ubuntu() { [[ -f /etc/lsb-release ]] && grep -q "Ubuntu" /etc/lsb-release; }

###############################################################################
# Path Configuration (Fast)
###############################################################################

if is_ubuntu; then
    export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/bin:/usr/local/bin:$PATH"
else
    # macOS PATH
    export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

    # Skip brew --prefix call, use direct paths
    if [[ -d "/opt/homebrew" ]]; then
        # Apple Silicon - direct path, no brew call
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
    elif [[ -d "/usr/local/Homebrew" ]]; then
        # Intel - direct path, no brew call
        export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
    fi
fi

# Bun
export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL" ]] && export PATH="$BUN_INSTALL/bin:$PATH"

###############################################################################
# History Configuration
###############################################################################

HISTFILE=~/.zsh_history
HISTSIZE=10000000
SAVEHIST=$HISTSIZE
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_IGNORE_SPACE

###############################################################################
# Shell Options
###############################################################################

setopt NO_CASE_GLOB
setopt EXTENDED_GLOB
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_MINUS
setopt AUTO_CD
setopt NO_MATCH
setopt CORRECT
setopt INTERACTIVE_COMMENTS
unsetopt CORRECT_ALL
unsetopt NOTIFY
unsetopt BEEP

###############################################################################
# Lazy Load Completion System (Major speedup)
###############################################################################

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

# Completion options
setopt COMPLETE_IN_WORD
setopt AUTO_MENU
setopt ALWAYS_TO_END
setopt NO_BEEP

###############################################################################
# SKIP SSH Configuration on startup - load on demand
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
# Lazy Load ZSH Plugins (Major speedup)
###############################################################################

# Defer plugin loading until first command
__load_plugins() {
    local plugin_base=""

    # Use direct paths instead of brew --prefix
    if [[ -d "/opt/homebrew/share" ]]; then
        plugin_base="/opt/homebrew/share"
    elif [[ -d "/usr/local/share" ]]; then
        plugin_base="/usr/local/share"
    elif [[ -d "/opt/local/share" ]]; then
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
# Git Prompt Functions (Optimized)
###############################################################################

git_info() {
    ! git rev-parse --is-inside-work-tree > /dev/null 2>&1 && return

    local GIT_LOCATION=${$(git symbolic-ref -q HEAD || git name-rev --name-only --no-undefined --always HEAD)#(refs/heads/|tags/)}

    local AHEAD="%F{3}↑NUM%f"
    local BEHIND="%F{4}↓NUM%f"
    local MERGING="%F{5}⧂%f"
    local UNTRACKED="%F{1}⊕%f"
    local MODIFIED="%F{9}∆%f"
    local STAGED="%F{2}∙%f"

    local -a DIVERGENCES
    local -a FLAGS

    local NUM_AHEAD="$(git log --oneline @{u}.. 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$NUM_AHEAD" -gt 0 ]] && DIVERGENCES+=("${AHEAD//NUM/$NUM_AHEAD}")

    local NUM_BEHIND="$(git log --oneline ..@{u} 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$NUM_BEHIND" -gt 0 ]] && DIVERGENCES+=("${BEHIND//NUM/$NUM_BEHIND}")

    local GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)"
    [[ -n $GIT_DIR ]] && test -r $GIT_DIR/MERGE_HEAD && FLAGS+=("$MERGING")

    [[ -n $(git ls-files --other --exclude-standard 2>/dev/null) ]] && FLAGS+=("$UNTRACKED")
    ! git diff --quiet 2>/dev/null && FLAGS+=("$MODIFIED")
    ! git diff --cached --quiet 2>/dev/null && FLAGS+=("$STAGED")

    local -a GIT_INFO
    GIT_INFO+=("%F{4}[%f")
    [[ ${#DIVERGENCES[@]} -ne 0 ]] && GIT_INFO+=("${(j::)DIVERGENCES}")
    [[ ${#FLAGS[@]} -ne 0 ]] && GIT_INFO+=("${(j::)FLAGS}")
    GIT_INFO+=("%F{6}$GIT_LOCATION%f")
    GIT_INFO+=("%F{4}]%f")
    echo "${(j::)GIT_INFO}"
}

is_git_directory() {
    git rev-parse --is-inside-work-tree 2>/dev/null
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
        echo "localhost"
    fi
}

# Fast milliseconds function (skip python fallback)
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
# Command Timing & Prompt Setup (Simplified)
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

    # Show MOTD with cached system info
    if [[ -z "$MOTD_SHOWN" ]]; then
        print -P "\n» salva nos, stella maris!"
        print -P ""

        if [[ -f "$HOME/.motd" ]]; then
            local motd_line=$(sed '/^$/d' "$HOME/.motd" | sort -R | head -1)
            [[ -n "$motd_line" ]] && print -P "│  ${motd_line}\n"
        fi

        # Cache system info for fast retrieval
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

# Lazy function for full system info (call manually if needed)
sysinfo() {
    if is_macos; then
        print -P "│  You are connected to $(system_profiler SPHardwareDataType | awk '/Serial Number/ {print $4}') | $(sw_vers -productName) - $(sw_vers -productVersion) ($(sw_vers -buildVersion)) on $(uname -m)"
    elif is_ubuntu; then
        print -P "│  You are connected to $(hostname) | Ubuntu $(lsb_release -rs 2>/dev/null || echo 'Unknown') on $(uname -m)"
    fi
    print -P "│  System Uptime: $(calculate_uptime)"
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
# Core Aliases Only - Load rest on demand
###############################################################################

# Basic navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'

# Platform-specific ls colors
export LSCOLORS=Gxfxcxdxbxegedabagacad
if is_macos; then
    alias ls="ls -G"
elif is_ubuntu; then
    alias ls="ls --color=auto"
fi

# Essential git aliases
alias g='git'
alias gs='git status'
alias ga='git add'
alias gaa='git add -A'
alias gc='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# Lazy load the rest of aliases and functions
load_full_config() {
    if [[ -z "$FULL_CONFIG_LOADED" ]]; then
        source ~/.zshrc.full
        export FULL_CONFIG_LOADED=1
    fi
}

# Create a separate file with all the other functions/aliases
# and load them on first use
for cmd in cdh cdd cdw cdm ll tree gcauto feature gist fmt pycalc ip dns extract fif secret claude cx cxf bb-sync bb-status; do
    alias $cmd="load_full_config; $cmd"
done

###############################################################################
# FZF Integration (Lazy)
###############################################################################

if command -v fzf > /dev/null; then
    __init_fzf() {
        [[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh
        eval "$(fzf --zsh)" 2>/dev/null || true
    }

    # Lazy load FZF on first use
    fzf() {
        unset -f fzf
        __init_fzf
        command fzf "$@"
    }
fi

###############################################################################
# Anthropic/Coder Integration (Lazy)
###############################################################################

# Only source if file exists and on demand
if [[ -f /Users/diego/code/anthropic/config/local/zsh/zshrc ]]; then
    load_anthropic() {
        source /Users/diego/code/anthropic/config/local/zsh/zshrc
    }
    # Trigger load on first coder command
    alias coder="load_anthropic; coder"
fi

###############################################################################
# END OF OPTIMIZED CONFIGURATION
###############################################################################