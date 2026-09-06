#!/usr/bin/env bash
#
# lib.sh — shared helpers for boblbee scripts
#
# Source detect-os.sh and lib/config.sh before this file.
# Provides: colours, logging, file-mtime, iCloud checks, sync helpers, git commit.

###############################################################################
# Colour codes
###############################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m' # No Colour

###############################################################################
# Logging
###############################################################################

log_message() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >&2
}

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

###############################################################################
# Progress spinner (adapted from matdotcx/dropship)
###############################################################################

# Braille frames, kept as an array so indexing is per-character regardless of
# the shell's locale (a multibyte string slice can land mid-character).
PROGRESS_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
PROGRESS_QUIET_AFTER=20   # seconds of silence before the "still working" hint

# run_with_progress <label> <command> [args...]
#
# Runs the command with combined stdout+stderr captured to a temp log. On an
# interactive terminal it draws a single self-updating line — braille spinner,
# label, elapsed time, and the command's most recent output line — so a long
# quiet build (e.g. compiling rust) never looks hung. If output stalls for
# PROGRESS_QUIET_AFTER seconds the trailing text switches to "still working".
#
# When stdout is NOT a TTY (e.g. fleet runs whose output is captured to a file)
# it streams the full output via tee instead, so logs stay complete.
#
# The full log path is left in RWP_LOG for the caller to inspect (grep for a
# marker, tail on failure) and remove. Returns the command's exit status.
RWP_LOG=""
run_with_progress() {
    local label="$1"; shift

    # Refresh sudo credentials up front so a backgrounded sudo command never
    # blocks on a password prompt hidden behind the spinner line.
    if [[ "${1##*/}" == sudo ]]; then
        sudo -v 2>/dev/null || true
    fi

    local log
    log=$(mktemp "${TMPDIR:-/tmp}/bb-update.XXXXXX") || log="/tmp/bb-update.$$"
    RWP_LOG="$log"

    # No TTY: stream full output (keeps fleet logs complete) and return.
    if [[ ! -t 1 ]]; then
        "$@" 2>&1 | tee "$log"
        return "${PIPESTATUS[0]}"
    fi

    "$@" >"$log" 2>&1 &
    local pid=$!

    local start=$SECONDS i=0 last_size=0 last_change=$SECONDS
    local frame elapsed mm ss size activity shown cols prefix_len avail
    while kill -0 "$pid" 2>/dev/null; do
        frame=${PROGRESS_FRAMES[i++ % ${#PROGRESS_FRAMES[@]}]}
        elapsed=$((SECONDS - start)); mm=$((elapsed / 60)); ss=$((elapsed % 60))

        # Detect silence by watching the log stop growing.
        size=$(( $(wc -c <"$log" 2>/dev/null || echo 0) ))
        if [[ "$size" != "$last_size" ]]; then last_size=$size; last_change=$SECONDS; fi

        activity=$(tail -n1 "$log" 2>/dev/null | tr -d '\r\n\t')
        if (( SECONDS - last_change >= PROGRESS_QUIET_AFTER )); then
            shown="still working${activity:+ — $activity}"
        else
            shown="$activity"
        fi

        # Truncate only the plain-text tail so colour codes are never sliced.
        cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
        prefix_len=$(( 1 + 1 + ${#label} + 1 + 5 + 2 ))   # spinner+sp+label+sp+MM:SS+2sp
        avail=$(( cols - prefix_len - 1 )); (( avail < 0 )) && avail=0
        shown=${shown:0:avail}

        printf "\r\033[K${BLUE}%s${NC} ${DIM}%s${NC} ${GREEN}%02d:%02d${NC}  %s" \
            "$frame" "$label" "$mm" "$ss" "$shown"
        sleep 0.1
    done
    wait "$pid"; local rc=$?
    printf "\r\033[K"   # clear the spinner line
    return $rc
}

###############################################################################
# iCloud detection (directory exists + key files are not evicted)
###############################################################################

check_icloud() {
    if ! is_macos; then
        return 1
    fi
    if [ ! -d "$ICLOUD_BASE" ]; then
        log_message "INFO" "iCloud directory does not exist"
        return 1
    fi
    # Check that the sync directory is present and not an evicted placeholder
    if [ ! -d "$ICLOUD_SYNC_PATH" ]; then
        log_message "INFO" "iCloud sync directory ($ICLOUD_SYNC_DIR) does not exist"
        return 1
    fi
    # Verify files are actually materialised (not just placeholders)
    # A quick stat on the directory is enough — if it's evicted the dir won't be traversable
    if ! ls "$ICLOUD_SYNC_PATH" >/dev/null 2>&1; then
        log_message "INFO" "iCloud sync directory exists but appears evicted"
        return 1
    fi
    return 0
}

###############################################################################
# ark-config detection (private config repo cloned as a sibling of boblbee)
###############################################################################

# True when the ark-config repo is checked out and contains boblbee's private
# material. This is the non-iCloud source of truth for SSH config + keys.
check_ark_config() {
    [ -d "$ARK_BOBLBEE_DIR" ] && [ -f "$ARK_BOBLBEE_DIR/ssh_config" ]
}

###############################################################################
# File helpers
###############################################################################

# Get file modification time as epoch seconds.
# Follows symlinks, returns "0" if file does not exist.
get_file_mtime() {
    local file="$1"
    if [ -L "$file" ]; then
        # Resolve symlink to absolute path (readlink alone returns relative on some systems)
        local link_target
        link_target="$(readlink "$file")"
        case "$link_target" in
            /*) file="$link_target" ;;
            *)  file="$(cd "$(dirname "$file")" && cd "$(dirname "$link_target")" && pwd)/$(basename "$link_target")" ;;
        esac
    fi
    if [ -f "$file" ]; then
        # Probe the BSD form first and fall back to GNU. Deliberately not using
        # is_macos() here: that lives in detect-os.sh, and a caller sourcing
        # lib.sh alone would otherwise get 0 for every file — silently making
        # every mtime comparison a tie and sending syncs the wrong way.
        stat -f %m "$file" 2>/dev/null \
            || stat -c %Y "$file" 2>/dev/null \
            || echo "0"
    else
        echo "0"
    fi
}

# Return the path of the newest file among the given arguments.
find_newest_file() {
    local newest_file=""
    local newest_time=0
    local current_time

    for file in "$@"; do
        if [ -f "$file" ] || [ -L "$file" ]; then
            current_time=$(get_file_mtime "$file")
            if [ "$current_time" -gt "$newest_time" ]; then
                newest_time="$current_time"
                newest_file="$file"
            fi
        fi
    done
    echo "$newest_file"
}

# Check write permissions on the parent directory of a path.
check_permissions() {
    local target_dir
    target_dir="$(dirname "$1")"
    if [ ! -w "$target_dir" ]; then
        echo -e "${RED}✗ No write permission for $target_dir${NC}"
        return 1
    fi
    return 0
}

# Backup a regular file (skips symlinks). Returns 0 if no backup needed.
backup_file() {
    local file="$1"
    if [ -f "$file" ] && [ ! -L "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}Backing up $(basename "$file") to $backup${NC}"
        if cp "$file" "$backup" 2>/dev/null; then
            echo -e "${GREEN}Backup created successfully${NC}"
            return 0
        else
            echo -e "${RED}Backup failed${NC}"
            log_message "ERROR" "Failed to backup $file to $backup"
            return 1
        fi
    fi
    return 0
}

###############################################################################
# Git helpers
###############################################################################

# Push the current branch to origin so other hosts stay in sync.
# Must be called from within DOTFILES_DIR (e.g. the commit subshell).
# On a non-fast-forward rejection, integrates remote work via pull --rebase
# and retries; if that conflicts, aborts the rebase and warns rather than
# leaving the repo mid-rebase.
push_dotfiles_changes() {
    if ! git remote get-url origin >/dev/null 2>&1; then
        echo -e "${BLUE}No 'origin' remote, skipping push${NC}"
        return 0
    fi

    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)

    if git push origin "$branch" 2>/dev/null; then
        echo -e "${GREEN}Pushed to origin/$branch${NC}"
        return 0
    fi

    echo -e "${YELLOW}Push rejected — integrating remote changes with pull --rebase${NC}"
    if git pull --rebase origin "$branch" 2>/dev/null && git push origin "$branch" 2>/dev/null; then
        echo -e "${GREEN}Pushed to origin/$branch after rebase${NC}"
        return 0
    fi

    git rebase --abort 2>/dev/null
    echo -e "${RED}Push failed: remote diverged with conflicts. Resolve manually in $DOTFILES_DIR.${NC}"
    return 1
}

# Commit changes in DOTFILES_DIR.
# Usage: commit_dotfiles_changes "commit message" file1 [file2 ...]
# Files are relative to DOTFILES_DIR (e.g. "assets/.zshrc").
commit_dotfiles_changes() {
    local commit_msg="$1"
    shift
    local files=("$@")

    # Run in a subshell so the cd doesn't affect the caller's cwd
    (
        cd "$DOTFILES_DIR" || exit 1

        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            if git add "${files[@]}" 2>/dev/null; then
                if git diff --staged --quiet; then
                    echo -e "${BLUE}No changes to commit${NC}"
                    exit 0
                else
                    if git commit -m "$commit_msg" 2>/dev/null; then
                        echo -e "${GREEN}Changes committed to git: $commit_msg${NC}"
                        push_dotfiles_changes
                        exit 0
                    else
                        echo -e "${YELLOW}Git commit failed, but file was updated${NC}"
                        exit 1
                    fi
                fi
            else
                echo -e "${YELLOW}Git add failed, but file was updated${NC}"
                exit 1
            fi
        else
            echo -e "${BLUE}Not in a git repository, skipping commit${NC}"
            exit 0
        fi
    )
}

###############################################################################
# Three-way sync helper
###############################################################################

# sync_dotfile <display_name> <home_file> <repo_file> <icloud_file> <git_add_pattern>
#
# Performs newest-mtime-wins sync across up to three locations:
#   home (local copy) ↔ repo (git-tracked) ↔ iCloud (cross-host sharing)
#
# If <icloud_file> is empty or iCloud is unavailable, falls back to 2-way.
# Ensures home is always a real file (migrates symlinks).
# Commits repo changes to git.
sync_dotfile() {
    local display_name="$1"
    local home_file="$2"
    local repo_file="$3"
    local icloud_file="$4"
    local git_add_pattern="$5"

    # Check repo source exists
    if [ ! -f "$repo_file" ]; then
        echo -e "${RED}✗ Source file not found: $repo_file${NC}"
        return 1
    fi

    local use_icloud=false
    if [ -n "$icloud_file" ] && check_icloud; then
        use_icloud=true
        echo -e "${BLUE}iCloud Drive detected${NC}"
        # Ensure iCloud directory structure exists
        mkdir -p "$(dirname "$icloud_file")" 2>/dev/null || true
        # Seed iCloud from repo if it doesn't exist
        if [ ! -f "$icloud_file" ]; then
            echo -e "${YELLOW}Creating $display_name in iCloud Drive from dotfiles${NC}"
            cp "$repo_file" "$icloud_file" 2>/dev/null || true
        fi
    else
        if is_macos && [ -n "$icloud_file" ]; then
            echo -e "${BLUE}macOS without iCloud Drive - using dotfiles only${NC}"
        elif is_ubuntu; then
            echo -e "${BLUE}Ubuntu detected - using simple dotfiles sync${NC}"
        fi
    fi

    # Build the list of files to compare
    local files_to_check=("$home_file" "$repo_file")
    if $use_icloud; then
        files_to_check+=("$icloud_file")
    fi

    local newest_file
    newest_file=$(find_newest_file "${files_to_check[@]}")

    if [ -n "$newest_file" ]; then
        echo -e "${BLUE}Newest $display_name: $(basename "$(dirname "$newest_file")")/$(basename "$newest_file")${NC}"

        local files_updated=false

        # Update repo if needed
        if [ "$newest_file" != "$repo_file" ] && ! diff -q "$newest_file" "$repo_file" >/dev/null 2>&1; then
            echo -e "${YELLOW}Updating dotfiles from $(basename "$newest_file")${NC}"
            if check_permissions "$repo_file" && cp "$newest_file" "$repo_file" 2>/dev/null; then
                echo -e "${GREEN}Dotfiles updated${NC}"
                files_updated=true
                local source_label="home directory"
                if $use_icloud && [ "$newest_file" = "$icloud_file" ]; then
                    source_label="iCloud Drive"
                fi
                commit_dotfiles_changes "Update $display_name from $source_label" "$git_add_pattern"
            else
                echo -e "${RED}Failed to update dotfiles${NC}"
                log_message "ERROR" "Failed to copy $newest_file to $repo_file"
            fi
        fi

        # Update iCloud if needed
        if $use_icloud && [ "$newest_file" != "$icloud_file" ] && ! diff -q "$newest_file" "$icloud_file" >/dev/null 2>&1; then
            echo -e "${YELLOW}Updating iCloud from $(basename "$newest_file")${NC}"
            if check_permissions "$icloud_file" && cp "$newest_file" "$icloud_file" 2>/dev/null; then
                echo -e "${GREEN}iCloud updated${NC}"
                files_updated=true
            else
                echo -e "${RED}Failed to update iCloud${NC}"
                log_message "ERROR" "Failed to copy $newest_file to $icloud_file"
            fi
        fi

        # Update home if needed (only if it's a real file, not a symlink we're about to fix)
        if [ ! -L "$home_file" ] && [ "$newest_file" != "$home_file" ] && ! diff -q "$newest_file" "$home_file" >/dev/null 2>&1; then
            echo -e "${YELLOW}Updating home from $(basename "$newest_file")${NC}"
            backup_file "$home_file" || log_message "WARN" "Backup failed, continuing"
            if check_permissions "$home_file" && cp "$newest_file" "$home_file" 2>/dev/null; then
                echo -e "${GREEN}Home $display_name updated${NC}"
                files_updated=true
            else
                echo -e "${RED}Failed to update home $display_name${NC}"
                log_message "ERROR" "Failed to copy $newest_file to $home_file"
            fi
        fi

        if [ "$files_updated" = false ]; then
            echo -e "${GREEN}All versions are already in sync${NC}"
        fi
    else
        # No files exist at home — install from repo
        if [ -f "$repo_file" ]; then
            echo -e "${YELLOW}Installing $display_name from dotfiles${NC}"
            if check_permissions "$home_file" && cp "$repo_file" "$home_file" 2>/dev/null; then
                echo -e "${GREEN}Installed $display_name${NC}"
            else
                echo -e "${RED}Failed to install $display_name${NC}"
                return 1
            fi
        fi
    fi

    # Ensure home is a real file (migrate from symlink if needed)
    if [ -L "$home_file" ]; then
        echo -e "${YELLOW}Migrating: replacing symlink with local copy${NC}"
        local link_target
        link_target="$(readlink "$home_file")"
        rm -f "$home_file" 2>/dev/null || { echo -e "${RED}Failed to remove symlink${NC}"; return 1; }
        local src="$link_target"
        [ -f "$src" ] || src="$repo_file"
        if cp "$src" "$home_file" 2>/dev/null; then
            echo -e "${GREEN}~/$display_name is now a local copy${NC}"
        else
            echo -e "${RED}Migration failed — restoring symlink${NC}"
            ln -s "$link_target" "$home_file" 2>/dev/null
            return 1
        fi
    elif [ ! -f "$home_file" ]; then
        local best_source="$repo_file"
        if $use_icloud && [ -f "$icloud_file" ]; then
            best_source="$icloud_file"
        fi
        echo -e "${YELLOW}Installing ~/$display_name${NC}"
        cp "$best_source" "$home_file" 2>/dev/null || { echo -e "${RED}Install failed${NC}"; return 1; }
        echo -e "${GREEN}Installed${NC}"
    fi

    # Summary
    echo ""
    if $use_icloud; then
        echo -e "${BLUE}Setup: Home (local copy) ↔ iCloud ↔ Dotfiles${NC}"
    else
        echo -e "${BLUE}Setup: Dotfiles ↔ Home (bidirectional sync)${NC}"
    fi
}

###############################################################################
# Two-way sync primitives (no iCloud leg, no per-file commit)
###############################################################################
#
# sync_dotfile() above is the three-way model: home <-> iCloud <-> repo,
# committing each file as it goes. The helpers below are the simpler shape used
# by the app-config scripts (tmux, ghostty, zed): a straight repo <-> local
# comparison with no iCloud participation, leaving the caller to batch a single
# commit_dotfiles_changes at the end.

# Sync one file two ways between the repo and its installed location, keeping
# whichever side is newer. A file present on only one side is copied to the
# other, in whichever direction is needed — same semantics as sync_dir_2way.
# Returns 1 on copy failure so the caller can decide whether that is fatal.
sync_file_2way() {
    local src="$1"      # repo-side file
    local dst="$2"      # installed location
    local name="$3"     # display name

    # Neither side has it — nothing to do
    if [ ! -f "$src" ] && [ ! -f "$dst" ]; then
        echo -e "${YELLOW}Skipping $name (not found in dotfiles or locally)${NC}"
        return 0
    fi

    # Present on one side only — copy it across, in whichever direction
    if [ ! -f "$src" ]; then
        echo -e "${YELLOW}Pulling $name to dotfiles${NC}"
        if cp "$dst" "$src" 2>/dev/null; then
            echo -e "${GREEN}$name added to dotfiles${NC}"
        else
            echo -e "${RED}Failed to pull $name to dotfiles${NC}"
            return 1
        fi
    elif [ ! -f "$dst" ]; then
        if cp "$src" "$dst" 2>/dev/null; then
            echo -e "${GREEN}Installed $name${NC}"
        else
            echo -e "${RED}Failed to install $name${NC}"
            return 1
        fi
    elif ! diff -q "$src" "$dst" >/dev/null 2>&1; then
        local src_mtime dst_mtime
        src_mtime=$(get_file_mtime "$src")
        dst_mtime=$(get_file_mtime "$dst")

        if [ "$dst_mtime" -gt "$src_mtime" ]; then
            echo -e "${YELLOW}Local $name is newer — updating dotfiles${NC}"
            if cp "$dst" "$src" 2>/dev/null; then
                echo -e "${GREEN}Dotfiles updated for $name${NC}"
            else
                echo -e "${RED}Failed to update dotfiles for $name${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}Dotfiles $name is newer — updating local${NC}"
            if cp "$src" "$dst" 2>/dev/null; then
                echo -e "${GREEN}Local $name updated${NC}"
            else
                echo -e "${RED}Failed to update local $name${NC}"
                return 1
            fi
        fi
    else
        echo -e "${GREEN}$name is already in sync${NC}"
    fi
}

# Sync a whole directory two ways, file by file, keeping whichever side is
# newer. Files present on only one side are copied to the other. Used for the
# ghostty/zed theme directories.
#
# $3 is a singular display label ("theme"); $4 is its plural form, defaulting
# to $3 with an "s". Both are printed, not used as paths.
sync_dir_2way() {
    local repo_dir="$1"
    local local_dir="$2"
    local label="${3:-theme}"
    local label_plural="${4:-${3:-theme}s}"

    if [ ! -d "$repo_dir" ]; then
        echo -e "${YELLOW}No $label directory in dotfiles, skipping${NC}"
        return 0
    fi

    mkdir -p "$local_dir" 2>/dev/null

    local updated=false
    local f name counterpart a_mtime b_mtime

    # Repo -> local (install new, or refresh where the repo copy is newer)
    for f in "$repo_dir"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        counterpart="$local_dir/$name"

        if [ ! -f "$counterpart" ]; then
            cp "$f" "$counterpart" 2>/dev/null && \
                echo -e "${GREEN}Installed $label: $name${NC}" && updated=true
        elif ! diff -q "$f" "$counterpart" >/dev/null 2>&1; then
            a_mtime=$(get_file_mtime "$counterpart")
            b_mtime=$(get_file_mtime "$f")
            if [ "$b_mtime" -gt "$a_mtime" ]; then
                cp "$f" "$counterpart" 2>/dev/null && \
                    echo -e "${GREEN}Updated local $label: $name${NC}" && updated=true
            fi
        fi
    done

    # Local -> repo (pull back new or newer local files)
    for f in "$local_dir"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        counterpart="$repo_dir/$name"

        if [ ! -f "$counterpart" ]; then
            cp "$f" "$counterpart" 2>/dev/null && \
                echo -e "${GREEN}New local $label pulled to dotfiles: $name${NC}" && updated=true
        elif ! diff -q "$f" "$counterpart" >/dev/null 2>&1; then
            a_mtime=$(get_file_mtime "$f")
            b_mtime=$(get_file_mtime "$counterpart")
            if [ "$a_mtime" -gt "$b_mtime" ]; then
                cp "$f" "$counterpart" 2>/dev/null && \
                    echo -e "${GREEN}Updated dotfiles $label: $name${NC}" && updated=true
            fi
        fi
    done

    if [ "$updated" = false ]; then
        echo -e "${GREEN}${label_plural} are already in sync${NC}"
    fi
}
