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
# iCloud layout (macOS only)
###############################################################################

if [[ "$OSTYPE" == "darwin"* ]]; then
    ICLOUD_BASE="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    ICLOUD_SYNC_DIR="Ark/Sync/System"
    ICLOUD_SYNC_PATH="$ICLOUD_BASE/$ICLOUD_SYNC_DIR"
fi

###############################################################################
# Observability / monitoring — derived from DNS, not hardcoded
###############################################################################

# Discover this host's domain, then derive helium's address.
_detect_domain() {
    # 1. hostname -d (works when domain is set via DHCP/DNS)
    local d
    d=$(hostname -d 2>/dev/null) && [[ -n "$d" && "$d" != "(none)" ]] && echo "$d" && return

    # 2. hostname -f minus the short name
    local fqdn
    fqdn=$(hostname -f 2>/dev/null)
    if [[ "$fqdn" == *.* ]]; then
        echo "${fqdn#*.}"
        return
    fi

    # 3. Tailscale FQDN (e.g. host.tail-net.ts.net → not useful, but the
    #    search domain set by Split DNS often lands in resolv.conf)
    d=$(grep '^search ' /etc/resolv.conf 2>/dev/null | awk '{print $2}')
    [[ -n "$d" ]] && echo "$d" && return

    # Give up — caller gets empty string
    return 1
}

_DOMAIN=$(_detect_domain)

HELIUM_FQDN="helium.${_DOMAIN:-int.iaconelli.org}"
HELIUM_IP=$(dig +short "$HELIUM_FQDN" 2>/dev/null | head -1)
HELIUM_REGISTER_SCRIPT="~/observability/scripts/register-host.sh"

unset _DOMAIN

###############################################################################
# Prometheus textfile collector
###############################################################################

PROMETHEUS_TEXTFILE_DIR="$HOME/.local/share/prometheus/textfile"

###############################################################################
# Versions
###############################################################################

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
