#!/bin/zsh
# aluminium: sync the Obsidian vault (iCloud working tree, git dir in ~/.vault.git) with deadline (primary) and radon (mirror).
# Commit/rebase/push mechanics live in git-safe-sync.sh (mutex, stale-lock cleanup, honest "pushed" logging) — the same
# script radon uses. The previous inline version logged "pushed" every 10 minutes even when nothing moved.
VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Zettelkasten"
LOG="$HOME/logs/vault-sync.log"
CONFLICTS="$VAULT/System/Sync Conflicts.md"
mkdir -p "$HOME/logs"

"$HOME/bin/git-safe-sync.sh" --repo "$VAULT" --branch main --remote deadline --message "aluminium $(date '+%Y-%m-%d %H:%M')" --log "$LOG"
rc=$?
if [ $rc -ne 0 ]; then
  printf -- '- %s vault-sync failed (rc=%s) on aluminium: run `git -C "%s" status` and see %s\n' "$(date '+%Y-%m-%d %H:%M')" "$rc" "$VAULT" "$LOG" >> "$CONFLICTS"
  exit $rc
fi
# mirror to radon; only log when a ref actually moved
before=$(/usr/bin/git -C "$VAULT" rev-parse -q --verify refs/remotes/radon/main 2>/dev/null || echo none)
if /usr/bin/git -C "$VAULT" push -q radon main 2>>"$LOG"; then
  after=$(/usr/bin/git -C "$VAULT" rev-parse -q --verify refs/remotes/radon/main 2>/dev/null || echo none)
  [ "$before" != "$after" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') [Zettelkasten] pushed radon ($after)" >> "$LOG"
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') [Zettelkasten] radon push failed" >> "$LOG"
fi
exit 0
