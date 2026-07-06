#!/bin/bash
# Toggle "center mode" for the workspace currently on the Dell U3425WE (bound to alt-c).
#
# Center mode is per workspace: the set of centered workspaces lives in a state file,
# and center-apply.sh (also run from exec-on-workspace-change) sets the Dell's side
# gaps for whichever workspace is showing there.
#
# Runs from AeroSpace's minimal launchd PATH, so use absolute paths.

AEROSPACE=/opt/homebrew/bin/aerospace
STATE_DIR="${AEROSPACE_CENTER_STATE_DIR:-$HOME/.local/state/aerospace}"
STATE="$STATE_DIR/centered-workspaces"
APPLY="$(dirname "$0")/center-apply.sh"

dell=$("$AEROSPACE" list-monitors --format '%{monitor-id}|%{monitor-name}' | /usr/bin/grep -i 'u3425we' | /usr/bin/cut -d'|' -f1)
[ -n "$dell" ] || exit 0   # Dell not connected: nothing to center
ws=$("$AEROSPACE" list-workspaces --monitor "$dell" --visible)
[ -n "$ws" ] || exit 0

/bin/mkdir -p "$STATE_DIR"
/usr/bin/touch "$STATE"
if /usr/bin/grep -qx "$ws" "$STATE"; then
  /usr/bin/grep -vx "$ws" "$STATE" > "$STATE.tmp"; /bin/mv "$STATE.tmp" "$STATE"
else
  echo "$ws" >> "$STATE"
fi

exec "$APPLY"
