#!/bin/bash
# deadline-backup-pull.sh — copy deadline's nightly backup to this host (boblbee hosts/agents/deadline-backup).
# Runs on cobalt at 06:30, after deadline's own job (02:30 UTC) has refreshed /var/backups/deadline;
# Backblaze on cobalt takes ~/backups offsite from here.
#
# deadline's user bkpull accepts only ~/.config/deadline-backup/id_ed25519, only from cobalt's tailnet
# address, forced to one read-only rsync sender for /var/backups/deadline. deadline's host key is pinned
# in ~/.config/deadline-backup/known_hosts. deadline's side: xenon chores/scripts/deadline-backup/install.sh.
#
# Each run writes ~/backups/deadline/YYYY-MM-DD_HHMMSS/, hard-linked against the previous copy (only what
# changed costs space), and repoints latest. Keeps KEEP_DAYS, never fewer than the newest 3. The state and
# vault files are age-encrypted on deadline; media/ is the site's public images.
#
#   DEADLINE_BACKUP_HOST        deadline's tailnet address  (default 100.77.139.21)
#   DEADLINE_BACKUP_DEST        local directory             (default ~/backups/deadline)
#   DEADLINE_BACKUP_KEEP_DAYS   prune copies older than     (default 30)
#   DEADLINE_BACKUP_MAX_AGE_H   fail if deadline's newest backup is older than this many hours (default 36)
#
# Writes deadline_backup.prom to the Prometheus textfile directory so observability can alert on it.
set -u
HOST=${DEADLINE_BACKUP_HOST:-100.77.139.21}
DEST=${DEADLINE_BACKUP_DEST:-$HOME/backups/deadline}
KEEP_DAYS=${DEADLINE_BACKUP_KEEP_DAYS:-30}; MAX_AGE_H=${DEADLINE_BACKUP_MAX_AGE_H:-36}
CFG="$HOME/.config/deadline-backup"
LOG="$HOME/logs/deadline-backup-pull.log"
PROM_DIR="$HOME/.local/share/prometheus/textfile"
mkdir -p "$DEST" "$HOME/logs" "$PROM_DIR"
log(){ printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

STAMP=$(date '+%Y-%m-%d_%H%M%S')
LINK_DEST=""; [ -d "$DEST/latest/" ] && LINK_DEST="--link-dest=../latest"
rsync -rlt $LINK_DEST \
  -e "ssh -F /dev/null -i $CFG/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=20 -o UserKnownHostsFile=$CFG/known_hosts -o StrictHostKeyChecking=yes" \
  "bkpull@$HOST:./" "$DEST/$STAMP.partial/" 2>>"$LOG"
pull_rc=$?

pruned=0
if [ $pull_rc -eq 0 ]; then
  mv "$DEST/$STAMP.partial" "$DEST/$STAMP" && ln -sfn "$STAMP" "$DEST/latest"
  find "$DEST" -maxdepth 1 -type d -name '*.partial' -exec rm -rf {} +
  # Newest first; past the newest 3, drop copies dated before the cutoff (the name carries the date).
  cutoff=$(date -v-"${KEEP_DAYS}"d '+%Y-%m-%d'); i=0
  while IFS= read -r d; do
    i=$((i + 1)); [ $i -le 3 ] && continue
    n=$(basename "$d"); if [[ "${n%%_*}" < "$cutoff" ]]; then rm -rf "$d" && pruned=$((pruned + 1)); fi
  done < <(find "$DEST" -maxdepth 1 -type d -name '20??-??-??_??????' | sort -r)
fi

# Health comes from the newest complete copy: deadline's own STATUS, and the age of its newest state file
# (rsync -t keeps deadline's modification time).
now=$(date +%s); newest_ts=0; remote_ok=0; copies=0; bytes=0
newest=$(ls -t "$DEST"/latest/state-*.tar.gz.age 2>/dev/null | head -1)
[ -n "$newest" ] && newest_ts=$(stat -f %m "$newest")
grep -qx 'result=ok' "$DEST/latest/STATUS" 2>/dev/null && remote_ok=1
copies=$(find "$DEST" -maxdepth 1 -type d -name '20??-??-??_??????' | wc -l | tr -d ' ')
[ -d "$DEST/latest/" ] && bytes=$(( $(du -sk "$DEST/latest/" | cut -f1) * 1024 ))
age_h=$(( (now - newest_ts) / 3600 ))

ok=1; status="ok"
if [ $pull_rc -ne 0 ]; then ok=0; status="pull from $HOST failed (rsync rc=$pull_rc)"
elif [ $remote_ok -ne 1 ]; then ok=0; status="deadline's last backup did not succeed (see latest/STATUS)"
elif [ "$newest_ts" -eq 0 ]; then ok=0; status="no state file in $DEST/latest"
elif [ $age_h -gt "$MAX_AGE_H" ]; then ok=0; status="deadline's newest backup is ${age_h}h old (limit ${MAX_AGE_H}h)"; fi
log "$status; copies=$copies newest=$(basename "${newest:-none}") pruned=$pruned"

tmp=$(mktemp "$PROM_DIR/.deadline_backup.XXXXXX")
cat > "$tmp" <<EOF
# HELP deadline_backup_pull_success 1 if the last pull succeeded, deadline's own run succeeded, and its newest backup is within the age limit.
# TYPE deadline_backup_pull_success gauge
deadline_backup_pull_success{source="deadline"} $ok
# HELP deadline_backup_newest_timestamp_seconds Modification time of deadline's newest state backup held here.
# TYPE deadline_backup_newest_timestamp_seconds gauge
deadline_backup_newest_timestamp_seconds{source="deadline"} $newest_ts
# HELP deadline_backup_copies Dated copies of deadline's backup held here.
# TYPE deadline_backup_copies gauge
deadline_backup_copies{source="deadline"} $copies
# HELP deadline_backup_bytes Size of the newest copy (hard links to older copies are counted in full).
# TYPE deadline_backup_bytes gauge
deadline_backup_bytes{source="deadline"} $bytes
# HELP deadline_backup_pull_last_run_timestamp_seconds When the pull last ran.
# TYPE deadline_backup_pull_last_run_timestamp_seconds gauge
deadline_backup_pull_last_run_timestamp_seconds{source="deadline"} $now
EOF
chmod 644 "$tmp" && mv -f "$tmp" "$PROM_DIR/deadline_backup.prom"

[ $ok = 1 ]
