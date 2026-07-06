#!/usr/bin/env bash

# Single poll-driven controller for the workspace UI (runs every update_freq via
# the hidden stack.anchor item, plus on events). Independent of whether yabai's
# space/window signals actually reach sketchybar:
#   • focused workspace number       -> background pill (icons stay white)
#   • current workspace's window-icon row (stack.1..MAX), focused window -> pill
#     (skips floating/hidden/minimized/sticky windows)
#
# All changes are batched into ONE `sketchybar` call applied atomically, so the
# periodic refresh doesn't flicker.

YABAI=/opt/homebrew/bin/yabai
JQ=/opt/homebrew/bin/jq
ICON_MAP="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins/icon_map.sh"
MAX=8

spaces=$("$YABAI" -m query --spaces 2>/dev/null)
[ -z "$spaces" ] && exit 0

focused=$(printf '%s' "$spaces" | "$JQ" -r '.[] | select(.["has-focus"]==true) | .index' | head -1)
[ -z "$focused" ] && exit 0

args=()

# --- workspace number: background pill on the focused one --------------------
for s in $(printf '%s' "$spaces" | "$JQ" -r '.[].index'); do
  if [ "$s" = "$focused" ]; then
    args+=(--set space.$s background.drawing=on)
  else
    args+=(--set space.$s background.drawing=off)
  fi
done

# --- current workspace's window-icon row ------------------------------------
list=$("$YABAI" -m query --windows --space "$focused" 2>/dev/null \
  | "$JQ" -r '.[]
      | select(.["is-floating"]==false and .["is-hidden"]==false
               and .["is-minimized"]==false and .["is-sticky"]==false)
      | "\(.["has-focus"])\t\(.app)"')

i=0
while IFS=$'\t' read -r focus app; do
  [ -z "$app" ] && continue
  i=$((i + 1)); [ "$i" -gt "$MAX" ] && break
  glyph=$(bash "$ICON_MAP" "$app")
  bg=off; [ "$focus" = "true" ] && bg=on
  args+=(--set stack.$i drawing=on icon="$glyph" background.drawing=$bg)
done <<< "$list"

# Hide the unused slots.
j=$((i + 1))
while [ "$j" -le "$MAX" ]; do args+=(--set stack.$j drawing=off); j=$((j + 1)); done

sketchybar "${args[@]}"
