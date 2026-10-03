#!/bin/bash
# posture.sh — hourly host posture gauges for Xenon v1 (boblbee hosts/agents/posture; xenon docs/V1.md §2).
#
# Writes posture.prom to node_exporter's textfile directory, the way boblbee.prom and the *_backup.prom
# files already work, so Prometheus scrapes it and Xenon reads the gauges without holding a key.
#
#   posture.sh                 write <textfile dir>/posture.prom
#   posture.sh --stdout        print the metrics instead
#   posture.sh --textfile DIR  write DIR/posture.prom
#
# Every check only reads. Run as the login user (the macOS LaunchAgent), it reports what that user can see;
# a check it can't evaluate sets posture_check_ok{check}=0 and emits no gauge, rather than a guess. Run as root
# (the Linux systemd timer), it sees everything. Secret values never leave the host: the secrets check counts
# file names, and the age check counts recipient stanzas in a backup's header.
#
# Works with macOS's bash 3.2: no associative arrays, mapfile or ${var,,}.
set -u
VERSION=1
export PATH="$HOME/bin:/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Tailscale.app/Contents/MacOS:/Applications/UTM.app/Contents/MacOS"
OS=$(uname -s); ME=$(id -un); ROOT=0; [ "$(id -u)" = 0 ] && ROOT=1
MODE=file; OUTDIR=""
case "${1:-}" in
    --stdout) MODE=stdout ;;
    --textfile) OUTDIR="${2:-}"; [ -n "$OUTDIR" ] || { echo "posture.sh: --textfile needs a directory" >&2; exit 2; } ;;
    "") ;;
    *) sed -n '2,15p' "$0"; exit 2 ;;
esac
START=$(date +%s)
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/posture.XXXXXX") || exit 1
trap 'rm -rf "$TMPD"' EXIT
TAB=$(printf '\t')

# ── output: samples are bucketed per metric so each family is contiguous, with one HELP/TYPE ──
FAMILIES=""
def() { printf '# HELP %s %s\n# TYPE %s gauge\n' "$1" "$2" "$1" > "$TMPD/$1.h"; FAMILIES="$FAMILIES $1"; }
put() { # metric value [labels]
    if [ -n "${3:-}" ]; then printf '%s{%s} %s\n' "$1" "$3" "$2"; else printf '%s %s\n' "$1" "$2"; fi >> "$TMPD/$1.s"
}
ok() { put posture_check_ok "$2" "check=\"$1\""; }
lv() { printf '%s' "$1" | tr '\n' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
with_timeout() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

def posture_collector_info        'Posture collector version, the user it ran as, and whether that user is root.'
def posture_last_run_timestamp_seconds 'When posture.sh last finished.'
def posture_run_duration_seconds  'How long the last posture.sh run took.'
def posture_check_ok              '1 when the check could be evaluated by this user, 0 when it could not (its gauges are then absent).'
def posture_tailscale_run_ssh     'Tailscale SSH server on (RunSSH). Expected 0: it bypasses authorized_keys options.'
def posture_sshd_permitrootlogin  'Effective sshd PermitRootLogin: 0 no, 1 forced-commands-only, 2 prohibit-password, 3 yes.'
def posture_root_authorized_keys  "Keys in root's authorized_keys, split by whether a forced command restricts them."
def posture_sudo_nopasswd         'NOPASSWD sudo rules per user. Expected 0 on internet-facing hosts.'
def posture_swu_auto_install      'macOS installs macOS updates automatically: 1 on, 0 off, -1 unset (the macOS default applies).'
def posture_filevault_on          'macOS FileVault is on.'
def posture_autologin_set         'macOS automatic login is set (it cannot work while FileVault is on).'
def posture_autorestart           'macOS restarts automatically after a power failure (pmset autorestart).'
def posture_unattended_upgrades   'Debian/Ubuntu unattended-upgrades is enabled and scheduled.'
def posture_untracked_secret_files 'Secret-looking files in a git repo that are neither tracked nor ignored, so a careless git add would commit them.'
def posture_age_recipients        'Recipient stanzas, by type, in the newest age file of each backup set.'
def posture_guest_running         'A VM or container engine on this host is running.'
def posture_guest_memory_bytes    'Memory assigned to a guest.'
def posture_container_unpinned    'A running container whose image reference is not pinned by digest.'

# ── access ──
check_tailscale() {
    local ts out
    ts=$(command -v tailscale 2>/dev/null) || { [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ] && ts=/Applications/Tailscale.app/Contents/MacOS/Tailscale; }
    [ -n "$ts" ] || return 0                                   # no Tailscale here: nothing to check
    out=$(with_timeout 10 "$ts" debug prefs 2>/dev/null)
    case "$out" in
        *'"RunSSH": true'*)  put posture_tailscale_run_ssh 1; ok tailscale_ssh 1 ;;
        *'"RunSSH": false'*) put posture_tailscale_run_ssh 0; ok tailscale_ssh 1 ;;
        *) ok tailscale_ssh 0 ;;
    esac
}

# First value of an sshd keyword the way sshd reads it: first match wins, Include is followed in order,
# and global settings end at a Match line. An unreadable file makes the answer incomplete.
sshd_first() { # keyword-lowercase file
    local key=$1 f=$2 line k inc g v
    if [ ! -r "$f" ]; then : > "$TMPD/sshd.incomplete"; return 1; fi
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%%#*}
        set -f; set -- $line; set +f
        [ $# -ge 2 ] || continue
        k=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
        case "$k" in
            match) return 1 ;;
            include)
                shift
                for inc in "$@"; do
                    case "$inc" in /*) ;; *) inc="/etc/ssh/$inc" ;; esac
                    for g in $inc; do
                        [ -e "$g" ] || continue
                        if v=$(sshd_first "$key" "$g"); then echo "$v"; return 0; fi
                    done
                done ;;
            "$key") printf '%s\n' "$2" | tr '[:upper:]' '[:lower:]'; return 0 ;;
        esac
    done < "$f"
    return 1
}
check_sshd() {
    local v="" code
    [ -e /etc/ssh/sshd_config ] || return 0
    if [ $ROOT = 1 ] && command -v sshd >/dev/null; then
        v=$(sshd -T 2>/dev/null | awk '$1 == "permitrootlogin" { print $2; exit }')
    fi
    if [ -z "$v" ]; then
        v=$(sshd_first permitrootlogin /etc/ssh/sshd_config) || v=prohibit-password   # OpenSSH's default since 7.0
        if [ -e "$TMPD/sshd.incomplete" ]; then ok sshd_config 0; return; fi
    fi
    case "$v" in no) code=0 ;; forced-commands-only) code=1 ;; prohibit-password|without-password) code=2 ;; yes) code=3 ;; *) ok sshd_config 0; return ;; esac
    put posture_sshd_permitrootlogin "$code"; ok sshd_config 1
}

check_root_keys() {
    local home f forced=0 open=0 line
    case "$OS" in Darwin) home=/var/root ;; *) home=/root ;; esac
    # Without search permission on root's home, a missing file and an unreadable one look the same.
    if [ ! -x "$home" ] || { [ -d "$home/.ssh" ] && [ ! -x "$home/.ssh" ]; }; then ok root_authorized_keys 0; return; fi
    for f in "$home/.ssh/authorized_keys" "$home/.ssh/authorized_keys2"; do
        [ -e "$f" ] || continue
        [ -r "$f" ] || { ok root_authorized_keys 0; return; }
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in ''|'#'*) continue ;; *'command="'*) forced=$((forced + 1)) ;; *) open=$((open + 1)) ;; esac
        done < "$f"
    done
    put posture_root_authorized_keys "$open" 'forced_command="0"'
    put posture_root_authorized_keys "$forced" 'forced_command="1"'
    ok root_authorized_keys 1
}

human_users() {
    case "$OS" in
        Darwin) dscl . list /Users UniqueID 2>/dev/null | awk '$2 >= 501 && $1 !~ /^_/ { print $1 }' ;;
        *) getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ { print $1 }' ;;
    esac
}
check_sudo() {
    local u n
    command -v sudo >/dev/null || return 0
    if [ $ROOT = 1 ]; then
        for u in $(human_users); do
            n=$(sudo -n -l -U "$u" 2>/dev/null | grep -c NOPASSWD)
            put posture_sudo_nopasswd "${n:-0}" "user=\"$(lv "$u")\""
        done
    else
        # With sudo's default listpw=any, -n -l only succeeds without a password when a NOPASSWD rule exists.
        n=$(sudo -n -l 2>/dev/null | grep -c NOPASSWD)
        put posture_sudo_nopasswd "${n:-0}" "user=\"$(lv "$ME")\""
    fi
    ok sudo 1
}

# ── updates and power ──
check_macos() {
    local v
    v=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null)
    case "$v" in 1|true) put posture_swu_auto_install 1 ;; 0|false) put posture_swu_auto_install 0 ;; *) put posture_swu_auto_install -1 ;; esac
    case "$(fdesetup status 2>/dev/null)" in
        *'FileVault is On'*)  put posture_filevault_on 1; ok filevault 1 ;;
        *'FileVault is Off'*) put posture_filevault_on 0; ok filevault 1 ;;
        *) ok filevault 0 ;;
    esac
    if defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser >/dev/null 2>&1; then put posture_autologin_set 1; else put posture_autologin_set 0; fi
    v=$(pmset -g 2>/dev/null | awk '$1 == "autorestart" { print $2; exit }')
    case "$v" in 0|1) put posture_autorestart "$v" ;; esac
}
check_linux() {
    local v e
    command -v apt-config >/dev/null || return 0
    v=$(apt-config dump 2>/dev/null | awk -F'"' '$1 == "APT::Periodic::Unattended-Upgrade " { print $2; exit }')
    e=$(systemctl is-enabled unattended-upgrades 2>/dev/null)
    if [ "$v" = 1 ] && [ "$e" = enabled ]; then put posture_unattended_upgrades 1; else put posture_unattended_upgrades 0; fi
}

# ── secrets ──
SECRET_RE='(^|/)(secrets?([-_.][^/]*)?/[^/]+|\.env(\.[^/]+)?|[^/]+\.(pem|key|p12|pfx|token)|id_(rsa|ed25519|ecdsa|dsa)|[^/]*(api[-_]?key|ping-url|credentials|secret)[^/]*)$'
SAFE_RE='(example|sample|template|\.dist$|\.md$|\.pub$|\.age$|\.(py|js|ts|go|rs|rb|sh|swift|java|kt)$)'   # docs, public keys, ciphertext, code
find_repos() {
    local b d
    {
        for b in "$HOME" $([ $ROOT = 1 ] && ls -d /home/* /Users/* 2>/dev/null | grep -v '^/Users/Shared$'); do
            for d in "$b"/*/.git "$b"/Developer/*/.git "$b"/Developer/*/*/.git "$b"/Developer/*/*/*/.git; do
                [ -d "$d" ] && printf '%s\n' "${d%/.git}"
            done
        done
        for d in /opt/*/.git /srv/*/.git; do [ -d "$d" ] && printf '%s\n' "${d%/.git}"; done
    } | sort -u
}
check_secrets() {
    local repo n
    find_repos > "$TMPD/repos"
    while IFS= read -r repo; do
        n=$(with_timeout 30 git -c safe.directory='*' -C "$repo" ls-files --others --exclude-standard 2>/dev/null \
              | grep -E "$SECRET_RE" | grep -viE "$SAFE_RE" | wc -l | tr -d ' ')
        put posture_untracked_secret_files "${n:-0}" "repo=\"$(lv "$repo")\""
    done < "$TMPD/repos"
}

# ── backups (cobalt): how many recipients the newest age file of each set is encrypted to ──
check_age() {
    local base="${POSTURE_BACKUPS:-$HOME/backups}" d set f
    [ -d "$base" ] || return 0
    for d in "$base"/*/; do
        set=$(basename "$d")
        f=$(find "$d" -type f -name '*.age' -exec ls -t {} + 2>/dev/null | head -1)
        [ -n "$f" ] || continue
        head -c 8192 "$f" | LC_ALL=C awk '/^-> / { print $2 } /^---/ { exit }' | sort | uniq -c | while read -r n type; do
            put posture_age_recipients "$n" "set=\"$(lv "$set")\",type=\"$(lv "$type")\""
        done
    done
}

# ── guests and their containers ──
containers() { # guest command-that-is-docker...
    local g=$1 ids out name image u; shift
    if ! ids=$(with_timeout 30 "$@" ps -q 2>/dev/null); then ok "containers:$g" 0; return; fi
    ok "containers:$g" 1
    [ -n "$ids" ] || return 0
    # .Config.Image is the reference the container was created from. docker ps shows a digest reference as a bare
    # image ID, which would hide a pin.
    # shellcheck disable=SC2086
    out=$(with_timeout 30 "$@" inspect --format '{{.Name}}{{"\t"}}{{.Config.Image}}' $ids 2>/dev/null) || { ok "containers:$g" 0; return; }
    printf '%s\n' "$out" | while IFS="$TAB" read -r name image; do
        name=${name#/}; [ -n "$name" ] || continue
        case "$image" in *@sha256:*) u=0 ;; *) u=1 ;; esac
        put posture_container_unpinned "$u" "guest=\"$(lv "$g")\",container=\"$(lv "$name")\",image=\"$(lv "$image")\""
    done
}
json_str() { printf '%s' "$2" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
json_num() { printf '%s' "$2" | sed -n "s/.*\"$1\":\([0-9][0-9]*\).*/\1/p"; }
check_guests() {
    local line name st mem g ctx run
    if command -v colima >/dev/null; then
        with_timeout 20 colima list -j 2>/dev/null > "$TMPD/colima"
        while IFS= read -r line; do
            name=$(json_str name "$line"); st=$(json_str status "$line"); mem=$(json_num memory "$line")
            [ -n "$name" ] || continue
            if [ "$name" = default ]; then g=colima; ctx=colima; else g="colima-$name"; ctx="colima-$name"; fi
            run=0; [ "$st" = Running ] && run=1
            put posture_guest_running "$run" "guest=\"$(lv "$g")\",kind=\"colima\""
            [ -n "$mem" ] && put posture_guest_memory_bytes "$mem" "guest=\"$(lv "$g")\""
            [ $run = 1 ] && containers "$g" docker --context "$ctx"
        done < "$TMPD/colima"
    fi
    if command -v limactl >/dev/null; then
        with_timeout 20 limactl list --format "{{.Name}}$TAB{{.Status}}$TAB{{.Memory}}" 2>/dev/null > "$TMPD/lima"
        while IFS="$TAB" read -r name st mem; do
            [ -n "$name" ] || continue
            run=0; [ "$st" = Running ] && run=1
            put posture_guest_running "$run" "guest=\"$(lv "$name")\",kind=\"lima\""
            case "$mem" in ''|*[!0-9]*) ;; *) put posture_guest_memory_bytes "$mem" "guest=\"$(lv "$name")\"" ;; esac
            if [ $run = 1 ] && with_timeout 15 limactl shell "$name" -- sh -c 'command -v docker' >/dev/null 2>&1; then
                containers "$name" limactl shell "$name" -- sudo -n docker
            fi
        done < "$TMPD/lima"
    fi
    if command -v utmctl >/dev/null; then
        # utmctl list: UUID, status, then the name (which may contain spaces). It needs the GUI session.
        # It exits 0 even when it fails ("does not work from SSH sessions"), so judge it by its output.
        if with_timeout 15 utmctl list > "$TMPD/utm" 2>&1 && ! grep -qE '^(Error|NOTE:)' "$TMPD/utm"; then
            ok utm 1
            tail -n +2 "$TMPD/utm" | while read -r _ st name; do
                [ -n "$name" ] || continue
                run=0; [ "$st" = started ] && run=1
                put posture_guest_running "$run" "guest=\"$(lv "$name")\",kind=\"utm\""
            done
        else
            ok utm 0
        fi
    fi
    if [ "$OS" = Linux ] && command -v docker >/dev/null; then
        # As root this is exact; as a user outside the docker group it reads as not evaluable.
        if with_timeout 10 docker info >/dev/null 2>&1; then
            put posture_guest_running 1 'guest="docker",kind="docker-engine"'
            containers docker docker
        else
            ok containers:docker 0
        fi
    fi
}

check_tailscale; check_sshd; check_root_keys; check_sudo
case "$OS" in Darwin) check_macos ;; Linux) check_linux ;; esac
check_secrets; check_age; check_guests
put posture_collector_info 1 "version=\"$VERSION\",user=\"$(lv "$ME")\",root=\"$ROOT\""
END=$(date +%s)
put posture_run_duration_seconds $((END - START))
put posture_last_run_timestamp_seconds "$END"

render() { local m; for m in $FAMILIES; do if [ -s "$TMPD/$m.s" ]; then cat "$TMPD/$m.h" "$TMPD/$m.s"; fi; done; }
if [ $MODE = stdout ]; then render; exit 0; fi

textfile_dir() {
    local d
    [ -n "$OUTDIR" ] && { printf '%s\n' "$OUTDIR"; return 0; }
    d=$(ps -A -o command= 2>/dev/null | grep -E 'node[_-]exporter' | grep -oE -- '--collector\.textfile\.directory[= ][^ ]+' | head -1 | sed -E 's/^--collector\.textfile\.directory[= ]//')
    [ -n "$d" ] && { printf '%s\n' "$d"; return 0; }
    for d in "$HOME/.local/share/prometheus/textfile" /var/lib/prometheus/node-exporter /var/lib/node_exporter/textfile; do
        [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
    done
    return 1
}
DIR=$(textfile_dir) || { echo "posture.sh: no node_exporter textfile directory found; pass --textfile DIR" >&2; exit 1; }
[ -d "$DIR" ] || { echo "posture.sh: $DIR does not exist" >&2; exit 1; }
tmp=$(mktemp "$DIR/.posture.prom.XXXXXX") || exit 1
render > "$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$DIR/posture.prom" || { rm -f "$tmp"; exit 1; }
