#!/usr/bin/env bash

# Sets the front_app label from whichever source fired:
#   hs_front_app        -> $APP   (Hammerspoon app watcher)
#   front_app_switched  -> $INFO  (native sketchybar fallback)

case "$SENDER" in
  hs_front_app)       name="$APP" ;;
  front_app_switched) name="$INFO" ;;
  *)                  name="$APP" ;;
esac

[ -n "$name" ] && sketchybar --set "$NAME" label="$name"
