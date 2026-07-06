#!/usr/bin/env bash

# Focused-app name in the bar. Driven by Hammerspoon (hs_front_app event with
# $APP) and ALSO by sketchybar's native front_app_switched ($INFO) as a fallback
# so it keeps working if Hammerspoon is reloading.

sketchybar --add event hs_front_app                                       \
           --add item front_app center                                   \
           --set front_app                                               \
                 icon.drawing=off                                        \
                 label.color=$WHITE                                      \
                 label.font="$FONT:Semibold:13.0"                        \
                 script="$PLUGIN_DIR/front_app.sh"                       \
           --subscribe front_app hs_front_app front_app_switched
