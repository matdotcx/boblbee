#!/bin/bash
# install.sh — "deadline-backup" profile (boblbee hosts/agents/deadline-backup): nightly pull of
# deadline's backup (/var/backups/deadline) onto the backup host (cobalt), where Backblaze takes it offsite.
# Idempotent; run by scripts/host-agents.sh for every host listed with this profile in
# hosts/agent-assignments.txt.   ./install.sh [--check|--no-load]
#
# Requires, in ~/.config/deadline-backup/: id_ed25519 (no passphrase; deadline's user bkpull accepts it
# only from cobalt's tailnet address, for one forced read-only rsync) and known_hosts (deadline's pinned key).
# deadline's side: xenon chores/scripts/deadline-backup/install.sh. --check tests the login.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/bin"; AGENTS="$HOME/Library/LaunchAgents"; LOGS="$HOME/logs"
CHECK=0; LOAD=1
case "${1:-}" in --check) CHECK=1;; --no-load) LOAD=0;; "") ;; *) sed -n '2,9p' "$0"; exit 1;; esac
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
C="$HOME/.config/deadline-backup"; H=${DEADLINE_BACKUP_HOST:-100.77.139.21}
for f in id_ed25519 known_hosts; do [ -f "$C/$f" ] && say "  $C/$f: ok" || { say "  $C/$f: MISSING"; rc=1; }; done
# The key is forced to one fixed rsync sender on deadline, so a dry run (-n), which negotiates differently under
# macOS's openrsync, always fails there. Instead, check that the key is accepted and the forced sender starts: it
# greets with its 4-byte protocol version. Whether the last pull worked is in deadline_backup.prom.
greet=$(ssh -F /dev/null -i "$C/id_ed25519" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 \
          -o UserKnownHostsFile="$C/known_hosts" -o StrictHostKeyChecking=yes "bkpull@$H" </dev/null 2>/dev/null | head -c 4 | wc -c | tr -d ' ')
if [ "$greet" = 4 ]; then
  say "  bkpull@$H: ok (key accepted, forced rsync sender answers)"; else say "  bkpull@$H: NO ANSWER (deadline side not installed yet, or key/address changed)"; rc=1; fi
exit $rc
