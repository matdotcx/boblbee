#!/bin/bash
# install-root.sh — the posture profile on a Linux host (deadline, the Pis): posture.sh as root, hourly, from a
# systemd timer. As root it can read sshd -T, root's authorized_keys, every user's sudo rules and Docker.
#
# The copy root runs is root-owned in /usr/local/libexec/posture, outside every user's home, so the login user
# can't change what root executes (DESIGN §8.2). Updating it means running this again; boblbee's nightly
# self-update doesn't touch it.
#
#   sudo bash install-root.sh                    install or refresh, then run once
#   sudo bash install-root.sh --enable-textfile  also give node_exporter a textfile directory if it has none
#   sudo bash install-root.sh --check            report what's installed, change nothing
#   sudo bash install-root.sh --uninstall        remove the timer, the copy and posture.prom
#
# Run it from a copy of the whole profile (it installs ../bin/posture.sh), e.g.
#   scp -r hosts/agents/posture HOST:/tmp/ && ssh -t HOST 'sudo bash /tmp/posture/linux/install-root.sh'
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../bin/posture.sh"
DST_DIR=/usr/local/libexec/posture; DST="$DST_DIR/posture.sh"
UNIT=/etc/systemd/system/posture.service; TIMER=/etc/systemd/system/posture.timer
MODE=install; ENABLE_TEXTFILE=0
for a in "$@"; do case "$a" in
    --check) MODE=check ;; --uninstall) MODE=uninstall ;; --enable-textfile) ENABLE_TEXTFILE=1 ;;
    *) sed -n '2,16p' "$0"; exit 2 ;;
esac; done
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
say() { printf '%s\n' "$*"; }

exporter_unit() { systemctl list-units --type=service --all --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^(prometheus-)?node[-_]exporter\.service$' | head -1; }
exporter_dir() {
    local cmd d root
    cmd=$(ps -A -o command= | grep -E 'node[_-]exporter' | grep -E -- '--collector\.textfile\.directory' | head -1)
    d=$(printf '%s\n' "$cmd" | grep -oE -- '--collector\.textfile\.directory[= ][^ ]+' | head -1 | sed -E 's/^--collector\.textfile\.directory[= ]//')
    # A containerised node_exporter names the directory as it sees it, under --path.rootfs; the host path drops that.
    root=$(printf '%s\n' "$cmd" | grep -oE -- '--path\.rootfs[= ][^ ]+' | head -1 | sed -E 's/^--path\.rootfs[= ]//')
    if [ -n "$d" ] && [ -n "$root" ] && [ "$root" != / ] && [ ! -d "$d" ]; then d=${d#"${root%/}"}; fi
    printf '%s\n' "$d"
}
textfile_dir() {
    local d; d=$(exporter_dir)
    if [ -n "$d" ]; then printf '%s\n' "$d"; return 0; fi
    # Debian's prometheus-node-exporter package builds this default in, with no flag on the command line.
    if [ "$(exporter_unit)" = prometheus-node-exporter.service ] && [ -d /var/lib/prometheus/node-exporter ]; then
        printf '%s\n' /var/lib/prometheus/node-exporter; return 0
    fi
    return 1
}

if [ $MODE = uninstall ]; then
    systemctl disable --now posture.timer 2>/dev/null && say "stopped posture.timer"
    rm -f "$UNIT" "$TIMER" && systemctl daemon-reload && say "removed the units"
    rm -rf "$DST_DIR" && say "removed $DST_DIR"
    d=$(textfile_dir) && rm -f "$d/posture.prom" && say "removed $d/posture.prom"
    exit 0
fi

if [ $MODE = check ]; then
    rc=0
    if [ -x "$DST" ] && cmp -s "$SRC" "$DST"; then say "  $DST: current"; else say "  $DST: MISSING or differs"; rc=1; fi
    st=$(stat -c '%U:%G %a' "$DST" 2>/dev/null); [ "$st" = "root:root 755" ] && say "  owner and mode: $st" || { say "  owner and mode: ${st:-none} (want root:root 755)"; rc=1; }
    systemctl is-active --quiet posture.timer && say "  posture.timer: active, next $(systemctl show posture.timer -p NextElapseUSecRealtime --value)" || { say "  posture.timer: NOT active"; rc=1; }
    if d=$(textfile_dir); then
        if [ -f "$d/posture.prom" ]; then say "  $d/posture.prom: written $(( ($(date +%s) - $(stat -c %Y "$d/posture.prom")) / 60 )) min ago"; else say "  $d/posture.prom: not written yet"; rc=1; fi
    else say "  node_exporter has no textfile directory (run with --enable-textfile)"; rc=1; fi
    exit $rc
fi

[ -f "$SRC" ] || { say "can't find $SRC: copy the whole posture profile, not just this script"; exit 1; }

say "== textfile directory"
if ! dir=$(textfile_dir); then
    unit=$(exporter_unit)
    if [ -z "$unit" ]; then say "  no node_exporter service found; nothing would scrape posture.prom"; exit 1; fi
    if [ $ENABLE_TEXTFILE = 0 ]; then say "  $unit runs without --collector.textfile.directory; re-run with --enable-textfile"; exit 1; fi
    dir=/var/lib/node_exporter/textfile
    # Repeat the unit's effective ExecStart with the flag added. The drop-in sorts last so it wins.
    exec_line=$(systemctl cat "$unit" | sed -n 's/^ExecStart=\(..*\)$/\1/p' | tail -1)
    [ -n "$exec_line" ] || { say "  can't read $unit's ExecStart"; exit 1; }
    install -d -o root -g root -m 755 "$dir" "/etc/systemd/system/$unit.d"
    printf '[Service]\nExecStart=\nExecStart=%s --collector.textfile.directory=%s\n' "$exec_line" "$dir" > "/etc/systemd/system/$unit.d/zz-posture-textfile.conf"
    systemctl daemon-reload && systemctl restart "$unit"
    sleep 2
    if [ "$(exporter_dir)" = "$dir" ]; then say "  $unit now reads $dir"; else say "  $unit did not pick up $dir; check: systemctl status $unit"; exit 1; fi
else
    say "  $dir"
fi

say "== $DST"
install -d -o root -g root -m 755 "$DST_DIR"
if [ -f "$DST" ] && cmp -s "$SRC" "$DST"; then say "  same"; else install -o root -g root -m 755 "$SRC" "$DST" && say "  installed"; fi

say "== systemd"
cat > "$UNIT" <<EOF
[Unit]
Description=Write posture.prom for Xenon (boblbee posture profile)
After=network-online.target

[Service]
Type=oneshot
Environment=HOME=/root
ExecStart=$DST --textfile $dir
Nice=10
IOSchedulingClass=idle
PrivateTmp=yes
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=read-only
EOF
cat > "$TIMER" <<'EOF'
[Unit]
Description=Hourly posture.prom for Xenon

[Timer]
OnCalendar=hourly
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload && systemctl enable --now posture.timer >/dev/null 2>&1 && say "  posture.timer enabled"

say "== first run"
if systemctl start posture.service; then
    say "  ok: $(grep -vc '^#' "$dir/posture.prom") samples in $dir/posture.prom"
    grep -E '^posture_(check_ok\{.*\} 0|sshd_permitrootlogin|root_authorized_keys|sudo_nopasswd|tailscale_run_ssh|unattended_upgrades)' "$dir/posture.prom" | sed 's/^/    /'
else
    say "  posture.service failed: journalctl -u posture.service -n 20"; exit 1
fi
