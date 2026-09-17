#!/bin/bash
# downloads-sweep — weekly sweep of ~/Downloads and iCloud Drive/Downloads (plan decision 24 + R7).
#
# Runs from a LaunchAgent every hour and at login/wake; does real work only when the last successful
# sweep is >= 7 days old (anacron pattern). Files untouched for >= AGE_DAYS are triaged:
#   installers / disk images  -> Trash
#   everything else           -> cobalt:/Volumes/XRAID/Data/Archive/Downloads/<YYYY>/<Www>/<inbox>/  (rsync over ssh, verified)
# A manifest (name, size, md5, destination) is written locally and beside the files on the NAS.
# If cobalt is unreachable when a sweep is due, a notification asks you to get it online and run `sweep-now`;
# the hourly tick retries on its own. Modes: SWEEP_MODE=dry-run (default for the first weeks) | apply.
set -u
MODE="${SWEEP_MODE:-dry-run}"; [ "${1:-}" = "--apply" ] && MODE=apply; [ "${1:-}" = "--dry-run" ] && MODE=dry-run
FORCE=0; [ "${1:-}" = "--force" ] || [ "${2:-}" = "--force" ] && FORCE=1
AGE_DAYS="${SWEEP_AGE_DAYS:-14}"; PERIOD_DAYS=7
HOST="cobalt"; NAS_ROOT="/Volumes/XRAID/Data/Archive/Downloads"
INBOXES=("$HOME/Downloads" "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Downloads")
STATE="$HOME/.local/state/downloads-sweep"; STAMP="$STATE/last-success"; NAG="$STATE/last-nag"
LOGDIR="$HOME/logs"; LOG="$LOGDIR/downloads-sweep.log"; TRASH="$HOME/.Trash/downloads-sweep-$(date +%F)"
mkdir -p "$STATE" "$LOGDIR"
log(){ echo "$(date '+%F %T') [$MODE] $*" | tee -a "$LOG"; }
notify(){ osascript -e "display notification \"$2\" with title \"Downloads sweep\" subtitle \"$1\"" >/dev/null 2>&1 || true; }
days_since(){ [ -f "$1" ] && echo $(( ( $(date +%s) - $(stat -f %m "$1") ) / 86400 )) || echo 9999; }

# 1. due?
since=$(days_since "$STAMP")
if [ "$FORCE" = 0 ] && [ "$since" -lt "$PERIOD_DAYS" ]; then exit 0; fi   # quiet: not due
log "sweep due (last success ${since}d ago); age threshold ${AGE_DAYS}d"

# 2. cobalt reachable? (ssh, 8 s) — otherwise nag at most once a day and retry next tick
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$HOST" "test -d '$NAS_ROOT' || mkdir -p '$NAS_ROOT'" 2>>"$LOG"; then
  if [ "$(days_since "$NAG")" -ge 1 ]; then
    notify "cobalt unreachable" "Sweep is ${since} days overdue. Get cobalt online, then run sweep-now (or wait for the hourly retry)."; touch "$NAG"
  fi
  log "cobalt unreachable; will retry"; exit 2
fi

# 3. collect candidates
year=$(date +%Y); week=$(date +W%V); manifest="$STATE/manifest-$(date +%F-%H%M).csv"
echo "inbox,relpath,bytes,md5,action,destination" > "$manifest"
moved=0; trashed=0; skipped=0; bytes=0
is_installer(){ case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in *.dmg|*.pkg|*.ipsw|*.iso|*.img|*.img.xz|*.img.gz|*.mpkg) return 0;; esac; return 1; }
for inbox in "${INBOXES[@]}"; do
  [ -d "$inbox" ] || continue
  label=$([ "$inbox" = "$HOME/Downloads" ] && echo local || echo icloud)
  while IFS= read -r -d '' f; do
    rel="${f#$inbox/}"
    case "$rel" in .DS_Store|.localized|*.download|*.download/*|*.part|*.crdownload|*.icloud) skipped=$((skipped+1)); continue;; esac
    if lsof -t -- "$f" >/dev/null 2>&1; then log "skip (open): $rel"; skipped=$((skipped+1)); continue; fi
    sz=$(stat -f %z "$f"); sum=$(md5 -q "$f" 2>/dev/null || echo "-")
    if is_installer "$rel"; then
      echo "$label,\"$rel\",$sz,$sum,trash," >> "$manifest"
      log "trash  $((sz/1000000)) MB  $label/$rel"
      if [ "$MODE" = apply ]; then mkdir -p "$TRASH/$label/$(dirname "$rel")"; mv "$f" "$TRASH/$label/$rel"; fi
      trashed=$((trashed+1))
    else
      dest="$NAS_ROOT/$year/$week/$label"
      echo "$label,\"$rel\",$sz,$sum,archive,$dest" >> "$manifest"
      log "archive $((sz/1000000)) MB  $label/$rel -> $HOST:$dest/"
      if [ "$MODE" = apply ]; then
        if rsync -Rt --partial "$inbox/./$rel" "$HOST:$dest/" 2>>"$LOG" && \
           [ -z "$(rsync -Rtc -n --out-format='%n' "$inbox/./$rel" "$HOST:$dest/" 2>>"$LOG" | grep -v '/$')" ]; then
          rm -f "$f"; bytes=$((bytes+sz)); moved=$((moved+1))
        else log "  VERIFY FAILED, kept: $rel"; fi
      else moved=$((moved+1)); bytes=$((bytes+sz)); fi
    fi
  done < <(find "$inbox" -mindepth 1 -type f -mtime "+$((AGE_DAYS-1))" -print0 2>/dev/null)
  # remove now-empty subfolders (never the inbox itself)
  [ "$MODE" = apply ] && find "$inbox" -mindepth 1 -depth -type d -empty -delete 2>/dev/null
done

# 4. manifest to the NAS bucket, stamp, notify
if [ "$MODE" = apply ]; then
  ssh -o BatchMode=yes "$HOST" "mkdir -p '$NAS_ROOT/$year/$week'" && scp -q "$manifest" "$HOST:$NAS_ROOT/$year/$week/manifest-$(date +%F-%H%M).csv"
  touch "$STAMP"
  notify "done" "$moved archived ($((bytes/1000000)) MB), $trashed installers trashed, $skipped skipped."
else
  touch "$STAMP"   # keep the weekly cadence in dry-run too, so it does not nag every hour
  notify "dry run" "Would archive $moved ($((bytes/1000000)) MB) and trash $trashed. See $LOG."
fi
log "end: archived=$moved (${bytes} bytes) trashed=$trashed skipped=$skipped manifest=$manifest"
