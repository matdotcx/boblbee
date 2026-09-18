#!/bin/zsh
# radon: keep ~/vault (a normal clone of deadline:vault.git) in step with deadline; commit anything
# written here by the XO routines or by hand, rebase, push. Runs every 10 minutes from
# org.iaconelli.vault-sync (boblbee hosts/agents/radon).
#
# The commit/push mechanics live in git-safe-sync.sh (boblbee scripts/lib, installed to ~/bin),
# which serialises against the routines writing into the same clone, clears genuinely stale .git
# locks, and rebases before pushing. This script used to inline all of that and hid a 22-hour
# outage (a failed `git add` on a stale index.lock was ignored and the trailing `git push && echo
# pushed` logged success every 10 minutes while pushing nothing).

VAULT="$HOME/vault"
LOG="$HOME/logs/vault-sync.log"
CONFLICTS="$VAULT/System/Sync Conflicts.md"

mkdir -p "$HOME/logs"

"$HOME/bin/git-safe-sync.sh" \
    --repo "$VAULT" \
    --branch main \
    --message "radon $(date '+%Y-%m-%d %H:%M')" \
    --log "$LOG"
rc=$?

if [ $rc -ne 0 ]; then
    # A real failure surfaces instead of being swallowed. Record it where the vault owner will
    # see it, but never touch anything under .git.
    printf -- '- %s vault-sync failed (rc=%s) on radon: run `git -C ~/vault status` and see %s\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$rc" "$LOG" >> "$CONFLICTS"
fi

exit $rc
