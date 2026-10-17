#!/bin/bash
#########################################################
# Title: rebuild-radon
# Description: The scripted half of docs/radon-rebuild-runbook.md. Puts radon's per-user setup back
#   after its home folder is lost, in order. Each step skips what's already done; nothing is
#   deleted, and it never types a password, passphrase or token: those steps are listed at the end
#   for you to do.
#
#   scripts/rebuild-radon.sh           run every step
#   scripts/rebuild-radon.sh --check   report each step's state; change nothing
#
#   Needs first (runbook §3): iCloud Drive signed in, Tailscale up, `gh auth login`, and this repo
#   at ~/Developer/workspace/matdotcx/boblbee. Seed ~/.config/boblbee/id_bootstrap from the vault
#   so the escrowed secrets (vault deploy key, Kobo token, tunnel) come back; without it those steps
#   say what's missing.
# Source: https://github.com/matdotcx/boblbee
#########################################################
set -u

MODE=${1:-}
case "$MODE" in ""|--check) ;; *) sed -n '3,16p' "$0"; exit 2 ;; esac
CHECK=0; [ "$MODE" = --check ] && CHECK=1

BOBLBEE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$(dirname "$BOBLBEE")"
ICLOUD_SSH="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ark/Sync/System/.ssh"
BOOTSTRAP_KEY="${BOBLBEE_BOOTSTRAP_KEY:-$HOME/.config/boblbee/id_bootstrap}"
# The repos radon runs things from. Everything else in matdotcx/* can be cloned when it's needed.
REPOS=(ark-config xenon observability xo imap-mcp KoboShelf)
# The user-level boblbee modules index.sh would run. The sudo ones (hostname, Touch ID, MacPorts,
# PAM, dots.sh) set things outside the home folder, which a lost home folder doesn't take with it.
MODULES=(git-config-shared.sh zshrc-sync.sh tmux-sync.sh ghostty-sync.sh zed-sync.sh motd-sync.sh claude-sync.sh observability-collector.sh)
FLEET=(helium cobalt hydrogen krypton nickel pf-edge deadline)

TODO=()
todo() { TODO+=("$*"); }
step() { printf '\n── %s\n' "$*"; }
say()  { printf '  %s\n' "$*"; }

step "1. preflight"
[ "$(scutil --get LocalHostName 2>/dev/null)" = radon ] && say "host: radon" || say "host: $(scutil --get LocalHostName 2>/dev/null) (this script is for radon; going on)"
gh auth status >/dev/null 2>&1 && say "gh: signed in" || { say "gh: NOT signed in"; todo "gh auth login --hostname github.com --git-protocol ssh --web"; }
[ -d "$ICLOUD_SSH" ] && say "iCloud SSH folder: present" || { say "iCloud SSH folder: MISSING"; todo "Sign in to iCloud Drive and wait for Ark/Sync/System to download, then re-run"; }
command -v age >/dev/null && say "age: $(command -v age)" || { say "age: MISSING"; todo "sudo port install age"; }
command -v cloudflared >/dev/null && say "cloudflared: $(command -v cloudflared)" || { say "cloudflared: MISSING"; todo "sudo port install cloudflared"; }
if [ -f "$BOOTSTRAP_KEY" ]; then say "id_bootstrap: present"
else say "id_bootstrap: absent (escrowed secrets can't be restored)"
     todo "Seed id_bootstrap from the vault: install -m 600 <file> \"$BOOTSTRAP_KEY\" (or set AGE_IDENTITY to the paper key for KoboShelf), then re-run"; fi

step "2. SSH"
if [ $CHECK = 1 ]; then
    for k in id_rsa id_ed25519 id_github; do [ -f "$HOME/.ssh/$k" ] && say "~/.ssh/$k: present" || say "~/.ssh/$k: MISSING"; done
else
    "$BOBLBEE/scripts/ssh-sync.sh" </dev/null 2>&1 | grep -E '✓|✗|Copied|Updated|pulled' | sed 's/\x1b\[[0-9;]*m//g; s/^/  /'
fi
# ssh-sync leaves known_hosts alone once ~/.ssh exists, so add iCloud's entries that are missing.
if [ -f "$ICLOUD_SSH/known_hosts" ]; then
    missing=$(grep -vxFf "$HOME/.ssh/known_hosts" "$ICLOUD_SSH/known_hosts" 2>/dev/null | grep -c . || true)
    [ -f "$HOME/.ssh/known_hosts" ] || missing=$(grep -c . "$ICLOUD_SSH/known_hosts")
    if [ "$missing" = 0 ]; then say "known_hosts: has every iCloud entry"
    elif [ $CHECK = 1 ]; then say "known_hosts: $missing iCloud entries missing"
    else
        tmp=$(mktemp "${TMPDIR:-/tmp}/known_hosts.XXXXXX")
        cat "$HOME/.ssh/known_hosts" "$ICLOUD_SSH/known_hosts" 2>/dev/null | awk 'NF && !seen[$0]++' > "$tmp"
        cat "$tmp" > "$HOME/.ssh/known_hosts"; rm -f "$tmp"; chmod 644 "$HOME/.ssh/known_hosts"
        say "known_hosts: added $missing entries from iCloud"
    fi
fi
loaded=0; ssh-add -l >/dev/null 2>&1 && loaded=$(ssh-add -l | grep -c .)
say "keys in the agent: $loaded"
[ "$loaded" -ge 1 ] || todo "Unlock the SSH keys once, typing each passphrase: ssh-add --apple-use-keychain ~/.ssh/id_rsa ~/.ssh/id_github ~/.ssh/id_ed25519"

step "3. repos in $WS"
for r in "${REPOS[@]}"; do
    if [ -d "$WS/$r/.git" ]; then say "same     $r"
    elif [ $CHECK = 1 ]; then say "MISSING  $r"
    elif git clone -q "git@github.com:matdotcx/$r.git" "$WS/$r" 2>/dev/null; then say "cloned   $r"
    else say "FAILED   $r (SSH to GitHub? see step 2)"; fi
done

step "4. boblbee modules"
if [ -z "$(git config --global user.email)" ]; then
    say "git identity: not set"
    todo "git config --global user.name 'Diego Iaconelli' && git config --global user.email diego@iaconelli.org, then re-run"
else say "git identity: $(git config --global user.name) <$(git config --global user.email)>"; fi
for m in "${MODULES[@]}"; do
    if [ $CHECK = 1 ]; then say "would run $m"; continue; fi
    # claude-sync keeps whichever settings.json is newer and pushes it to gold. If Claude Code wrote
    # a fresh one after boblbee was cloned, that bare default would replace the curated copy.
    if [ "$m" = claude-sync.sh ] && [ -f "$HOME/.claude/settings.json" ] \
        && ! cmp -s "$HOME/.claude/settings.json" "$BOBLBEE/assets/claude-settings.json" \
        && [ "$HOME/.claude/settings.json" -nt "$BOBLBEE/assets/claude-settings.json" ]; then
        say "skipped  claude-sync.sh (the local settings.json is newer and differs)"
        todo "Claude settings: check ~/.claude/settings.json against boblbee/assets/claude-settings.json; to take boblbee's, move the local one aside and run boblbee/scripts/claude-sync.sh"
        continue
    fi
    if (cd "$BOBLBEE/scripts" && "./$m" </dev/null >/dev/null 2>&1); then say "ran      $m"; else say "FAILED   $m (run it by hand to see why)"; fi
done
todo "boblbee/scripts/dots.sh at the Mac: Finder, Dock and clock preferences (it also uses sudo for update policy and time settings)"

step "5. xo's push job"
# Before host-agents: both install ~/bin/git-safe-sync.sh, and boblbee's copy (a superset) must win.
if [ $CHECK = 1 ]; then launchctl print "gui/$(id -u)/org.iaconelli.xo-push" >/dev/null 2>&1 && say "xo-push: loaded" || say "xo-push: NOT loaded"
elif [ -x "$WS/xo/recovery/install-push-job.sh" ]; then
    "$WS/xo/recovery/install-push-job.sh" </dev/null 2>&1 | grep -E '✓|✗' | sed 's/^ */  /'
else say "xo isn't cloned (step 3)"; fi
todo "xo at the Mac: xo/recovery/bootstrap-mac.sh (IMAP and Slack passwords), quit and reopen Claude Desktop, recreate the /xo Routine (daily 08:00, folder xo), then xo/recovery/install-replies-job.sh and install-dispatch-job.sh; re-approve the routines' tools on their first runs"

step "6. boblbee host agents and self-update"
if [ $CHECK = 1 ]; then
    "$BOBLBEE/scripts/host-agents.sh" --check 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'MISSING|DIFFERS|NOT-LOADED|FAILED|UNREACHABLE|OK|ERROR' | sed 's/^ */  /'
else
    "$BOBLBEE/scripts/host-agents.sh" </dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '\[(OK|ERROR)\]|restored|cloned|created|seeded|MISSING|FAILED' | sed 's/^ */  /'
    (cd "$BOBLBEE/scripts" && ./self-update.sh --install </dev/null >/dev/null 2>&1) && say "self-update: installed" || say "self-update: FAILED"
fi

step "7. KoboShelf"
K="$WS/KoboShelf"
if [ ! -d "$K/deploy" ]; then say "KoboShelf isn't cloned (step 3)"
elif [ $CHECK = 1 ]; then
    launchctl print "gui/$(id -u)/org.iaconelli.koboshelfd" >/dev/null 2>&1 && say "koboshelfd: loaded" || say "koboshelfd: NOT loaded"
    "$K/deploy/escrow-secrets.sh" --check 2>&1 | sed 's/^/  /'
elif [ -s "$HOME/.koboshelf-token" ] || [ -f "$BOOTSTRAP_KEY" ] || [ -n "${AGE_IDENTITY:-}" ]; then
    "$K/deploy/rebuild-host.sh" 2>&1 | grep -E '^──|✓|✗|restored|DIFFERS' | sed 's/^/  /'
else
    say "skipped: no token here and no key to restore the escrowed one"
    todo "KoboShelf: seed id_bootstrap and re-run, or NEW_TOKEN=1 POINT_KOBO=1 KoboShelf/deploy/rebuild-host.sh with the Kobo plugged in (a new token means re-pointing it)"
fi

step "8. verify"
for h in "${FLEET[@]}"; do
    if ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes "$h" true </dev/null >/dev/null 2>&1; then say "ssh $h: ok"
    else say "ssh $h: FAILED"; fi
done
todo "If macOS asks, allow the new background items (System Settings > General > Login Items & Extensions)"
todo "GPG signing: install gnupg2, import the key, boblbee/scripts/setup-gpg-signing.sh diego@iaconelli.org"

printf '\n── For you to do\n'
for t in "${TODO[@]}"; do printf '  - %s\n' "$t"; done
