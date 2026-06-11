#!/usr/bin/env bash
#
# update-fleet.sh — pull boblbee and run system-update on every host
#
# Updates the software boblbee installs (MacPorts ports + recommended macOS
# updates / apt packages, plus Claude Code) across the fleet.
#
# Unlike sync-fleet.sh, this connects with `ssh -A` so remote `sudo`
# authenticates via your forwarded SSH agent (pam_ssh_agent_auth). Make sure
# your key is loaded (`ssh-add -l`) before running.
#
# Usage:
#   ./update-fleet.sh                # uses hosts/elements.txt
#   ./update-fleet.sh host1 host2    # explicit hosts
#   ./update-fleet.sh -r             # reboot hosts that need it, after updating
#   PARALLEL=1 ./update-fleet.sh     # all hosts at once
#   DRY_RUN=1  ./update-fleet.sh     # print what would run, execute nothing
#
# Env:
#   HOSTS_FILE=path/to/hosts.txt
#   SSH_OPTS=...      override ssh options (default: -A, BatchMode, timeouts)
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
# -A forwards the SSH agent so remote sudo (pam_ssh_agent_auth) is passwordless.
# ServerAliveInterval keeps long-running updates from dropping the connection.
SSH_OPTS="${SSH_OPTS:--A -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=30}"
PARALLEL="${PARALLEL:-0}"
DRY_RUN="${DRY_RUN:-0}"

BRANCH=$(get_default_branch)

# Args: an optional -r/--reboot flag, plus any explicit hosts.
REBOOT_FLAG=""
HOSTS=()
for arg in "$@"; do
    case "$arg" in
        -r|--reboot) REBOOT_FLAG="-r" ;;
        *)           HOSTS+=("$arg") ;;
    esac
done

# Fall back to the host file when no hosts were given on the command line.
if [[ ${#HOSTS[@]} -eq 0 ]]; then
    while IFS= read -r line; do HOSTS+=("$line"); done < <(grep -v '^\s*#' "$HOSTS_FILE" | grep -v '^\s*$')
fi

# Remote payload — self-contained so we only need one SSH.
# Pulls the repo first (so the newest system-update.sh runs), then updates.
REMOTE_CMD=$(cat <<EOF
set -e
REPO="\$HOME/Developer/workspace/matdotcx/boblbee"
[[ -d "\$REPO/.git" ]] || { echo "FAIL: boblbee repo not found at \$REPO"; exit 1; }

cd "\$REPO"
# Fetch over HTTPS then ff-merge — same agent-free pull as sync-fleet.
GIT_CONFIG_GLOBAL=/dev/null git fetch -q "$REPO_HTTPS" "$BRANCH" || echo "WARN: git fetch failed, using current checkout"
git merge -q --ff-only FETCH_HEAD 2>/dev/null || echo "WARN: merge skipped (local changes or fetch failed)"

./scripts/system-update.sh $REBOOT_FLAG
EOF
)

# Run the update on one host, streaming its output (indented) and teeing a
# clean copy to <logfile> for RESTART-REQUIRED detection. Returns ssh's exit.
update_host() {
    local h="$1" logfile="$2"
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}   $h${NC}"
    echo -e "${BLUE}================================================================${NC}"

    if [[ "$DRY_RUN" == "1" ]]; then
        echo -e "${BLUE}[DRY]${NC} would ssh -A $h → git fetch+merge $BRANCH, run system-update.sh $REBOOT_FLAG"
        : > "$logfile"
        return 0
    fi

    ssh $SSH_OPTS "$h" bash -s <<< "$REMOTE_CMD" 2>&1 | tee "$logfile" | sed 's/^/  /'
    local rc=${PIPESTATUS[0]}
    if [[ $rc -eq 0 ]]; then
        log_success "$h: update complete"
    else
        log_error "$h: update failed (exit $rc)"
    fi
    return $rc
}

echo -e "${BLUE}Updating ${#HOSTS[@]} host(s) on branch '$BRANCH'${NC}"
[[ "$DRY_RUN" == "1" ]] && log_warn "DRY RUN — nothing will be executed"
[[ -n "$REBOOT_FLAG" ]] && log_warn "Reboot enabled — hosts needing a restart will reboot (in 1 min) after updating"

failed=0
RESTART_HOSTS=()

if [[ "$PARALLEL" == "1" ]]; then
    tmp_dir=$(mktemp -d)
    pids=()
    for h in "${HOSTS[@]}"; do
        ( update_host "$h" "$tmp_dir/$h.log" > "$tmp_dir/$h.out" 2>&1; echo $? > "$tmp_dir/$h.status" ) &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do wait "$pid" || true; done
    for h in "${HOSTS[@]}"; do
        cat "$tmp_dir/$h.out"
        [[ "$(cat "$tmp_dir/$h.status" 2>/dev/null)" != "0" ]] && failed=1
        grep -qi "RESTART REQUIRED" "$tmp_dir/$h.log" 2>/dev/null && RESTART_HOSTS+=("$h")
    done
    rm -rf "$tmp_dir"
else
    for h in "${HOSTS[@]}"; do
        logfile=$(mktemp)
        update_host "$h" "$logfile" || failed=1
        grep -qi "RESTART REQUIRED" "$logfile" 2>/dev/null && RESTART_HOSTS+=("$h")
        rm -f "$logfile"
    done
fi

echo ""
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}   Summary${NC}"
echo -e "${BLUE}================================================================${NC}"
if [[ ${#RESTART_HOSTS[@]} -gt 0 ]]; then
    if [[ -n "$REBOOT_FLAG" ]]; then
        log_warn "Restart needed — rebooting: ${RESTART_HOSTS[*]}"
    else
        log_warn "Restart required (not rebooted): ${RESTART_HOSTS[*]}"
        echo "  Re-run with -r to reboot these automatically."
    fi
fi
if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}All ${#HOSTS[@]} host(s) updated.${NC}"
else
    echo -e "${RED}Some hosts failed — see above.${NC}"
fi
exit $failed
