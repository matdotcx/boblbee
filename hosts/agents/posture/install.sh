#!/bin/bash
# install.sh — "posture" profile (boblbee hosts/agents/posture): every hour, write posture.prom (the posture
# gauges Xenon v1 reads, xenon docs/V1.md §2) to node_exporter's textfile directory. Read-only checks, run as the
# login user. Idempotent; run by scripts/host-agents.sh for every host listed with this profile
# in hosts/agent-assignments.txt.   ./install.sh [--check|--no-load]
#
# Linux hosts run the same posture.sh as root from a systemd timer instead: see linux/install-root.sh.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/bin"; AGENTS="$HOME/Library/LaunchAgents"; LOGS="$HOME/logs"
CHECK=0; LOAD=1
case "${1:-}" in --check) CHECK=1;; --no-load) LOAD=0;; "") ;; *) sed -n '2,7p' "$0"; exit 1;; esac
uid=$(id -u); rc=0
say(){ printf '%s\n' "$*"; }
say "== scripts -> $BIN"; mkdir -p "$BIN" "$LOGS"
for f in "$HERE"/bin/*; do
  b=$(basename "$f")
  if [ -f "$BIN/$b" ] && cmp -s "$f" "$BIN/$b"; then say "  same     $b"; continue; fi
  if [ $CHECK = 1 ]; then say "  DIFFERS  $b"; rc=1; continue; fi
  install -m 755 "$f" "$BIN/$b" && say "  installed $b"
done
say "== LaunchAgents -> $AGENTS"; mkdir -p "$AGENTS"
for t in "$HERE"/launchd/*.plist; do
  label=$(basename "$t" .plist); dst="$AGENTS/$label.plist"
  tmp=$(mktemp); sed "s#__HOME__#$HOME#g" "$t" > "$tmp"
  if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then state=same; else state=changed; fi
  if [ $CHECK = 1 ]; then
    loaded=$(launchctl print "gui/$uid/$label" >/dev/null 2>&1 && echo loaded || echo NOT-LOADED)
    # A job can be loaded and still never have run (seen once after a bootstrap): count that as a failure too.
    runs=$(launchctl print "gui/$uid/$label" 2>/dev/null | awk '$1 == "runs" { print $3; exit }')
    [ "$state" = same ] && [ "$loaded" = loaded ] && [ "${runs:-0}" -gt 0 ] || rc=1
    say "  $label: plist $state, $loaded, runs ${runs:-0}"; rm -f "$tmp"; continue
  fi
  if [ "$state" = changed ]; then install -m 644 "$tmp" "$dst" && say "  wrote    $label"; else say "  same     $label"; fi
  rm -f "$tmp"
  if [ $LOAD = 1 ]; then
    loaded=$(launchctl print "gui/$uid/$label" >/dev/null 2>&1 && echo yes || echo no)
    if [ "$state" = changed ] || [ "$loaded" = no ]; then
      launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
      if launchctl bootstrap "gui/$uid" "$dst" 2>/dev/null; then say "  loaded   $label"; else say "  FAILED to load $label"; rc=1; fi
      # RunAtLoad should start it, but don't rely on it: start it now so posture.prom appears straight away.
      launchctl kickstart "gui/$uid/$label" >/dev/null 2>&1 && say "  started  $label"
    else say "  running  $label"; fi
  fi
done
say "== prerequisites"
T="$HOME/.local/share/prometheus/textfile"
if [ -d "$T" ]; then say "  $T: ok"; else say "  $T: MISSING (node_exporter's textfile directory; posture.sh finds others itself)"; fi
P="$T/posture.prom"
if [ -f "$P" ]; then say "  posture.prom: written $(( ($(date +%s) - $(stat -f %m "$P")) / 60 )) min ago"; else say "  posture.prom: not written yet"; fi
exit $rc
