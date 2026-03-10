#!/usr/bin/env bash
#
# status-fleet.sh — report config/infra status across all hosts
#
# Checks, per host:
#   - reachable over SSH
#   - boblbee repo commit (drift vs. local HEAD)
#   - ~/.zshrc: local file or symlink, content hash vs. repo
#   - zsh plugin load status (source path)
#   - MacPorts presence
#   - ~/.ssh/agent dir perms (broken exec bit kills agent forwarding)
#
# Usage:
#   ./status-fleet.sh                # uses hosts/elements.txt
#   ./status-fleet.sh host1 host2    # explicit hosts
#
# Env:
#   HOSTS_FILE=path/to/hosts.txt     # override default host list
#

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOBLBEE_DIR="$(dirname "$SCRIPT_DIR")"
HOSTS_FILE="${HOSTS_FILE:-$BOBLBEE_DIR/hosts/elements.txt}"
SSH_OPTS="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=5}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
DIM='\033[2m'
NC='\033[0m'

ok()   { printf "${GREEN}%s${NC}" "$1"; }
bad()  { printf "${RED}%s${NC}" "$1"; }
warn() { printf "${YELLOW}%s${NC}" "$1"; }
dim()  { printf "${DIM}%s${NC}" "$1"; }

# Local reference: HEAD commit and expected zshrc hash
LOCAL_HEAD=$(git -C "$BOBLBEE_DIR" rev-parse --short HEAD 2>/dev/null || echo "???????")
ZSHRC_HASH=$(md5sum "$BOBLBEE_DIR/assets/.zshrc" 2>/dev/null | cut -c1-8 \
          || md5 -q "$BOBLBEE_DIR/assets/.zshrc" 2>/dev/null | cut -c1-8 \
          || echo "????????")

# Hosts: from args or from file
if [[ $# -gt 0 ]]; then
    HOSTS=("$@")
else
    mapfile -t HOSTS < <(grep -v '^\s*#' "$HOSTS_FILE" | grep -v '^\s*$')
fi

printf "Local HEAD: %s   zshrc hash: %s\n\n" "$LOCAL_HEAD" "$ZSHRC_HASH"
printf "%-10s %-10s %-10s %-18s %-24s %-10s %-8s\n" \
       HOST COMMIT ZSHRC ZSHRC-HASH PLUGINS MACPORTS AGENTDIR

drift=0

for h in "${HOSTS[@]}"; do
    # Gather everything in one SSH round-trip
    out=$(ssh $SSH_OPTS "$h" bash <<'REMOTE' 2>/dev/null
        # boblbee repo location
        for d in "$HOME/Developer/workspace/matdotcx/boblbee" \
                 "$HOME/Developer/matdotcx/boblbee" \
                 "$HOME/workspace/matdotcx/boblbee" \
                 "/workspace/matdotcx/boblbee"; do
            [[ -d "$d/.git" ]] && REPO="$d" && break
        done
        echo "repo_commit=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "norepo")"

        # zshrc: symlink or file, and content hash
        if [[ -L ~/.zshrc ]]; then
            echo "zshrc_type=symlink"
        elif [[ -f ~/.zshrc ]]; then
            echo "zshrc_type=file"
        else
            echo "zshrc_type=missing"
        fi
        h=$(md5sum ~/.zshrc 2>/dev/null | cut -c1-8 \
         || md5 -q ~/.zshrc 2>/dev/null | cut -c1-8 \
         || echo "--------")
        echo "zshrc_hash=$h"

        # plugins: force-load and see where _zsh_highlight came from
        p=$(zsh -ic '__load_plugins 2>/dev/null; whence -v _zsh_highlight 2>/dev/null' 2>/dev/null \
            | grep -oE '/[a-z/]+/zsh-syntax-highlighting' | head -1)
        echo "plugins=${p:-none}"

        # macports
        [[ -x /opt/local/bin/port ]] && echo "macports=yes" || echo "macports=no"

        # agent dir perms (should be drwx------, i.e. 700; missing is fine)
        if [[ -d ~/.ssh/agent ]]; then
            echo "agent_perms=$(stat -f %Lp ~/.ssh/agent 2>/dev/null || stat -c %a ~/.ssh/agent 2>/dev/null)"
        else
            echo "agent_perms=absent"
        fi
REMOTE
    )

    if [[ -z "$out" ]]; then
        printf "%-10s %s\n" "$h" "$(bad unreachable)"
        drift=1
        continue
    fi

    # parse key=value lines
    declare -A f=()
    while IFS='=' read -r k v; do f["$k"]="$v"; done <<< "$out"

    # render fields with colour
    commit="${f[repo_commit]:-?}"
    if [[ "$commit" == "$LOCAL_HEAD" ]]; then c_commit=$(ok "$commit")
    elif [[ "$commit" == "norepo" ]];     then c_commit=$(bad "norepo"); drift=1
    else                                       c_commit=$(warn "$commit"); drift=1
    fi

    ztype="${f[zshrc_type]:-?}"
    if [[ "$ztype" == "file" ]];       then c_ztype=$(ok file)
    elif [[ "$ztype" == "symlink" ]];  then c_ztype=$(warn symlink); drift=1
    else                                    c_ztype=$(bad "$ztype"); drift=1
    fi

    zhash="${f[zshrc_hash]:-?}"
    if [[ "$zhash" == "$ZSHRC_HASH" ]]; then c_zhash=$(ok "$zhash")
    else                                     c_zhash=$(warn "$zhash"); drift=1
    fi

    plugins="${f[plugins]:-?}"
    if [[ "$plugins" == "none" ]]; then c_plugins=$(bad "not loaded"); drift=1
    else                                c_plugins=$(dim "${plugins##*/share/}")
    fi

    mp="${f[macports]:-?}"
    if [[ "$mp" == "yes" ]]; then c_mp=$(ok yes)
    else                          c_mp=$(warn no)
    fi

    ap="${f[agent_perms]:-?}"
    if [[ "$ap" == "700" || "$ap" == "absent" ]]; then c_ap=$(ok "$ap")
    else                                               c_ap=$(bad "$ap"); drift=1
    fi

    # column widths account for ANSI codes (pad by visible width)
    printf "%-10s %-19s %-19s %-27s %-33s %-19s %-17s\n" \
        "$h" "$c_commit" "$c_ztype" "$c_zhash" "$c_plugins" "$c_mp" "$c_ap"
done

echo ""
if [[ $drift -eq 0 ]]; then
    echo -e "${GREEN}All hosts in sync.${NC}"
else
    echo -e "${YELLOW}Drift detected — run bb-sync-fleet to converge.${NC}"
fi
exit $drift
