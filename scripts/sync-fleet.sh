#!/usr/bin/env bash
#
# sync-fleet.sh — pull boblbee and run bb-sync on every host
#
# Fetches over HTTPS (public repo) so agent forwarding isn't required
# for the pull; bb-sync scripts run entirely locally on each host.
#
# Usage:
#   ./sync-fleet.sh                  # uses hosts/elements.txt
#   ./sync-fleet.sh host1 host2      # explicit hosts
#   PARALLEL=1 ./sync-fleet.sh       # all hosts at once
#
# Env:
#   HOSTS_FILE=path/to/hosts.txt
#   PARALLEL=1        run all hosts concurrently
#   DRY_RUN=1         print what would run without executing
#

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOBLBEE_DIR="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

HOSTS_FILE="${HOSTS_FILE:-$BOBLBEE_DIR/hosts/elements.txt}"
SSH_OPTS="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=5}"
PARALLEL="${PARALLEL:-0}"
DRY_RUN="${DRY_RUN:-0}"

BRANCH=$(get_default_branch)

# Hosts: from args or from file
if [[ $# -gt 0 ]]; then
    HOSTS=("$@")
else
    HOSTS=()
    while IFS= read -r line; do HOSTS+=("$line"); done < <(grep -v '^\s*#' "$HOSTS_FILE" | grep -v '^\s*$')
fi

# Remote payload — self-contained so we only need one SSH
# Uses single canonical path per user's decision
REMOTE_CMD=$(cat <<EOF
set -e
REPO="\$HOME/Developer/workspace/matdotcx/boblbee"
[[ -d "\$REPO/.git" ]] || { echo "FAIL: boblbee repo not found at \$REPO"; exit 1; }

cd "\$REPO"
# Fetch over HTTPS then merge — avoids agent-forwarding dependency.
# GIT_CONFIG_GLOBAL=/dev/null neutralises any host's url.*.insteadOf rewrite
# (e.g. https://github.com/ -> git@github.com:) that would otherwise force the
# anonymous HTTPS pull onto SSH and fail without a GitHub key.
GIT_CONFIG_GLOBAL=/dev/null git fetch -q "$REPO_HTTPS" "$BRANCH"
git merge -q --ff-only FETCH_HEAD || { echo "FAIL: merge failed (local changes?)"; exit 1; }

./scripts/claude-sync.sh > /dev/null 2>&1 || echo "WARN: claude-sync failed"
./scripts/zshrc-sync.sh  > /dev/null 2>&1 || echo "WARN: zshrc-sync failed"
./scripts/ssh-sync.sh    > /dev/null 2>&1 || echo "WARN: ssh-sync failed"
./scripts/tmux-sync.sh   > /dev/null 2>&1 || echo "WARN: tmux-sync failed"
./scripts/motd-sync.sh   > /dev/null 2>&1 || echo "WARN: motd-sync failed"

echo "OK: \$(git rev-parse --short HEAD)"
EOF
)

sync_host() {
    local h="$1"
    if [[ "$DRY_RUN" == "1" ]]; then
        printf "${BLUE}[DRY]${NC} %-10s would: git fetch+merge %s, run sync scripts\n" "$h" "$BRANCH"
        return 0
    fi

    local out rc
    out=$(ssh $SSH_OPTS "$h" bash -s <<< "$REMOTE_CMD" 2>&1)
    rc=$?

    if [[ $rc -eq 0 ]] && [[ "$out" == OK:* ]]; then
        printf "${GREEN}[OK]${NC}   %-10s %s\n" "$h" "$out"
    elif [[ $rc -eq 0 ]]; then
        printf "${YELLOW}[WARN]${NC} %-10s %s\n" "$h" "$out"
    else
        printf "${RED}[FAIL]${NC} %-10s %s\n" "$h" "$(echo "$out" | tail -1)"
        return 1
    fi
}

echo -e "${BLUE}Syncing ${#HOSTS[@]} host(s) to branch '$BRANCH'${NC}"
echo ""

failed=0
if [[ "$PARALLEL" == "1" ]]; then
    pids=()
    for h in "${HOSTS[@]}"; do
        sync_host "$h" &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do
        wait "$pid" || failed=1
    done
else
    for h in "${HOSTS[@]}"; do
        sync_host "$h" || failed=1
    done
fi

echo ""
if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}All hosts synced.${NC}"
else
    echo -e "${RED}Some hosts failed — see above.${NC}"
fi
exit $failed
