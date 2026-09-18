#!/bin/bash
# log-trim.sh — keep launchd job logs from growing without bound (boblbee hosts/agents/logtrim).
#
# launchd's StandardOutPath/StandardErrorPath files are append-only and never rotated, so a crash
# loop or a chatty job can leave a multi-hundred-MB log behind (helium: 915 MB node-exporter.log,
# 415 MB port-forward.log, Sep 2026). Weekly, for every *.log / *.err under ~/logs and
# ~/Library/Logs larger than LIMIT, keep only the last KEEP bytes. Writers hold the file with
# O_APPEND, so truncate-and-rewrite in place is safe; nothing is renamed and no descriptor breaks.
#
#   LOG_TRIM_LIMIT   bytes above which a file is trimmed (default 50 MB)
#   LOG_TRIM_KEEP    bytes retained from the tail          (default 10 MB)
#   log-trim.sh --dry-run   report only
set -u
LIMIT=${LOG_TRIM_LIMIT:-52428800}; KEEP=${LOG_TRIM_KEEP:-10485760}
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
REPORT="$HOME/logs/log-trim.log"; mkdir -p "$HOME/logs"
stamp(){ date '+%Y-%m-%d %H:%M:%S'; }
trimmed=0
for dir in "$HOME/logs" "$HOME/Library/Logs"; do
  [ -d "$dir" ] || continue
  while IFS= read -r -d '' f; do
    case "$f" in "$REPORT") continue;; esac
    size=$(stat -f %z "$f" 2>/dev/null || stat -c %s "$f" 2>/dev/null || echo 0)
    [ "$size" -gt "$LIMIT" ] || continue
    if [ $DRY = 1 ]; then echo "would trim $f ($size bytes)"; continue; fi
    tmp=$(mktemp) && tail -c "$KEEP" "$f" > "$tmp" && cat "$tmp" > "$f"; rm -f "$tmp"
    echo "$(stamp) trimmed $f: $size -> $(stat -f %z "$f" 2>/dev/null || stat -c %s "$f") bytes" >> "$REPORT"
    trimmed=$((trimmed+1))
  done < <(find "$dir" -maxdepth 1 -type f \( -name '*.log' -o -name '*.err' \) -print0 2>/dev/null)
done
[ $DRY = 1 ] || echo "$(stamp) run complete: $trimmed file(s) trimmed" >> "$REPORT"
