#!/bin/bash
# git-safe-sync.sh — serialised commit-and-push for a git working copy.
#
# Replaces the ad-hoc "git add / commit / push" tails that used to live inline
# in vault-sync.sh and xo/bin/xo-finalise.sh. Those raced each other and the
# scheduled Claude routines writing into the same repos, left stale index.lock
# files behind whenever a run was killed mid-write, and reported success when
# nothing had actually moved.
#
# Guarantees:
#   * one instance per repo at a time (portable mkdir mutex — no flock needed)
#   * genuinely stale git lock files are cleared; live ones are never touched
#   * always rebase onto upstream before pushing, so a diverged clone heals
#     instead of failing forever on non-fast-forward
#   * "pushed" is logged only when a ref actually moved
#   * real failures exit non-zero and are recorded, never swallowed
#
# Usage: git-safe-sync.sh --repo DIR --branch NAME [options]
#
#   --repo DIR          working copy                              (required)
#   --branch NAME       branch to sync                            (required)
#   --remote NAME       remote to fetch/push                      (default origin)
#   --message MSG       commit message for pending changes
#   --paths SPEC        pathspec to stage; repeatable  (default: everything)
#   --no-commit         push only; never create a commit
#   --no-push           commit only; never contact the remote
#   --log FILE          append log here
#   --stale-lock SECS   age at which a git lock is deemed stale   (default 900)
#   --mutex-stale SECS  age at which the mutex is deemed stale    (default 3600)
#
# Exit: 0 success or cleanly skipped; 1 usage error; 2 git failure.

set -uo pipefail

REPO="" BRANCH="" MESSAGE="" LOG_FILE="" REMOTE="origin"
DO_COMMIT=1 DO_PUSH=1
STALE_LOCK=900 MUTEX_STALE=3600
PATHS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)         REPO="${2:-}";        shift 2 ;;
        --branch)       BRANCH="${2:-}";      shift 2 ;;
        --remote)       REMOTE="${2:-}";      shift 2 ;;
        --message)      MESSAGE="${2:-}";     shift 2 ;;
        --paths)        PATHS+=("${2:-}");    shift 2 ;;
        --log)          LOG_FILE="${2:-}";    shift 2 ;;
        --stale-lock)   STALE_LOCK="${2:-}";  shift 2 ;;
        --mutex-stale)  MUTEX_STALE="${2:-}"; shift 2 ;;
        --no-commit)    DO_COMMIT=0;          shift ;;
        --no-push)      DO_PUSH=0;            shift ;;
        -h|--help)      sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "git-safe-sync: unknown argument: $1" >&2; exit 1 ;;
    esac
done

[ -n "$REPO" ]   || { echo "git-safe-sync: --repo is required" >&2; exit 1; }
[ -n "$BRANCH" ] || { echo "git-safe-sync: --branch is required" >&2; exit 1; }
[ -e "$REPO/.git" ] || { echo "git-safe-sync: $REPO is not a git working copy" >&2; exit 1; }  # .git may be a gitdir pointer file (aluminium vault)

# Use the real binary: an interactive `git` shell function (radon has one that
# runs ssh-add) can block forever on a passphrase prompt under launchd.
GIT=/usr/bin/git
[ -x "$GIT" ] || GIT=$(command -v git)
GITDIR=$(cd "$REPO" && "$GIT" rev-parse --absolute-git-dir 2>/dev/null || echo "$REPO/.git")

log() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') [$(basename "$REPO")] $*"
    if [ -n "$LOG_FILE" ]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        printf '%s\n' "$line" >> "$LOG_FILE"
    else
        printf '%s\n' "$line" >&2
    fi
}

# Seconds since a path was last modified. Prints a huge number if absent, so
# callers treat "missing" as "infinitely old" and never block on it.
age_of() {
    local p="$1" mtime now
    [ -e "$p" ] || { echo 999999999; return; }
    mtime=$(stat -f %m "$p" 2>/dev/null || stat -c %Y "$p" 2>/dev/null) || { echo 0; return; }
    now=$(date +%s)
    echo $(( now - mtime ))
}

# ---------------------------------------------------------------- mutex ----
# mkdir is atomic on every POSIX filesystem, which flock is not (absent on
# macOS) and shlock is not (absent on the Linux routine sandboxes).
MUTEX="$GITDIR/git-safe-sync.lock"

release_mutex() { [ -n "${MUTEX_HELD:-}" ] && rm -rf "$MUTEX"; }

acquire_mutex() {
    local holder
    if mkdir "$MUTEX" 2>/dev/null; then
        echo $$ > "$MUTEX/pid"; MUTEX_HELD=1; trap release_mutex EXIT; return 0
    fi
    holder=$(cat "$MUTEX/pid" 2>/dev/null || echo "")
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
        log "another sync (pid $holder) holds the mutex — skipping this run"
        return 1
    fi
    if [ "$(age_of "$MUTEX")" -lt "$MUTEX_STALE" ]; then
        log "mutex held by pid ${holder:-unknown} (not yet stale) — skipping this run"
        return 1
    fi
    log "WARNING: breaking stale mutex (pid ${holder:-unknown}, age $(age_of "$MUTEX")s)"
    rm -rf "$MUTEX"
    if mkdir "$MUTEX" 2>/dev/null; then
        echo $$ > "$MUTEX/pid"; MUTEX_HELD=1; trap release_mutex EXIT; return 0
    fi
    log "ERROR: could not acquire mutex after breaking a stale one"
    return 1
}

# ------------------------------------------------------- stale git locks ----
# The failure that motivated this script: a routine is killed between creating
# .git/index.lock and releasing it, and every later run dies on it forever.
# Only clear a lock that is old AND unopened by any live process.
clear_stale_git_locks() {
    local lock age
    for lock in "$GITDIR/index.lock" "$GITDIR/HEAD.lock" \
                "$GITDIR/config.lock" "$GITDIR/shallow.lock"; do
        [ -e "$lock" ] || continue
        age=$(age_of "$lock")
        if [ "$age" -lt "$STALE_LOCK" ]; then
            log "lock $(basename "$lock") is only ${age}s old — leaving it alone"
            continue
        fi
        if command -v lsof >/dev/null 2>&1 && lsof -- "$lock" >/dev/null 2>&1; then
            log "lock $(basename "$lock") is ${age}s old but still open — leaving it alone"
            continue
        fi
        log "clearing stale $(basename "$lock") (age ${age}s, no process holds it)"
        rm -f "$lock"
    done
}

# --------------------------------------------------------------- actions ----
do_commit() {
    local staged
    if [ "${#PATHS[@]}" -gt 0 ]; then
        "$GIT" add -A -- "${PATHS[@]}" || { log "ERROR: git add failed"; return 2; }
    else
        "$GIT" add -A || { log "ERROR: git add failed"; return 2; }
    fi
    if "$GIT" diff --cached --quiet; then
        log "nothing staged — no commit needed"
        return 0
    fi
    staged=$("$GIT" diff --cached --name-only | wc -l | tr -d ' ')
    if "$GIT" commit -q -m "${MESSAGE:-$(basename "$REPO") $(date '+%Y-%m-%d %H:%M')}"; then
        log "committed ${staged} file(s): $("$GIT" log --oneline -1)"
        return 0
    fi
    log "ERROR: git commit failed"
    return 2
}

do_push() {
    local before after
    if ! "$GIT" fetch -q "$REMOTE" "$BRANCH" 2>/dev/null; then
        log "ERROR: git fetch failed — remote unreachable"
        return 2
    fi
    before=$("$GIT" rev-parse "$REMOTE/$BRANCH" 2>/dev/null || echo none)

    # Heal divergence rather than failing on it forever.
    if [ -n "$("$GIT" log "$REMOTE/$BRANCH..HEAD" --oneline 2>/dev/null)" ] || \
       [ -n "$("$GIT" log "HEAD..$REMOTE/$BRANCH" --oneline 2>/dev/null)" ]; then
        if ! "$GIT" rebase --autostash "$REMOTE/$BRANCH" >/dev/null 2>&1; then
            "$GIT" rebase --abort 2>/dev/null
            log "ERROR: rebase onto $REMOTE/$BRANCH conflicted — aborted, needs a human"
            return 2
        fi
    fi

    if [ -z "$("$GIT" log "$REMOTE/$BRANCH..HEAD" --oneline 2>/dev/null)" ]; then
        log "no local commits to push"
        return 0
    fi

    if ! "$GIT" push -q "$REMOTE" "$BRANCH" 2>/dev/null; then
        log "push rejected — refetching and retrying once"
        "$GIT" fetch -q "$REMOTE" "$BRANCH" 2>/dev/null
        if ! "$GIT" rebase --autostash "$REMOTE/$BRANCH" >/dev/null 2>&1; then
            "$GIT" rebase --abort 2>/dev/null
            log "ERROR: rebase conflicted on retry — aborted, needs a human"
            return 2
        fi
        if ! "$GIT" push -q "$REMOTE" "$BRANCH" 2>/dev/null; then
            log "ERROR: git push failed after retry"
            return 2
        fi
    fi

    after=$("$GIT" rev-parse "$REMOTE/$BRANCH" 2>/dev/null || echo none)
    if [ "$before" != "$after" ]; then
        log "pushed ${before:0:8}..${after:0:8} -> $REMOTE/$BRANCH"
    else
        # The old vault-sync.sh logged "pushed" here every 10 minutes while
        # actually moving nothing. Never claim a push that did not happen.
        log "push reported success but $REMOTE/$BRANCH did not move"
    fi
    return 0
}

# ------------------------------------------------------------------ main ----
cd "$REPO" || { echo "git-safe-sync: cannot cd to $REPO" >&2; exit 1; }

acquire_mutex || exit 0
clear_stale_git_locks

RC=0
if [ "$DO_COMMIT" -eq 1 ]; then
    do_commit || RC=$?
fi
if [ "$DO_PUSH" -eq 1 ] && [ "$RC" -eq 0 ]; then
    do_push || RC=$?
fi

[ "$RC" -ne 0 ] && log "FAILED (rc=$RC)"
exit "$RC"
