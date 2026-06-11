#!/usr/bin/env bash
#
# system-update.sh — update the software boblbee installs, on THIS host
#
# macOS:  port selfupdate + port upgrade outdated; softwareupdate -i -r
#         (recommended updates only); claude update
# Ubuntu: apt-get update / upgrade / autoremove; claude update
#
# A restart is never forced. If an update needs one, the script prints a
# RESTART REQUIRED marker and stops there — unless -r is given, in which case
# it schedules a reboot 1 minute out (so the shell/SSH session closes cleanly).
#
# Usage:
#   ./system-update.sh            # update; report if a restart is needed
#   ./system-update.sh -r         # also reboot (in 1 min) if a restart is needed
#
# sudo: run locally it prompts (TouchID); run over the fleet via `ssh -A`,
# pam_ssh_agent_auth makes the same sudo calls passwordless.
#

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Source shared libraries
source "$SCRIPT_DIR/detect-os.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/lib.sh"

# Claude Code (native installer) and MacPorts live here; a non-login SSH shell
# may not have them on PATH.
export PATH="$HOME/.local/bin:/opt/local/bin:/opt/local/sbin:$PATH"

REBOOT=0
case "${1:-}" in
    -r|--reboot) REBOOT=1 ;;
    "")          ;;
    *)           echo "Usage: $(basename "$0") [-r|--reboot]"; exit 1 ;;
esac

RESTART_NEEDED=0
FAILED=0

update_claude() {
    if command -v claude >/dev/null 2>&1; then
        log_info "Claude Code: checking for updates..."
        if claude update; then
            log_success "Claude Code up to date"
        else
            log_warn "claude update failed (non-fatal)"
        fi
    else
        log_warn "claude not on PATH — skipping Claude Code update"
    fi
}

update_macos() {
    # MacPorts
    if [[ -x /opt/local/bin/port ]]; then
        log_info "MacPorts: selfupdate..."
        sudo /opt/local/bin/port -N selfupdate || { log_warn "port selfupdate failed"; FAILED=1; }

        log_info "MacPorts: upgrading outdated ports..."
        # `port upgrade outdated` exits non-zero when nothing is outdated —
        # treat that specific case as success.
        if run_with_progress "port upgrade" sudo /opt/local/bin/port -N upgrade outdated; then
            log_success "MacPorts ports up to date"
        elif grep -qi "nothing to upgrade" "$RWP_LOG" 2>/dev/null; then
            log_success "MacPorts ports up to date"
        else
            log_warn "port upgrade reported errors"
            if [[ -f "$RWP_LOG" ]]; then
                echo "  --- last 40 lines of port log ---"
                tail -n 40 "$RWP_LOG"
            fi
            FAILED=1
        fi
        rm -f "$RWP_LOG"
    else
        log_warn "MacPorts not installed — skipping ports"
    fi

    # macOS software updates — recommended only, never auto-reboot here.
    log_info "macOS: installing recommended software updates..."
    run_with_progress "softwareupdate" sudo softwareupdate -i -r
    if grep -qi "restart" "$RWP_LOG" 2>/dev/null; then
        RESTART_NEEDED=1
    fi
    rm -f "$RWP_LOG"

    update_claude
}

update_ubuntu() {
    log_info "apt: update..."
    sudo apt-get update || { log_warn "apt update failed"; FAILED=1; }

    log_info "apt: upgrade..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade || { log_warn "apt upgrade failed"; FAILED=1; }

    log_info "apt: autoremove..."
    sudo apt-get -y autoremove || log_warn "apt autoremove failed (non-fatal)"

    [[ -f /var/run/reboot-required ]] && RESTART_NEEDED=1

    update_claude
}

if is_macos; then
    update_macos
elif is_ubuntu; then
    update_ubuntu
else
    log_error "Unsupported platform"
    exit 1
fi

echo ""
if [[ $RESTART_NEEDED -eq 1 ]]; then
    if [[ $REBOOT -eq 1 ]]; then
        log_warn "RESTART REQUIRED — scheduling reboot in 1 minute (-r given)"
        # Detached + delayed so this script exits 0 and the SSH session closes
        # cleanly before the machine actually goes down.
        ( sudo shutdown -r +1 >/dev/null 2>&1 & ) || log_warn "failed to schedule reboot"
    else
        log_warn "RESTART REQUIRED — reboot to finish (re-run with -r to auto-reboot)"
    fi
fi

if [[ $FAILED -eq 0 ]]; then
    log_success "system-update complete"
else
    log_warn "system-update completed with some failures"
fi
exit $FAILED
