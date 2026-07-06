#!/bin/bash
# Apply the Vivaldi config in this directory: quit Vivaldi, write workspaces / rules /
# UI settings / nickname search engines (workspace-rules.py), then reopen it.
# Fully unattended; backups of Preferences and Web Data are written before changes.
set -euo pipefail
cd "$(dirname "$0")"

was_running=false
if pgrep -x Vivaldi >/dev/null; then
  was_running=true
  echo "Quitting Vivaldi..."
  osascript -e 'quit app "Vivaldi"'
  for _ in $(seq 1 30); do pgrep -x Vivaldi >/dev/null || break; sleep 0.5; done
  pgrep -x Vivaldi >/dev/null && { echo "Vivaldi didn't quit; close it and re-run."; exit 1; }
fi

python3 ./workspace-rules.py

$was_running && open -a Vivaldi
echo "Done."
