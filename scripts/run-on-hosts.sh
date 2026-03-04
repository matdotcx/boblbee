#!/usr/bin/env bash
#
# run-on-hosts.sh - Run commands on multiple hosts
#
# Simple configuration management: execute a set of commands across a list of hosts.
#
# Usage:
#   ./run-on-hosts.sh <commands-file> [hosts-file]
#   ./run-on-hosts.sh <commands-file> host1 host2 host3 ...
#
# Examples:
#   ./run-on-hosts.sh commands.txt hosts.txt
#   ./run-on-hosts.sh commands.txt alice bob charlie
#   ./run-on-hosts.sh commands.txt helium
#
# Commands file format (one command per line):
#   sudo apt update
#   sudo apt upgrade -y
#   # Comments are ignored
#
#   # Blank lines are ignored too
#   echo "Done"
#
# Hosts file format (one host per line):
#   alice
#   bob
#   charlie
#   # Comments work here too
#
# Options (set via environment variables):
#   DRY_RUN=1       Show what would run without executing
#   PARALLEL=1      Run on all hosts simultaneously (default: sequential)
#   STOP_ON_ERROR=1 Stop if any command fails (default: continue)
#   SSH_OPTS="-A"   Additional SSH options (default: -A for agent forwarding)
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
SSH_OPTS="${SSH_OPTS:--A}"
DRY_RUN="${DRY_RUN:-0}"
PARALLEL="${PARALLEL:-0}"
STOP_ON_ERROR="${STOP_ON_ERROR:-0}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_host() { echo -e "${CYAN}[$1]${NC} $2"; }

usage() {
    cat << EOF
Usage: $(basename "$0") <commands-file> [hosts-file | host1 host2 ...]

Run commands from <commands-file> on each specified host.

Arguments:
  commands-file   File containing commands to run (one per line)
  hosts-file      File containing hostnames (one per line)
  host1 host2...  Alternatively, specify hosts directly as arguments

Environment Variables:
  DRY_RUN=1       Show commands without executing
  PARALLEL=1      Run on all hosts simultaneously
  STOP_ON_ERROR=1 Stop if any command fails on a host
  SSH_OPTS="-A"   SSH options (default: -A for agent forwarding)

Examples:
  $(basename "$0") update.txt hosts.txt
  $(basename "$0") deploy.txt alice bob charlie
  DRY_RUN=1 $(basename "$0") commands.txt hosts.txt
  PARALLEL=1 $(basename "$0") commands.txt hosts.txt
EOF
    exit 1
}

# Parse commands file, stripping comments and blank lines
parse_commands() {
    local file="$1"
    grep -v '^\s*#' "$file" | grep -v '^\s*$'
}

# Parse hosts file or use arguments
parse_hosts() {
    local first_arg="$1"
    shift

    if [[ -f "$first_arg" ]]; then
        # It's a file
        grep -v '^\s*#' "$first_arg" | grep -v '^\s*$'
    else
        # It's a hostname, plus any remaining args
        echo "$first_arg"
        for host in "$@"; do
            echo "$host"
        done
    fi
}

# Run commands on a single host
run_on_host() {
    local host="$1"
    local commands_file="$2"
    local failed=0

    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}   ${host}${NC}"
    echo -e "${BLUE}================================================================${NC}"

    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue

        log_host "$host" "$ $cmd"

        if [[ "$DRY_RUN" == "1" ]]; then
            continue
        fi

        local output
        local exit_code
        output=$(ssh -n $SSH_OPTS "$host" "$cmd" 2>&1)
        exit_code=$?

        echo "$output" | sed "s/^/  /"

        if [[ $exit_code -eq 0 ]]; then
            log_host "$host" "${GREEN}ok${NC}"
        else
            log_host "$host" "${RED}failed (exit $exit_code)${NC}"
            failed=1
            if [[ "$STOP_ON_ERROR" == "1" ]]; then
                log_error "Stopping due to error on $host"
                return 1
            fi
        fi
    done < <(parse_commands "$commands_file")

    if [[ "$failed" == "0" ]]; then
        log_success "$host: All commands completed"
    else
        log_warn "$host: Some commands failed"
    fi

    return $failed
}

# Main
main() {
    if [[ $# -lt 2 ]]; then
        usage
    fi

    local commands_file="$1"
    shift

    if [[ ! -f "$commands_file" ]]; then
        log_error "Commands file not found: $commands_file"
        exit 1
    fi

    # Collect hosts
    local hosts=()
    while IFS= read -r host; do
        hosts+=("$host")
    done < <(parse_hosts "$@")

    if [[ ${#hosts[@]} -eq 0 ]]; then
        log_error "No hosts specified"
        exit 1
    fi

    # Summary
    local cmd_count
    cmd_count=$(parse_commands "$commands_file" | wc -l | tr -d ' ')

    echo ""
    log_info "Commands file: $commands_file ($cmd_count commands)"
    log_info "Hosts: ${hosts[*]}"
    log_info "Mode: $([ "$PARALLEL" == "1" ] && echo "parallel" || echo "sequential")"
    [[ "$DRY_RUN" == "1" ]] && log_warn "DRY RUN - no commands will be executed"
    echo ""

    # Execute
    local failed_hosts=()

    if [[ "$PARALLEL" == "1" ]]; then
        # Parallel execution
        local pids=()
        local tmp_dir
        tmp_dir=$(mktemp -d)

        for host in "${hosts[@]}"; do
            (
                run_on_host "$host" "$commands_file" > "${tmp_dir}/${host}.log" 2>&1
                echo $? > "${tmp_dir}/${host}.status"
            ) &
            pids+=($!)
        done

        # Wait for all
        for pid in "${pids[@]}"; do
            wait "$pid" || true
        done

        # Show results
        for host in "${hosts[@]}"; do
            cat "${tmp_dir}/${host}.log"
            if [[ "$(cat "${tmp_dir}/${host}.status")" != "0" ]]; then
                failed_hosts+=("$host")
            fi
        done

        rm -rf "$tmp_dir"
    else
        # Sequential execution
        for host in "${hosts[@]}"; do
            if ! run_on_host "$host" "$commands_file"; then
                failed_hosts+=("$host")
                if [[ "$STOP_ON_ERROR" == "1" ]]; then
                    break
                fi
            fi
        done
    fi

    # Summary
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}   Summary${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""

    local success_count=$((${#hosts[@]} - ${#failed_hosts[@]}))

    if [[ ${#failed_hosts[@]} -eq 0 ]]; then
        log_success "All ${#hosts[@]} hosts completed successfully"
    else
        log_warn "${success_count}/${#hosts[@]} hosts completed successfully"
        log_error "Failed hosts: ${failed_hosts[*]}"
        exit 1
    fi
}

main "$@"
