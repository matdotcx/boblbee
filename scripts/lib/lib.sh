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
# File helpers
###############################################################################

# Get file modification time as epoch seconds.
# Follows symlinks, returns "0" if file does not exist.
get_file_mtime() {
    local file="$1"
    if [ -L "$file" ]; then
        file="$(readlink "$file")"
    fi
    if [ -f "$file" ]; then
        if is_macos; then
            stat -f %m "$file" 2>/dev/null || echo "0"
        else
            stat -c %Y "$file" 2>/dev/null || echo "0"
        fi
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

# Commit changes in DOTFILES_DIR.
# Usage: commit_dotfiles_changes "commit message" file1 [file2 ...]
# Files are relative to DOTFILES_DIR (e.g. "assets/.zshrc").
commit_dotfiles_changes() {
    local commit_msg="$1"
    shift
    local files=("$@")

    cd "$DOTFILES_DIR" || return 1

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if git add "${files[@]}" 2>/dev/null; then
            if git diff --staged --quiet; then
                echo -e "${BLUE}No changes to commit${NC}"
                return 0
            else
                if git commit -m "$commit_msg" 2>/dev/null; then
                    echo -e "${GREEN}Changes committed to git: $commit_msg${NC}"
                    return 0
                else
                    echo -e "${YELLOW}Git commit failed, but file was updated${NC}"
                    return 1
                fi
            fi
        else
            echo -e "${YELLOW}Git add failed, but file was updated${NC}"
            return 1
        fi
    else
        echo -e "${BLUE}Not in a git repository, skipping commit${NC}"
        return 0
    fi
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
        exit 1
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
                exit 1
            fi
        fi
    fi

    # Ensure home is a real file (migrate from symlink if needed)
    if [ -L "$home_file" ]; then
        echo -e "${YELLOW}Migrating: replacing symlink with local copy${NC}"
        local link_target
        link_target="$(readlink "$home_file")"
        rm -f "$home_file" 2>/dev/null || { echo -e "${RED}Failed to remove symlink${NC}"; exit 1; }
        local src="$link_target"
        [ -f "$src" ] || src="$repo_file"
        if cp "$src" "$home_file" 2>/dev/null; then
            echo -e "${GREEN}~/$display_name is now a local copy${NC}"
        else
            echo -e "${RED}Migration failed — restoring symlink${NC}"
            ln -s "$link_target" "$home_file" 2>/dev/null
            exit 1
        fi
    elif [ ! -f "$home_file" ]; then
        local best_source="$repo_file"
        if $use_icloud && [ -f "$icloud_file" ]; then
            best_source="$icloud_file"
        fi
        echo -e "${YELLOW}Installing ~/$display_name${NC}"
        cp "$best_source" "$home_file" 2>/dev/null || { echo -e "${RED}Install failed${NC}"; exit 1; }
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
