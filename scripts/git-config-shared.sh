#!/usr/bin/env bash

#########################################################
# Title: git-config-shared
# Description: Cross-platform git config that applies on every boblbee host.
# Purpose: Universal settings (HTTPS->SSH rewrite for GitHub, sane defaults,
#          aliases) that should be identical on macOS and Ubuntu so the
#          fleet behaves the same way regardless of which box you're on.
# Usage: ./git-config-shared.sh
# Source: https://github.com/matdotcx/boblbee
#########################################################
#
# Identity (user.name / user.email), signing keys, and SSH key material are
# handled elsewhere — see configure_git_identity in index.sh, the
# ubuntu-git-setup.sh and setup-gpg-signing.sh scripts. This script is
# intentionally identity-free so it can run unattended on every sync.
#
# Every command here is idempotent: re-running on a host that already has the
# value set is a no-op, and overwriting a stale value is the desired behavior.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/lib.sh
[ -f "$SCRIPT_DIR/lib/lib.sh" ] && source "$SCRIPT_DIR/lib/lib.sh" || {
    log_info()    { echo "[info]    $*"; }
    log_success() { echo "[ok]      $*"; }
    log_warn()    { echo "[warn]    $*"; }
}

log_info "Applying shared git config..."

# ---------------------------------------------------------------------------
# Transport: prefer SSH over HTTPS for GitHub
# ---------------------------------------------------------------------------
# Forces every git operation against github.com to use the SSH transport even
# when the configured remote URL is https://. Means sync scripts don't have
# to per-repo `git remote set-url`, and new clones picked up over HTTPS still
# benefit from the user's SSH agent + key.
git config --global url."git@github.com:".insteadOf "https://github.com/"
log_success "url.git@github.com:.insteadof -> https://github.com/"

# ---------------------------------------------------------------------------
# Core defaults
# ---------------------------------------------------------------------------
git config --global init.defaultBranch main
git config --global core.autocrlf input
git config --global core.safecrlf true
git config --global pull.rebase false
git config --global push.default simple

# Editor: vim if available, else leave alone
if command -v vim >/dev/null 2>&1; then
    git config --global core.editor vim
fi

log_success "Core defaults applied (init/autocrlf/pull/push/editor)"

# ---------------------------------------------------------------------------
# Aliases — match the long-standing macOS workflow
# ---------------------------------------------------------------------------
git config --global alias.st       'status'
git config --global alias.co       'checkout'
git config --global alias.br       'branch'
git config --global alias.ci       'commit'
git config --global alias.unstage  'reset HEAD --'
git config --global alias.last     'log -1 HEAD'
git config --global alias.visual   '!gitk'

log_success "Aliases applied (st/co/br/ci/unstage/last/visual)"

log_info "Shared git config complete. Verify with: git config --global --list"
