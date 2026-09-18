#!/bin/bash
# uninstall.sh — unload the agents and remove the installed copies. Leaves logs, state and data alone.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; uid=$(id -u)
for t in "$HERE"/launchd/*.plist; do
  label=$(basename "$t" .plist)
  launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 && echo "unloaded $label"
  rm -f "$HOME/Library/LaunchAgents/$label.plist" && echo "removed  $label.plist"
done
for f in "$HERE"/bin/*; do rm -f "$HOME/bin/$(basename "$f")" && echo "removed  ~/bin/$(basename "$f")"; done
