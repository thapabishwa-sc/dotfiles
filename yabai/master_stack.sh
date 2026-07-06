#!/usr/bin/env bash
# Master-stack layout for the FOCUSED space (yabai has no native master-stack).
# The left-most managed window becomes the master at MASTER_RATIO of the width;
# every other window is stacked in a single vertical column on the right.
#
# yabai's tree ops (warp/insert) are not perfectly deterministic, so this is a
# best-effort rebuild — run it (shift+alt+m) whenever the layout drifts. If it
# doesn't produce a clean master|stack, tell me what it did and we'll tune it.

MASTER_RATIO=0.60
Y=/opt/homebrew/bin/yabai
J=/opt/homebrew/bin/jq

sid=$("$Y" -m query --spaces --space | "$J" '.index')

# Managed, non-floating, non-minimized windows, ordered left-to-right/top-to-bottom.
# (window IDs are integers, so word-splitting is safe — avoids bash-4 mapfile.)
ids=($("$Y" -m query --windows --space "$sid" \
  | "$J" -r '[.[] | select(.["is-floating"]==false and .["is-minimized"]==false and .["is-native-fullscreen"]==false)]
             | sort_by(.frame.x, .frame.y) | .[].id'))
n=${#ids[@]}
(( n <= 1 )) && exit 0

master=${ids[0]}

# 1) master | first stack window  -> left/right split (master ends up west)
"$Y" -m window "$master" --insert east
"$Y" -m window "${ids[1]}" --warp "$master"

# 2) stack the remaining windows vertically beneath the previous stack window
prev=${ids[1]}
for (( i=2; i<n; i++ )); do
  "$Y" -m window "$prev" --insert south
  "$Y" -m window "${ids[i]}" --warp "$prev"
  prev=${ids[i]}
done

# 3) give the master its width
"$Y" -m window "$master" --ratio abs:"$MASTER_RATIO" 2>/dev/null
