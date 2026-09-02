#!/usr/bin/env python3
"""Post-edit hook: runs ruff check --fix and ruff format on edited Python files."""
import json
import subprocess
import sys


def run_command(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        output = ""
        if result.stderr:
            output += result.stderr
        if result.stdout:
            output += result.stdout
        return result.returncode == 0, output
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return True, ""


try:
    input_data = json.load(sys.stdin)
except (json.JSONDecodeError, EOFError):
    sys.exit(0)

file_path = input_data.get("tool_input", {}).get("file_path", "")
if not file_path.endswith(".py"):
    sys.exit(0)

run_command(["ruff", "format", file_path])
success, output = run_command(["ruff", "check", "--fix", file_path])
if not success and output:
    print(output, file=sys.stderr)

sys.exit(0)
