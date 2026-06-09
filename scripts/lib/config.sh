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
# ark-config — private config repo, sibling of boblbee (all platforms)
###############################################################################
#
# Source of truth for secrets/configs that can't live in the public boblbee
# repo. On hosts without iCloud Drive, this is the non-iCloud fallback that
# delivers the SSH config + keys (see ssh-sync.sh / script/bootstrap).
#
# Layout:  ark-config/boblbee/{ssh_config,id_ed25519,id_rsa,id_github,...}

# Canonical repo path (sibling of boblbee)
ARK_CONFIG_PATH="$(dirname "$BOBLBEE_CANONICAL_PATH")/ark-config"
ARK_BOBLBEE_DIR="$ARK_CONFIG_PATH/boblbee"

# Bootstrap key: a single passphrase-less ed25519 key, seeded once per host from a
# vault. It is BOTH the read-only GitHub deploy key for ark-config (so a host can
# clone the private repo) and the age identity that decrypts the *.age secrets in
# ark-config/boblbee/. Override the path with BOBLBEE_BOOTSTRAP_KEY if needed.
BOOTSTRAP_KEY="${BOBLBEE_BOOTSTRAP_KEY:-$HOME/.config/boblbee/id_bootstrap}"

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
