#!/usr/bin/env bash

# Highlights the focused space. Runs for each space item on the `yabai_space`
# event (triggered by yabai signals) and once when the item is created.
# $1 = this item's space index; $NAME = this item's sketchybar name.

sid="$1"
focused=$(yabai -m query --spaces --space | grep -o '"index":[0-9]*' | grep -o '[0-9]*')

if [ "$sid" = "$focused" ]; then
  sketchybar --set "$NAME" icon.highlight=on  background.drawing=on
else
  sketchybar --set "$NAME" icon.highlight=off background.drawing=off
fi
