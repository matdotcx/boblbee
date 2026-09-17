#!/usr/bin/env bash

#########################################################
# Title: self-update
# Description: Pull boblbee repo and run sync scripts on a schedule
# Source: https://github.com/matdotcx/boblbee
#
# Wrapped in main() so bash parses the entire script before
# execution — git pull replaces this file on disk.
#
# Usage:
#   ./self-update.sh              # run update now
#   ./self-update.sh --install    # install daily schedule (00:48)
#   ./self-update.sh --uninstall  # remove schedule
#########################################################

main() {
    # Ensure PATH covers MacPorts and system tools for launchd/cron context
    export PATH="$HOME/bin:/opt/local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

    if [ -n "${BASH_SOURCE[0]}" ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    else
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    fi
    BOBLBEE_DIR="$(dirname "$SCRIPT_DIR")"

    # Source shared libraries
    source "$SCRIPT_DIR/detect-os.sh"
    source "$SCRIPT_DIR/lib/config.sh"
    source "$SCRIPT_DIR/lib/lib.sh"

    LOG_FILE="$HOME/logs/boblbee-update.log"
    PROM_FILE="$PROMETHEUS_TEXTFILE_DIR/boblbee.prom"

    case "${1:-}" in
        --install)   install_schedule; return ;;
        --uninstall) uninstall_schedule; return ;;
    esac

    # Ensure directories exist
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$PROMETHEUS_TEXTFILE_DIR"

    run_update
    local rc=$?
    migrate_legacy_labels
    return $rc
}

log_entry() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

write_metrics() {
    local success="$1"
    local commit branch
    commit=$(git -C "$BOBLBEE_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    branch=$(git -C "$BOBLBEE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

    cat > "$PROM_FILE.tmp" << EOF
# HELP boblbee_update_timestamp_seconds Unix timestamp of last boblbee self-update run
# TYPE boblbee_update_timestamp_seconds gauge
boblbee_update_timestamp_seconds $(date +%s)
# HELP boblbee_update_success Whether the last boblbee self-update succeeded
# TYPE boblbee_update_success gauge
boblbee_update_success $success
# HELP boblbee_update_info Current boblbee checkout info
# TYPE boblbee_update_info gauge
boblbee_update_info{commit="$commit",branch="$branch"} 1
EOF
    mv "$PROM_FILE.tmp" "$PROM_FILE"
}

run_update() {
    log_entry "Starting self-update"

    cd "$BOBLBEE_DIR" || { log_entry "FAIL: can't cd to $BOBLBEE_DIR"; write_metrics 0; return 1; }

    BRANCH=$(get_default_branch)

    # Fetch over HTTPS (no SSH key needed for public repo)
    if ! git fetch -q "$REPO_HTTPS" "$BRANCH" 2>>"$LOG_FILE"; then
        log_entry "FAIL: git fetch failed"
        write_metrics 0
        return 1
    fi

    # Check for changes
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse FETCH_HEAD)

    if [[ "$LOCAL" == "$REMOTE" ]]; then
        log_entry "OK: already up to date ($(git rev-parse --short HEAD))"
        write_metrics 1
        return 0
    fi

    # Merge (ff-only for safety — refuses if local edits exist)
    if ! git merge -q --ff-only FETCH_HEAD 2>>"$LOG_FILE"; then
        log_entry "FAIL: merge failed (local changes?)"
        write_metrics 0
        return 1
    fi

    log_entry "Updated: $(git rev-parse --short "$LOCAL") -> $(git rev-parse --short HEAD)"

    # Run sync scripts (no sudo, non-interactive)
    run_sync() {
        local script="$1"
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            if "$SCRIPT_DIR/$script" >> "$LOG_FILE" 2>&1; then
                log_entry "  $script: ok"
            else
                log_entry "  $script: failed (non-fatal)"
            fi
        fi
    }

    run_sync "zshrc-sync.sh"
    run_sync "tmux-sync.sh"
    run_sync "motd-sync.sh"
    run_sync "ssh-sync.sh"
    is_macos && run_sync "ghostty-sync.sh"
    is_macos && run_sync "zed-sync.sh"
    run_sync "observability-collector.sh"
    run_sync "host-agents.sh"          # per-host agents from hosts/agent-assignments.txt (idempotent)

    log_entry "OK: sync complete ($(git rev-parse --short HEAD))"
    write_metrics 1
}

# =========================================================================
# Schedule management
# =========================================================================

# ---------------------------------------------------------------------------
# One-off label migration (macOS). LaunchAgent labels are the author's
# reverse-DNS, so com.boblbee.* and com.observability.* become org.iaconelli.*.
# Safe to run every night: it does nothing once the legacy plists are gone.
# ---------------------------------------------------------------------------
migrate_legacy_labels() {
    is_macos || return 0
    local uid; uid=$(id -u)
    local agents="$HOME/Library/LaunchAgents"

    # node_exporter: same plist, new label; restart under the new name.
    local old_ne="$agents/com.observability.node-exporter.plist"
    local new_ne="$agents/org.iaconelli.node-exporter.plist"
    if [ -f "$old_ne" ]; then
        if [ ! -f "$new_ne" ]; then
            sed 's#<string>com.observability.node-exporter</string>#<string>org.iaconelli.node-exporter</string>#' "$old_ne" > "$new_ne"
        fi
        launchctl bootout "gui/$uid/com.observability.node-exporter" 2>/dev/null || true
        rm -f "$old_ne"
        launchctl bootout "gui/$uid/org.iaconelli.node-exporter" 2>/dev/null || true
        launchctl bootstrap "gui/$uid" "$new_ne" 2>/dev/null || launchctl load "$new_ne" 2>/dev/null || true
        log_entry "migrated LaunchAgent label: com.observability.node-exporter -> org.iaconelli.node-exporter"
    fi

    # self-update: write the new agent, then retire the old label *after* this run exits
    # (booting out the label we are running under would kill this script mid-way).
    local old_su="$agents/com.boblbee.self-update.plist"
    if [ -f "$old_su" ]; then
        install_launchagent > /dev/null
        rm -f "$old_su"
        nohup sh -c "sleep 15; launchctl bootout gui/$uid/com.boblbee.self-update" > /dev/null 2>&1 &
        log_entry "migrated LaunchAgent label: com.boblbee.self-update -> org.iaconelli.boblbee-self-update (old label retired after this run)"
    fi
}

install_schedule() {
    mkdir -p "$HOME/logs"
    mkdir -p "$PROMETHEUS_TEXTFILE_DIR"

    if is_macos; then
        install_launchagent
    elif is_ubuntu; then
        install_cron
    else
        echo "Unsupported platform for scheduling"
        return 1
    fi
}

uninstall_schedule() {
    if is_macos; then
        uninstall_launchagent
    elif is_ubuntu; then
        uninstall_cron
    fi
}

install_launchagent() {
    local plist_path="$HOME/Library/LaunchAgents/org.iaconelli.boblbee-self-update.plist"
    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.iaconelli.boblbee-self-update</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_DIR}/self-update.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>0</integer>
        <key>Minute</key>
        <integer>48</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/logs/boblbee-update.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/logs/boblbee-update.log</string>
</dict>
</plist>
EOF

    launchctl unload "$plist_path" 2>/dev/null || true
    launchctl load "$plist_path"
    echo -e "${GREEN}Installed LaunchAgent (daily at 00:48)${NC}"
}

uninstall_launchagent() {
    local plist_path="$HOME/Library/LaunchAgents/org.iaconelli.boblbee-self-update.plist"
    launchctl unload "$plist_path" 2>/dev/null || true
    rm -f "$plist_path"
    echo -e "${GREEN}Removed LaunchAgent${NC}"
}

install_cron() {
    local cron_cmd="${SCRIPT_DIR}/self-update.sh"
    local cron_entry="48 0 * * * $cron_cmd >> $HOME/logs/boblbee-update.log 2>&1"

    # Remove any existing boblbee entry, then add
    (crontab -l 2>/dev/null | grep -v 'self-update.sh'; echo "$cron_entry") | crontab -
    echo -e "${GREEN}Installed cron job (daily at 00:48)${NC}"
}

uninstall_cron() {
    (crontab -l 2>/dev/null | grep -v 'self-update.sh') | crontab -
    echo -e "${GREEN}Removed cron job${NC}"
}

main "$@"
