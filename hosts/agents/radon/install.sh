#!/bin/bash
# install.sh — lay down the "radon" agent profile (boblbee hosts/agents/radon). Idempotent; run by
# scripts/host-agents.sh, which decides from hosts/agent-assignments.txt whether this host gets it.
#
#   ./install.sh            install scripts to ~/bin, template + load the LaunchAgents
#   ./install.sh --check    report what is installed, differs, or is not running; change nothing
#   ./install.sh --no-load  install files but do not (re)load agents
#
# This profile owns the vault: the deploy key (restored from ark-config when missing), the ~/vault
# clone and its origin, the bare mirror aluminium pushes to, and the sync agent. radon's other jobs are installed by their own repos and
# are *verified* here, not managed: the XO agents by matdotcx/xo (recovery/install-*-job.sh),
# koboshelfd + cloudflared-kobo by KoboShelf (deploy/rebuild-host.sh). rmcd runs on helium, not
# here. If one of those is missing, --check fails and the nightly self-update log says which repo to re-run.
#
# The vault is fetched and pushed with ~/.ssh/id_vault_deploy only, which deadline pins to git-shell
# (LEDGER Gaps #5); the deadline-vault alias would offer the personal key first. A full rebuild:
# docs/radon-rebuild-runbook.md.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SHARED=("$REPO/scripts/lib/git-safe-sync.sh")   # shared with other hosts; installed into ~/bin like the profile scripts
# Each entry lists the acceptable labels for one service, "|"-separated (repos are moving to org.iaconelli.*).
EXTERNAL=("org.iaconelli.xo-push" "org.iaconelli.xo-dispatch" "org.iaconelli.xo-replies" "org.iaconelli.koboshelfd|cx.matdot.koboshelfd" "org.iaconelli.cloudflared-kobo|cx.matdot.cloudflared-kobo")
BIN="$HOME/bin"; AGENTS="$HOME/Library/LaunchAgents"; LOGS="$HOME/logs"
VAULT="$HOME/vault"; MIRROR="$HOME/vault-mirror.git"; ORIGIN="ops@hetzner.iaconelli.org:vault.git"
DKEY="$HOME/.ssh/id_vault_deploy"
SSHCMD='ssh -F /dev/null -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=~/.ssh/known_hosts -i ~/.ssh/id_vault_deploy'
ARK="${ARK_CONFIG_PATH:-$(dirname "$REPO")/ark-config}"; ESCROWED="$ARK/boblbee/hosts/radon/id_vault_deploy.age"
BOOTSTRAP_KEY="${BOBLBEE_BOOTSTRAP_KEY:-$HOME/.config/boblbee/id_bootstrap}"; AGE="$(command -v age || echo /opt/local/bin/age)"
CHECK=0; LOAD=1
case "${1:-}" in --check) CHECK=1;; --no-load) LOAD=0;; "") ;; *) sed -n '2,18p' "$0"; exit 1;; esac
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

say "== vault"
if [ -f "$DKEY" ]; then say "  deploy key: present"
elif [ $CHECK = 1 ]; then say "  deploy key: MISSING ($DKEY)"; rc=1
elif [ -f "$ESCROWED" ] && [ -f "$BOOTSTRAP_KEY" ]; then
  if ( umask 077; "$AGE" -d -i "$BOOTSTRAP_KEY" -o "$DKEY.tmp" "$ESCROWED" ) && mv -f "$DKEY.tmp" "$DKEY"; then
    cp "${ESCROWED%.age}.pub" "$DKEY.pub" 2>/dev/null; say "  deploy key: restored from ark-config"
  else rm -f "$DKEY.tmp"; say "  deploy key: FAILED to decrypt $ESCROWED"; rc=1; fi
else say "  deploy key: MISSING; seed id_bootstrap and re-run, or make a new one (docs/radon-rebuild-runbook.md)"; rc=1
fi
if [ -d "$VAULT/.git" ]; then
  if [ "$(git -C "$VAULT" remote get-url origin 2>/dev/null)" = "$ORIGIN" ] && [ "$(git -C "$VAULT" config core.sshCommand)" = "$SSHCMD" ]; then
    say "  ~/vault: clone, origin and deploy key set"
  elif [ $CHECK = 1 ]; then say "  ~/vault: origin or core.sshCommand DIFFERS"; rc=1
  else git -C "$VAULT" remote set-url origin "$ORIGIN" && git -C "$VAULT" config core.sshCommand "$SSHCMD" && say "  ~/vault: set origin and core.sshCommand"
  fi
elif [ -e "$VAULT" ]; then say "  ~/vault: EXISTS but isn't a git clone; left alone"; rc=1
elif [ $CHECK = 1 ]; then say "  ~/vault: MISSING"; rc=1
elif [ -f "$DKEY" ] && GIT_SSH_COMMAND="$SSHCMD" git clone -q "$ORIGIN" "$VAULT"; then
  git -C "$VAULT" config core.sshCommand "$SSHCMD"; say "  ~/vault: cloned"
else say "  ~/vault: FAILED to clone (no deploy key, or deadline unreachable)"; rc=1
fi
if git -C "$MIRROR" rev-parse --is-bare-repository >/dev/null 2>&1; then say "  ~/vault-mirror.git: bare repo"
elif [ -e "$MIRROR" ]; then say "  ~/vault-mirror.git: EXISTS but isn't a bare repo; left alone"; rc=1
elif [ $CHECK = 1 ]; then say "  ~/vault-mirror.git: MISSING (aluminium pushes here)"; rc=1
else
  git init -q --bare "$MIRROR" && say "  ~/vault-mirror.git: created"
  if [ -d "$VAULT/.git" ] && git -C "$VAULT" push -q "$MIRROR" "refs/remotes/origin/main:refs/heads/main" 2>/dev/null; then
    say "  ~/vault-mirror.git: seeded main from ~/vault"; fi
fi

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
if [ -d "$VAULT/.git" ] && git -C "$VAULT" ls-remote -q origin HEAD >/dev/null 2>&1; then say "  vault origin through the deploy key: ok"
else say "  vault origin through the deploy key: UNREACHABLE (key, deadline's authorized_keys, or known_hosts)"; rc=1; fi
exit $rc
