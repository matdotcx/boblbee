#!/bin/bash
# create-check.sh — one-time setup for the heartbeat profile: create (or find) the healthchecks.io check and
# save its ping URL to ~/.config/heartbeat/ping-url (mode 600). Reads the project's read-write API key from
# ~/.config/healthchecks/api-key. Prints the check's name, status and timings and the alert channels;
# never the key or the URL. Safe to re-run: the check is matched by name.
set -euo pipefail
KEY_FILE="$HOME/.config/healthchecks/api-key"; URL_FILE="$HOME/.config/heartbeat/ping-url"
API=https://healthchecks.io/api/v3
[ -r "$KEY_FILE" ] || { echo "No API key at $KEY_FILE" >&2; exit 1; }
hdr() { printf 'X-Api-Key: %s\n' "$(head -1 "$KEY_FILE")"; }   # header via a file, so the key isn't in ps

resp=$(curl -fsS -m 20 -X POST "$API/checks/" -H @<(hdr) -H 'Content-Type: application/json' --data @- <<'JSON'
{"name": "helium monitoring", "slug": "helium-monitoring", "tags": "helium observability",
 "desc": "Pinged every 5 min by org.iaconelli.heartbeat on helium while Prometheus is ready and at least half its targets are up (boblbee hosts/agents/heartbeat). A /fail ping carries the reason.",
 "timeout": 300, "grace": 600, "channels": "*", "unique": ["name"]}
JSON
)
umask 077; mkdir -p "$(dirname "$URL_FILE")"
printf '%s' "$resp" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["ping_url"])' > "$URL_FILE"
chmod 600 "$URL_FILE"
printf '%s' "$resp" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print("check: %s | status: %s | period %ss + grace %ss" % (d["name"], d["status"], d["timeout"], d["grace"]))'
curl -fsS -m 20 "$API/channels/" -H @<(hdr) | /usr/bin/python3 -c 'import json,sys; c=json.load(sys.stdin)["channels"]; print("alert channels:", ", ".join("%s (%s)" % (x["kind"], x["name"] or "unnamed") for x in c) or "NONE: add an email or app integration in healthchecks.io")'
echo "ping URL saved to $URL_FILE"
