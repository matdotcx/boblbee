#!/bin/bash
# Claude Code PreToolUse hook: allow read-only gh api calls, block mutations.
#
# Reads the tool input JSON from stdin. Checks if the Bash command contains
# a gh api call. If so, only allows GET and HEAD methods (the default for
# gh api is GET). Blocks POST, PUT, PATCH, DELETE.
#
# Security: Checks for gh api anywhere in the command to prevent bypasses
# via command chaining (&&, ||, ;), subshells, or piping.

set -euo pipefail

# Read tool input from stdin
INPUT=$(cat)

# Extract the command from the tool input
COMMAND=$(echo "$INPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))" 2>/dev/null || echo "")

# Check if command contains gh api anywhere (not just at start)
# This prevents bypasses via: cmd && gh api, (gh api ...), echo | gh api, etc.
if ! echo "$COMMAND" | grep -qE '\bgh\s+api\b'; then
    # No gh api command — pass through (no opinion)
    exit 0
fi

# Check for explicit method flags that indicate mutation
if echo "$COMMAND" | grep -qiE '(-X|--method)\s+(POST|PUT|PATCH|DELETE)\b'; then
    # Mutating method — block
    echo '{"decision": "block", "reason": "gh-api-readonly hook: only GET/HEAD methods are allowed. Use explicit Bash permissions for write operations."}'
    exit 0
fi

# Check for --input or --raw-field flags which are used with mutations
# (--input provides request body, typically for POST/PUT/PATCH)
if echo "$COMMAND" | grep -qE '\s(--input|-F\s|--raw-field)\b'; then
    echo '{"decision": "block", "reason": "gh-api-readonly hook: --input and --raw-field flags suggest mutation. Use explicit Bash permissions for write operations."}'
    exit 0
fi

# Check for -X GET or -X HEAD (explicitly read-only — allow)
if echo "$COMMAND" | grep -qiE '(-X|--method)\s+(GET|HEAD)\b'; then
    # Read-only — no opinion; defer to normal permission handling.
    exit 0
fi

# No explicit method flag — gh api defaults to GET; no opinion, defer to
# normal permission handling.
exit 0
