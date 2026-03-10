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
HOSTS_FILE="${HOSTS_FILE:-$BOBLBEE_DIR/hosts/elements.txt}"
SSH_OPTS="${SSH_OPTS:--A -o BatchMode=yes -o ConnectTimeout=5}"
PARALLEL="${PARALLEL:-0}"
DRY_RUN="${DRY_RUN:-0}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# HTTPS remote (public repo — avoids dependency on agent forwarding for pull)
REPO_HTTPS="https://github.com/matdotcx/boblbee.git"
BRANCH=$(git -C "$BOBLBEE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "gold")

# Hosts: from args or from file
if [[ $# -gt 0 ]]; then
    HOSTS=("$@")
else
    mapfile -t HOSTS < <(grep -v '^\s*#' "$HOSTS_FILE" | grep -v '^\s*$')
fi

# Remote payload — self-contained so we only need one SSH
REMOTE_CMD=$(cat <<EOF
set -e
for d in "\$HOME/Developer/workspace/matdotcx/boblbee" \\
         "\$HOME/Developer/matdotcx/boblbee" \\
         "\$HOME/workspace/matdotcx/boblbee" \\
         "/workspace/matdotcx/boblbee"; do
    [[ -d "\$d/.git" ]] && REPO="\$d" && break
done
[[ -z "\$REPO" ]] && { echo "FAIL: boblbee repo not found"; exit 1; }

cd "\$REPO"
# Fetch over HTTPS then merge — avoids agent-forwarding dependency
git fetch -q "$REPO_HTTPS" "$BRANCH"
git merge -q --ff-only FETCH_HEAD || { echo "FAIL: merge failed (local changes?)"; exit 1; }

./scripts/zshrc-sync.sh  > /dev/null 2>&1 || echo "WARN: zshrc-sync failed"
./scripts/ssh-sync.sh    > /dev/null 2>&1 || echo "WARN: ssh-sync failed"
./scripts/tmux-sync.sh   > /dev/null 2>&1 || echo "WARN: tmux-sync failed"

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
