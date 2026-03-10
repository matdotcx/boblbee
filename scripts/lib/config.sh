#!/usr/bin/env bash
#
# config.sh — shared configuration for boblbee scripts
#
# Source this file from any script that needs shared values.
# All scripts should source detect-os.sh first, then this file.

###############################################################################
# Repo layout
###############################################################################

# Canonical repo path (the ONLY supported location)
BOBLBEE_CANONICAL_PATH="$HOME/Developer/workspace/matdotcx/boblbee"

###############################################################################
# iCloud layout (macOS)
###############################################################################

ICLOUD_BASE="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
ICLOUD_SYNC_DIR="Ark/Sync/System"
ICLOUD_SYNC_PATH="$ICLOUD_BASE/$ICLOUD_SYNC_DIR"

###############################################################################
# Observability / monitoring
###############################################################################

HELIUM_FQDN="helium.gl52.iaconelli.org"
HELIUM_IP="10.52.1.26"
HELIUM_REGISTER_SCRIPT="~/observability/scripts/register-host.sh"

NODE_EXPORTER_VERSION="1.10.2"

###############################################################################
# Fleet
###############################################################################

# HTTPS remote (public repo — avoids agent-forwarding dependency for pull)
REPO_HTTPS="https://github.com/matdotcx/boblbee.git"

###############################################################################
# Helpers
###############################################################################

# Detect the default branch from the remote (cached per script run).
# Queries origin's HEAD ref so the result is stable regardless of local checkout.
get_default_branch() {
    if [[ -z "${_BOBLBEE_DEFAULT_BRANCH:-}" ]]; then
        local repo_dir="${DOTFILES_DIR:-$BOBLBEE_CANONICAL_PATH}"
        # Try the remote HEAD symref first (e.g. "refs/remotes/origin/HEAD -> origin/gold")
        _BOBLBEE_DEFAULT_BRANCH=$(
            git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
                | sed 's|refs/remotes/origin/||'
        )
        # Fallback: if origin/HEAD isn't set, use the local branch
        if [[ -z "$_BOBLBEE_DEFAULT_BRANCH" ]]; then
            _BOBLBEE_DEFAULT_BRANCH=$(
                git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "gold"
            )
        fi
    fi
    echo "$_BOBLBEE_DEFAULT_BRANCH"
}
