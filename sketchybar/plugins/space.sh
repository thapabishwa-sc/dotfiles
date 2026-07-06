#!/usr/bin/env bash

# Highlights the focused space number. $1 = this item's space index.
# Driven by yabai_space (space_changed signal).

YABAI=/opt/homebrew/bin/yabai
JQ=/opt/homebrew/bin/jq
sid="$1"

focused=$("$YABAI" -m query --spaces --space 2>/dev/null | "$JQ" -r '.index // 0')
if [ "$sid" = "$focused" ]; then
  sketchybar --set "$NAME" icon.highlight=on  background.drawing=on
else
  sketchybar --set "$NAME" icon.highlight=off background.drawing=off
fi
