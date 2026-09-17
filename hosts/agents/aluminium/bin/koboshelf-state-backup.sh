#!/bin/bash
# koboshelf-state-backup — nightly copy of KoboShelf's local state (annotations, reading positions, ReadingStatus,
# DeviceBackups) into the Calibre library's backup folder, which iCloud carries. Without this the reading state exists
# only on this Mac. Keeps 14 dated snapshots via hard-linked rsync (cheap: unchanged files share blocks).
set -u
SRC="$HOME/Library/Application Support/KoboShelf"
DST="$HOME/Documents/Calibre Library/.koboshelf-backups/state"
LOG="$HOME/logs/koboshelf-state-backup.log"
KEEP=14
mkdir -p "$DST" "$HOME/logs"
[ -d "$SRC" ] || { echo "$(date '+%F %T') no KoboShelf state at $SRC" >> "$LOG"; exit 0; }
today="$DST/$(date +%F)"; latest="$DST/latest"
if [ -d "$latest" ]; then rsync -a --delete --link-dest="$latest" "$SRC/" "$today/"; else rsync -a --delete "$SRC/" "$today/"; fi
rc=$?
if [ $rc -eq 0 ]; then rm -f "$latest"; ln -s "$today" "$latest"; fi
# prune
ls -1d "$DST"/20??-??-?? 2>/dev/null | sort | awk -v k="$KEEP" '{a[NR]=$0} END{for(i=1;i<=NR-k;i++) print a[i]}' | while read -r old; do rm -rf "$old"; done
echo "$(date '+%F %T') rc=$rc snapshot=$(basename "$today") size=$(du -sh "$today" 2>/dev/null | cut -f1)" >> "$LOG"
exit $rc
