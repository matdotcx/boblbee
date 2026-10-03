#!/bin/bash
# ha-backup-pull.sh — copy Home Assistant's nightly backups from hydrogen to this host (boblbee
# hosts/agents/ha-backup). Runs on cobalt at 06:15, after HA writes its automatic backup (~05:20);
# Backblaze on cobalt takes ~/backups offsite from here.
#
# Pull, not push: cobalt already reaches hydrogen with its keychain-held key, so nothing new is
# authorised on either side, and hydrogen holds no way into the backup host.
#
# Only Automatic_backup_*.tar is copied. HA encrypts those with its backup key; the same folder
# also holds plaintext config snapshots (*.bak, ha-config-*/) that must not go offsite. HA keeps 3
# copies; this keeps KEEP_DAYS here, never fewer than the newest 3, and never mirrors deletions.
#
#   HA_BACKUP_SRC        host:path to pull from  (default hydrogen:/Users/ops/homeassistant/backups/)
#   HA_BACKUP_DEST       local directory         (default ~/backups/homeassistant)
#   HA_BACKUP_KEEP_DAYS  prune copies older than (default 30)
#   HA_BACKUP_MAX_AGE_H  fail if the newest copy is older than this many hours (default 36)
#
# Writes ha_backup.prom to the Prometheus textfile directory so observability can alert on it.
set -u
SRC=${HA_BACKUP_SRC:-hydrogen:/Users/ops/homeassistant/backups/}
DEST=${HA_BACKUP_DEST:-$HOME/backups/homeassistant}
KEEP_DAYS=${HA_BACKUP_KEEP_DAYS:-30}; MAX_AGE_H=${HA_BACKUP_MAX_AGE_H:-36}
LOG="$HOME/logs/ha-backup-pull.log"
PROM_DIR="$HOME/.local/share/prometheus/textfile"
src_host=${SRC%%:*}
mkdir -p "$DEST" "$HOME/logs" "$PROM_DIR"
log(){ printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

rsync -a --include='Automatic_backup_*.tar' --exclude='*' \
  -e 'ssh -o BatchMode=yes -o ConnectTimeout=15' "$SRC" "$DEST/" 2>>"$LOG"
pull_rc=$?

# Newest first; mtime is the backup's own time (rsync -a keeps it). Prune past the newest 3 only,
# so a long run of failed pulls can't age every copy out.
pruned=0; i=0
while IFS= read -r f; do
  i=$((i + 1)); [ $i -le 3 ] && continue
  if [ -n "$(find "$f" -mtime +"$KEEP_DAYS" 2>/dev/null)" ]; then rm -f "$f" && pruned=$((pruned + 1)); fi
done < <(ls -t "$DEST"/Automatic_backup_*.tar 2>/dev/null)

newest=$(ls -t "$DEST"/Automatic_backup_*.tar 2>/dev/null | head -1)
now=$(date +%s); newest_ts=0; copies=0; bytes=0
if [ -n "$newest" ]; then
  newest_ts=$(stat -f %m "$newest")
  copies=$(ls "$DEST"/Automatic_backup_*.tar | wc -l | tr -d ' ')
  bytes=$(stat -f %z "$DEST"/Automatic_backup_*.tar | awk '{s += $1} END {print s + 0}')
fi
age_h=$(( (now - newest_ts) / 3600 ))

ok=1; status="ok"
if [ $pull_rc -ne 0 ]; then ok=0; status="pull from $src_host failed (rsync rc=$pull_rc)"; fi
if [ "$newest_ts" -eq 0 ]; then ok=0; status="no backups in $DEST"
elif [ $age_h -gt "$MAX_AGE_H" ]; then ok=0; status="newest copy is ${age_h}h old (limit ${MAX_AGE_H}h)"; fi
log "$status; copies=$copies newest=$(basename "${newest:-none}") pruned=$pruned"

tmp=$(mktemp "$PROM_DIR/.ha_backup.XXXXXX")
cat > "$tmp" <<EOF
# HELP ha_backup_pull_success 1 if the last pull succeeded and the newest copy is within the age limit.
# TYPE ha_backup_pull_success gauge
ha_backup_pull_success{source="$src_host"} $ok
# HELP ha_backup_newest_timestamp_seconds Modification time of the newest Home Assistant backup held here.
# TYPE ha_backup_newest_timestamp_seconds gauge
ha_backup_newest_timestamp_seconds{source="$src_host"} $newest_ts
# HELP ha_backup_copies Home Assistant backups held here.
# TYPE ha_backup_copies gauge
ha_backup_copies{source="$src_host"} $copies
# HELP ha_backup_bytes Total size of the Home Assistant backups held here.
# TYPE ha_backup_bytes gauge
ha_backup_bytes{source="$src_host"} $bytes
# HELP ha_backup_pull_last_run_timestamp_seconds When the pull last ran.
# TYPE ha_backup_pull_last_run_timestamp_seconds gauge
ha_backup_pull_last_run_timestamp_seconds{source="$src_host"} $now
EOF
chmod 644 "$tmp" && mv -f "$tmp" "$PROM_DIR/ha_backup.prom"

[ $ok = 1 ]
