#!/bin/bash
# heartbeat.sh — tell healthchecks.io that helium's monitoring is alive (boblbee hosts/agents/heartbeat).
#
# helium runs the fleet's only monitoring, so it can't report its own outage: on 18 Sep 2026 Prometheus
# was down for 12 hours and nothing noticed. Every 5 minutes this pings an external check when Prometheus
# is ready and at least half its scrape targets are up, and pings the check's /fail endpoint with the
# reason when not. healthchecks.io alerts on a /fail, and when pings stop for longer than the period plus
# grace (5 + 10 minutes). So it catches helium being down, asleep or not logged in, and Colima or
# Prometheus being down: none of those can alert from helium itself.
#
# The ping URL is in ~/.config/heartbeat/ping-url (mode 600), outside every repo. Anyone with it can ping.
set -u
URL_FILE="$HOME/.config/heartbeat/ping-url"
LOG="$HOME/logs/heartbeat.log"
mkdir -p "$HOME/logs"
[ -r "$URL_FILE" ] || { echo "$(date '+%F %T') no ping URL at $URL_FILE" >> "$LOG"; exit 1; }
URL=$(head -1 "$URL_FILE")

reason=""
if ! curl -sf --max-time 5 http://127.0.0.1:9090/-/ready >/dev/null; then
    reason="Prometheus on helium is not ready"
else
    counts=$(curl -s --max-time 5 http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=count(up == 1) or vector(0)' \
               | /usr/bin/python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(int(float(r[0]["value"][1])) if r else 0)' 2>/dev/null)
    total=$(curl -s --max-time 5 http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=count(up)' \
               | /usr/bin/python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(int(float(r[0]["value"][1])) if r else 0)' 2>/dev/null)
    up=${counts:-0}; total=${total:-0}
    if [ "$total" -eq 0 ] || [ $((up * 2)) -lt "$total" ]; then reason="only $up of $total Prometheus targets are up"; fi
fi

if [ -z "$reason" ]; then
    curl -fsS -m 10 --retry 3 -o /dev/null --data-raw "ok: $up/$total targets up" "$URL" 2>>"$LOG" || echo "$(date '+%F %T') ping failed" >> "$LOG"
else
    curl -fsS -m 10 --retry 3 -o /dev/null --data-raw "$reason" "$URL/fail" 2>>"$LOG"
    echo "$(date '+%F %T') FAIL: $reason" >> "$LOG"
fi
