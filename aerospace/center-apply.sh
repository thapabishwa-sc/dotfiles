#!/bin/bash
# Apply per-workspace center mode on the Dell U3425WE ultrawide.
#
# AeroSpace gaps are per monitor, not per workspace, and can't be changed at runtime
# (upstream #1515), so this rewrites the Dell's outer.left/right in aerospace.toml and
# reloads - but only when the workspace showing on the Dell needs a different margin
# than the current one, so switching between same-mode workspaces costs nothing.
# Called from exec-on-workspace-change and from center-toggle.sh (alt-c).
#
# Runs from AeroSpace's minimal launchd PATH, so use absolute paths.

AEROSPACE=/opt/homebrew/bin/aerospace
CONFIG="$HOME/.config/aerospace/aerospace.toml"
STATE="${AEROSPACE_CENTER_STATE_DIR:-$HOME/.local/state/aerospace}/centered-workspaces"
NORMAL=32    # everyday side gap on the Dell (matches [gaps])
CENTER=700   # ~20% of 3440px per side -> a ~2040px centered column

dell=$("$AEROSPACE" list-monitors --format '%{monitor-id}|%{monitor-name}' | /usr/bin/grep -i 'u3425we' | /usr/bin/cut -d'|' -f1)
[ -n "$dell" ] || exit 0
ws=$("$AEROSPACE" list-workspaces --monitor "$dell" --visible)

want=$NORMAL
[ -n "$ws" ] && [ -f "$STATE" ] && /usr/bin/grep -qx "$ws" "$STATE" && want=$CENTER

/usr/bin/grep -q "^outer\.left .*monitor\.'u3425we' = $want }" "$CONFIG" && exit 0   # already right

# Only touch the outer.left/right lines (inner/top/bottom use other values).
/usr/bin/perl -pi -e "s/(^outer\.(left|right)\s*=.*monitor\.'u3425we' = )\d+( \})/\${1}$want\${3}/" "$CONFIG"
"$AEROSPACE" reload-config
