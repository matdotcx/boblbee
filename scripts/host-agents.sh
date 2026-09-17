#!/bin/bash
# host-agents.sh — install (or check) the scheduled jobs assigned to this host.
#
# Profiles live in hosts/agents/<profile>/ (bin/, launchd/, install.sh). Which host gets which
# profile is decided by hosts/agent-assignments.txt, never by anything hard-coded here:
#
#   aluminium  aluminium            # host aluminium gets the "aluminium" profile
#   radon      radon vault-mirror   # a host may take several profiles
#
# Usage:
#   ./host-agents.sh                 install/refresh the profiles assigned to $(hostname -s)
#   ./host-agents.sh --check         report drift and unloaded agents, change nothing (exit 1 if any)
#   ./host-agents.sh --host NAME     resolve assignments as if this machine were NAME
#   ./host-agents.sh --profile NAME  run this profile regardless of assignments (repeatable)
#   ./host-agents.sh --list          show hosts, profiles and what this host would get
#
# Called by index.sh (fresh install) and self-update.sh (nightly, install mode). Idempotent: each
# profile's install.sh only copies what differs and only reloads an agent whose plist changed or
# which is not loaded.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/lib.sh
[ -f "$SCRIPT_DIR/lib/lib.sh" ] && source "$SCRIPT_DIR/lib/lib.sh" || {
    log_info()    { echo "[INFO] $*"; }; log_success() { echo "[OK] $*"; }
    log_warn()    { echo "[WARN] $*"; }; log_error()   { echo "[ERROR] $*"; }
}
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSIGN="$REPO_DIR/hosts/agent-assignments.txt"
PROFILES_DIR="$REPO_DIR/hosts/agents"

CHECK=0; LIST=0; HOST="$(hostname -s 2>/dev/null || hostname)"; PROFILES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   CHECK=1; shift ;;
        --list)    LIST=1; shift ;;
        --host)    HOST="${2:-}"; shift 2 ;;
        --profile) PROFILES+=("${2:-}"); shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) log_error "unknown argument: $1"; exit 1 ;;
    esac
done

resolve_profiles() {
    [ -f "$ASSIGN" ] || return 0
    awk -v h="$HOST" '$0 !~ /^[[:space:]]*(#|$)/ && $1 == h { for (i = 2; i <= NF; i++) print $i }' "$ASSIGN"
}

if [ $LIST = 1 ]; then
    echo "profiles available: $(ls "$PROFILES_DIR" 2>/dev/null | tr '\n' ' ')"
    echo "assignments ($ASSIGN):"; grep -v -E '^[[:space:]]*(#|$)' "$ASSIGN" 2>/dev/null | sed 's/^/  /'
    echo "this host ($HOST) would get: $(resolve_profiles | tr '\n' ' ')"
    exit 0
fi

if [ ${#PROFILES[@]} -eq 0 ]; then
    while IFS= read -r p; do [ -n "$p" ] && PROFILES+=("$p"); done < <(resolve_profiles)
fi
if [ ${#PROFILES[@]} -eq 0 ]; then
    log_info "host-agents: no agent profiles assigned to $HOST (see hosts/agent-assignments.txt)"
    exit 0
fi

rc=0
for p in "${PROFILES[@]}"; do
    inst="$PROFILES_DIR/$p/install.sh"
    if [ ! -x "$inst" ]; then log_error "host-agents: profile '$p' has no executable install.sh"; rc=1; continue; fi
    if [ $CHECK = 1 ]; then
        log_info "host-agents: checking profile '$p' for $HOST"
        if "$inst" --check; then log_success "profile '$p': in sync"; else log_warn "profile '$p': drift or unloaded agents (see above)"; rc=1; fi
    else
        log_info "host-agents: installing profile '$p' for $HOST"
        if "$inst"; then log_success "profile '$p': installed"; else log_error "profile '$p': install reported problems"; rc=1; fi
    fi
done
exit $rc
