#!/usr/bin/env bash

# yabai-driven workspace numbers (1..N), focused one highlighted. Navigation
# only — the current workspace's window icons are shown by the stack row
# (items/stack.sh). Driven by yabai_space (space_changed signal).

sketchybar --add event yabai_space

# Wait for yabai to be queryable — if this reload was chained right after
# `yabai --restart-service`, yabai's socket may not be up yet and the query
# returns empty, leaving the bar with no spaces. Retry briefly.
spaces=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  spaces=$(yabai -m query --spaces 2>/dev/null | grep -o '"index":[0-9]*' | grep -o '[0-9]*')
  [ -n "$spaces" ] && break
  sleep 0.3
done

for sid in $spaces; do
  sketchybar --add item space.$sid left                                   \
             --subscribe space.$sid yabai_space                           \
             --set space.$sid                                             \
                   icon="$sid"                                            \
                   icon.color=$WHITE                                      \
                   icon.highlight_color=$RED                              \
                   icon.padding_left=8                                    \
                   icon.padding_right=8                                   \
                   label.drawing=off                                      \
                   background.color=0x44ffffff                            \
                   background.corner_radius=5                             \
                   background.height=24                                   \
                   background.drawing=off                                 \
                   click_script="yabai -m space --focus $sid 2>/dev/null" \
                   script="$PLUGIN_DIR/space.sh $sid"
done
