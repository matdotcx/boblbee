#!/usr/bin/env bash

#########################################################
# Title: claude-sync
# Description: Install Claude hooks + Manganese themes; bidirectional sync of memory + user settings (copy strategy)
# Source: https://github.com/matdotcx/boblbee
#
# ~/.config/claude/memory/user.md and ~/.claude/settings.json are real local
# files (not symlinks). Newest-mtime-wins between local and repo, then
# auto-commits to git.
#########################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

REPO_MEMORY="$DOTFILES_DIR/claude/memory/user.md"
LOCAL_MEMORY="$HOME/.config/claude/memory/user.md"

# Claude user-scope settings (global default; per-project .claude/settings*.json
# sit above this in precedence and are never touched here).
REPO_SETTINGS="$DOTFILES_DIR/assets/claude-settings.json"
LOCAL_SETTINGS="$HOME/.claude/settings.json"

# Hook scripts referenced by claude-settings.json. One-way (repo -> home): they
# are code, so the repo is the source of truth and local edits are overwritten.
REPO_HOOKS="$DOTFILES_DIR/assets/claude-hooks"
LOCAL_HOOKS="$HOME/.claude/hooks"

echo "=== Claude Hooks Install ==="
echo ""

# Install hooks before settings so the settings never reference a missing hook.
mkdir -p "$LOCAL_HOOKS"
for hook in "$REPO_HOOKS"/*; do
    [ -f "$hook" ] || continue
    name="$(basename "$hook")"
    if cmp -s "$hook" "$LOCAL_HOOKS/$name"; then
        echo -e "${GREEN}✓ $name already up to date${NC}"
        continue
    fi
    cp "$hook" "$LOCAL_HOOKS/$name"
    chmod +x "$LOCAL_HOOKS/$name"
    echo -e "${GREEN}✓ Installed $name${NC}"
done

echo ""
echo "=== Claude Settings Sync ==="
echo ""

# Sync ~/.claude/settings.json first, unconditionally — the memory sync below
# has early-exit branches, so settings would be skipped if it ran afterwards.
# Newest-mtime-wins (2-way repo <-> home), matching the memory strategy.
mkdir -p "$(dirname "$LOCAL_SETTINGS")"
sync_dotfile "claude-settings.json" "$LOCAL_SETTINGS" "$REPO_SETTINGS" "" "assets/claude-settings.json"

echo ""
echo "=== Claude Themes (Manganese) ==="
echo ""

# The Manganese themes live in their own repo (the source of truth), so fetch
# them from its gold branch rather than vendoring copies here. Runs before the
# memory sync, which has early-exit branches. Fetch failures warn and move on —
# themes are cosmetic, setup shouldn't abort offline.
MANGANESE_RAW="https://raw.githubusercontent.com/matdotcx/manganese/gold/claude-code"
LOCAL_THEMES="$HOME/.claude/themes"
mkdir -p "$LOCAL_THEMES"
for theme in manganese-light.json manganese-dark.json; do
    tmp="$(mktemp)"
    if curl -fsSL --max-time 15 "$MANGANESE_RAW/$theme" -o "$tmp" && head -c1 "$tmp" | grep -q '{'; then
        if cmp -s "$tmp" "$LOCAL_THEMES/$theme"; then
            echo -e "${GREEN}✓ $theme already up to date${NC}"
        else
            mv "$tmp" "$LOCAL_THEMES/$theme"
            echo -e "${GREEN}✓ Installed $theme${NC}"
        fi
    else
        echo -e "${YELLOW}Could not fetch $theme from manganese — skipping${NC}"
    fi
    rm -f "$tmp"
done

echo ""
echo "=== Claude Memory Sync ==="
echo ""

# Ensure local directory exists
mkdir -p "$(dirname "$LOCAL_MEMORY")"

# Migrate symlink to copy if still present
if [ -L "$LOCAL_MEMORY" ]; then
    echo -e "${YELLOW}Migrating: replacing symlink with local copy${NC}"
    link_target="$(readlink "$LOCAL_MEMORY")"
    rm -f "$LOCAL_MEMORY"
    src="$link_target"
    [ -f "$src" ] || src="$REPO_MEMORY"
    if [ -f "$src" ]; then
        cp "$src" "$LOCAL_MEMORY"
        echo -e "${GREEN}✓ Migrated to local copy${NC}"
    fi
fi

# Check we have at least one source
if [ ! -f "$REPO_MEMORY" ] && [ ! -f "$LOCAL_MEMORY" ]; then
    echo "No Claude memory file found in repo or locally"
    exit 0
fi

# If only one exists, copy to the other
if [ ! -f "$LOCAL_MEMORY" ] && [ -f "$REPO_MEMORY" ]; then
    cp "$REPO_MEMORY" "$LOCAL_MEMORY"
    echo -e "${GREEN}Installed Claude memory from dotfiles${NC}"
    exit 0
fi
if [ ! -f "$REPO_MEMORY" ] && [ -f "$LOCAL_MEMORY" ]; then
    cp "$LOCAL_MEMORY" "$REPO_MEMORY"
    echo -e "${GREEN}Copied local Claude memory to dotfiles${NC}"
    commit_dotfiles_changes "Update Claude memory from local" "claude/memory/user.md"
    exit 0
fi

# Both exist — compare
if diff -q "$LOCAL_MEMORY" "$REPO_MEMORY" >/dev/null 2>&1; then
    echo -e "${GREEN}Claude memory already in sync${NC}"
    exit 0
fi

# Newest wins
local_mtime=$(get_file_mtime "$LOCAL_MEMORY")
repo_mtime=$(get_file_mtime "$REPO_MEMORY")

if [ "$local_mtime" -gt "$repo_mtime" ]; then
    echo -e "${YELLOW}Local memory is newer — updating dotfiles${NC}"
    cp "$LOCAL_MEMORY" "$REPO_MEMORY"
    echo -e "${GREEN}Dotfiles updated${NC}"
    commit_dotfiles_changes "Update Claude memory from local" "claude/memory/user.md"
elif [ "$repo_mtime" -gt "$local_mtime" ]; then
    echo -e "${YELLOW}Dotfiles memory is newer — updating local${NC}"
    cp "$REPO_MEMORY" "$LOCAL_MEMORY"
    echo -e "${GREEN}Local Claude memory updated${NC}"
else
    echo -e "${GREEN}Claude memory already in sync${NC}"
fi

echo ""
echo -e "${GREEN}Claude memory sync complete${NC}"
