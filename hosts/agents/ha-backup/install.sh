#!/bin/bash
# install.sh — "ha-backup" profile (boblbee hosts/agents/ha-backup): nightly pull of Home Assistant's
# encrypted backups from hydrogen onto the backup host (cobalt), where Backblaze takes them offsite.
# Idempotent; run by scripts/host-agents.sh for every host listed with this profile in
# hosts/agent-assignments.txt.   ./install.sh [--check|--no-load]
#
# Requires: ssh to hydrogen without a prompt from launchd (cobalt's key is in its keychain via
# UseKeychain, as for helium's observability backup). --check tests this.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/bin"; AGENTS="$HOME/Library/LaunchAgents"; LOGS="$HOME/logs"
CHECK=0; LOAD=1
case "${1:-}" in --check) CHECK=1;; --no-load) LOAD=0;; "") ;; *) sed -n '2,8p' "$0"; exit 1;; esac
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
    [ "$state" = same ] && [ "$loaded" = loaded ] || rc=1
    say "  $label: plist $state, $loaded"; rm -f "$tmp"; continue
  fi
  if [ "$state" = changed ]; then install -m 644 "$tmp" "$dst" && say "  wrote    $label"; else say "  same     $label"; fi
  rm -f "$tmp"
  if [ $LOAD = 1 ]; then
    loaded=$(launchctl print "gui/$uid/$label" >/dev/null 2>&1 && echo yes || echo no)
    if [ "$state" = changed ] || [ "$loaded" = no ]; then
      launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
      if launchctl bootstrap "gui/$uid" "$dst" 2>/dev/null; then say "  loaded   $label"; else say "  FAILED to load $label"; rc=1; fi
    else say "  running  $label"; fi
  fi
done
say "== prerequisites"
src_host=${HA_BACKUP_SRC:-hydrogen:}; src_host=${src_host%%:*}
if ssh -o BatchMode=yes -o ConnectTimeout=6 "$src_host" true 2>/dev/null; then say "  ssh $src_host: ok"; else say "  ssh $src_host: UNREACHABLE (host key or keychain-held key; see ~/logs/ha-backup-pull.log)"; rc=1; fi
exit $rc
