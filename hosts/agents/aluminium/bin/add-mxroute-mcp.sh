#!/bin/sh
# Registers the hosted imap-mcp (diego@iaconelli.org) with Claude Code, user scope.
# Reads the bearer token over SSH; nothing is echoed.
set -eu
TOKEN="$(ssh deadline sudo cat /opt/imap-mcp/secrets/mcp-token-read 2>/dev/null || ssh deadline sudo cat /opt/imap-mcp/secrets/mcp-token)"
[ -n "$TOKEN" ] || { echo "no token read from deadline" >&2; exit 1; }
claude mcp remove -s user mxroute >/dev/null 2>&1 || true
claude mcp add --transport http -s user mxroute https://mcp.iaconelli.org/mcp \
  -H "Authorization: Bearer $TOKEN"
unset TOKEN
claude mcp list | grep -i mxroute
