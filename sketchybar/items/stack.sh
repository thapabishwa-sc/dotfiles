#!/usr/bin/env bash

# Current-workspace window row: a row of app-icon slots showing the focused
# space's windows (focused one highlighted). Glyphs need the sketchybar-app-font.

sketchybar --add event windows_on_spaces
sketchybar --add event window_focus

# Hidden anchor runs the manager script on space/window/focus changes, plus a
# periodic poll as a safety net (window_created/destroyed can be flaky, so this
# guarantees open/close is reflected within update_freq seconds).
sketchybar --add item stack.anchor left                                   \
           --set stack.anchor drawing=off                                 \
                 updates=on                                               \
                 update_freq=2                                            \
                 script="$PLUGIN_DIR/stack.sh"                            \
           --subscribe stack.anchor yabai_space windows_on_spaces window_focus

# Pre-created icon slots (stable positions; the plugin fills/toggles them).
for i in $(seq 1 8); do
  sketchybar --add item stack.$i left                                     \
             --set stack.$i                                               \
                   drawing=off                                            \
                   icon.font="sketchybar-app-font:Regular:16.0"           \
                   icon.color=$WHITE                                      \
                   label.drawing=off                                      \
                   background.color=0x44ffffff                            \
                   background.corner_radius=5                             \
                   background.height=24                                   \
                   background.drawing=off                                 \
                   click_script="yabai -m window --focus stack.$i 2>/dev/null"
done
