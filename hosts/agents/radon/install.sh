#!/bin/bash
# install.sh — lay down the "radon" agent profile (boblbee hosts/agents/radon). Idempotent; run by
# scripts/host-agents.sh, which decides from hosts/agent-assignments.txt whether this host gets it.
#
#   ./install.sh            install scripts to ~/bin, template + load the LaunchAgents
#   ./install.sh --check    report what is installed, differs, or is not running; change nothing
#   ./install.sh --no-load  install files but do not (re)load agents
#
# This profile owns only the vault sync. radon's other jobs are installed by their own repos and
# are *verified* here, not managed: the XO agents by matdotcx/xo (recovery/install-*-job.sh),
# koboshelfd + cloudflared-kobo by KoboShelf's installer, rmcd by matdotcx/rmc. If one of those is
# missing, --check fails and the nightly self-update log says which repo to re-run.
#
# Requires: ssh alias `deadline-vault` (the vault's origin) and a normal clone at ~/vault.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SHARED=("$REPO/scripts/lib/git-safe-sync.sh")   # shared with other hosts; installed into ~/bin like the profile scripts
# Each entry lists the acceptable labels for one service, "|"-separated (repos are moving to org.iaconelli.*).
EXTERNAL=("org.iaconelli.xo-push" "org.iaconelli.xo-dispatch" "org.iaconelli.xo-replies" "org.iaconelli.koboshelfd|cx.matdot.koboshelfd" "org.iaconelli.cloudflared-kobo|cx.matdot.cloudflared-kobo" "org.iaconelli.rmcd|cx.mat.rmcd")
BIN="$HOME/bin"; AGENTS="$HOME/Library/LaunchAgents"; LOGS="$HOME/logs"
CHECK=0; LOAD=1
case "${1:-}" in --check) CHECK=1;; --no-load) LOAD=0;; "") ;; *) sed -n '2,14p' "$0"; exit 1;; esac
uid=$(id -u); rc=0
say(){ printf '%s\n' "$*"; }

say "== scripts -> $BIN"
mkdir -p "$BIN" "$LOGS"
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

say "== agents owned by other repos (verified only)"
for entry in "${EXTERNAL[@]}"; do
  found=""
  IFS="|" read -r -a alts <<< "$entry"
  for label in "${alts[@]}"; do launchctl print "gui/$uid/$label" >/dev/null 2>&1 && { found="$label"; break; }; done
  if [ -n "$found" ]; then say "  loaded   $found"; else say "  MISSING  ${alts[0]} (re-run its repo's installer)"; rc=1; fi
done

say "== prerequisites"
if ssh -o BatchMode=yes -o ConnectTimeout=6 deadline-vault true 2>/dev/null; then say "  ssh deadline-vault: ok"; else say "  ssh deadline-vault: UNREACHABLE (check ~/.ssh/config and keys)"; rc=1; fi
if [ -d "$HOME/vault/.git" ] && git -C "$HOME/vault" remote get-url origin >/dev/null 2>&1; then say "  ~/vault: git clone, origin $(git -C "$HOME/vault" remote get-url origin)"; else say "  ~/vault: NOT a git clone with an origin"; rc=1; fi
exit $rc
