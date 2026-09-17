#!/bin/bash
# install.sh — lay down the "aluminium" agent profile (boblbee hosts/agents/aluminium). Idempotent; run by
# scripts/host-agents.sh, which decides from hosts/agent-assignments.txt whether this host gets it.
#
#   ./install.sh            install scripts to ~/bin, template + load the LaunchAgents
#   ./install.sh --check    report what is installed, differs, or is not running; change nothing
#   ./install.sh --no-load  install files but do not (re)load agents
#
# Requires: ssh config aliases `deadline`, `radon`, `cobalt` (boblbee's ssh-sync provides them),
# and Full Disk Access for /bin/zsh (xo-mirror and vault-sync write inside the iCloud Obsidian container).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SHARED=("$REPO/scripts/lib/git-safe-sync.sh")   # shared with other hosts; installed into ~/bin like the profile scripts
BIN="$HOME/bin"; AGENTS="$HOME/Library/LaunchAgents"; LOGS="$HOME/logs"
CHECK=0; LOAD=1
case "${1:-}" in --check) CHECK=1;; --no-load) LOAD=0;; "") ;; *) sed -n '2,10p' "$0"; exit 1;; esac
uid=$(id -u); rc=0
say(){ printf '%s\n' "$*"; }

say "== scripts -> $BIN"
mkdir -p "$BIN" "$LOGS" "$HOME/.local/state/downloads-sweep"
for f in "$HERE"/bin/* "${SHARED[@]}"; do
  b=$(basename "$f")
  if [ -f "$BIN/$b" ] && cmp -s "$f" "$BIN/$b"; then say "  same     $b"; continue; fi
  if [ $CHECK = 1 ]; then say "  DIFFERS  $b"; rc=1; continue; fi
  install -m 755 "$f" "$BIN/$b" && say "  installed $b"
done

say "== LaunchAgents -> $AGENTS"
mkdir -p "$AGENTS"
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
    else
      say "  running  $label"
    fi
  fi
done

say "== prerequisites"
for h in deadline radon cobalt; do
  if ssh -o BatchMode=yes -o ConnectTimeout=6 "$h" true 2>/dev/null; then say "  ssh $h: ok"; else say "  ssh $h: UNREACHABLE (check ~/.ssh/config and keys)"; fi
done
V="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Zettelkasten"
if [ -e "$V/.git" ] && [ -d "$HOME/.vault.git" ]; then say "  vault git: attached ($HOME/.vault.git)"; else say "  vault git: NOT attached — see README 'Re-attaching the vault'"; rc=1; fi
say "  Full Disk Access: grant to /bin/zsh (System Settings > Privacy & Security) — cannot be checked from here"
say "  downloads-sweep mode: $(plutil -extract EnvironmentVariables.SWEEP_MODE raw -o - "$AGENTS/org.iaconelli.downloads-sweep.plist" 2>/dev/null || echo '?')"
exit $rc
