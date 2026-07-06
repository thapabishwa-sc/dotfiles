#!/usr/bin/env sh
# Space + gap layout, extracted from yabairc so the display_added / display_removed
# signals can re-run JUST the layout. Re-running the whole yabairc on every display
# change would call `yabai -m signal --add` again for every signal — and yabai
# APPENDS signals, it never dedupes — leaving duplicate copies that fire sketchybar
# several times per event. That pile-up is what made sketchybar flicker / feel buggy.
# This script only creates/moves/labels spaces and sets gaps, so it's idempotent
# and safe to run at startup and on every dock/undock.
#
# Requires the scripting addition (already loaded by the time this runs).

MACBOOK_UUID="37D8832A-2D66-02CA-B9F7-8F30A301B230"

# ── Spaces -> displays (dynamic; survives dock/undock) ───────────────────────
# Docked (2 displays):   ws1-8 on the external, ws9-10 on the built-in MacBook.
# Undocked (laptop only): all 10 spaces collapse back onto the MacBook.
# The MacBook is found by its stable display UUID — yabai's display *index*
# depends on physical arrangement, so it can't be hardcoded. We also destroy the
# empty space macOS auto-creates on a newly attached display (the stray "space
# 11"), then relabel ws1..ws10 == space index 1..10 so index and label agree.
setup_spaces() {
  local ndisplays macbook external i idx n
  ndisplays=$(yabai -m query --displays | jq 'length')
  macbook=$(yabai -m query --displays | jq -r --arg u "$MACBOOK_UUID" '.[] | select(.uuid==$u) | .index')

  # Exactly 10 spaces: destroy extras (prefer the empty/unlabeled phantom macOS
  # creates on attach), create any that are missing.
  while [ "$(yabai -m query --spaces | jq 'length')" -gt 10 ]; do
    yabai -m space "$(yabai -m query --spaces | jq -r '(map(select(.label=="")) + .)[0].index')" --destroy 2>/dev/null || break
  done
  while [ "$(yabai -m query --spaces | jq 'length')" -lt 10 ]; do yabai -m space --create; done

  # Docked: leave exactly 2 spaces on the MacBook; the external takes the other 8.
  if [ -n "$macbook" ] && [ "$ndisplays" -ge 2 ]; then
    external=$(yabai -m query --displays | jq -r --arg m "$macbook" '.[] | select((.index|tostring)!=$m) | .index' | head -1)
    while [ "$(yabai -m query --spaces --display "$macbook" | jq 'length')" -gt 2 ]; do
      yabai -m space "$(yabai -m query --spaces --display "$macbook" | jq -r '.[0].index')" --display "$external" 2>/dev/null || break
    done
    while [ "$(yabai -m query --spaces --display "$macbook" | jq 'length')" -lt 2 ]; do
      yabai -m space "$(yabai -m query --spaces --display "$external" | jq -r '.[-1].index')" --display "$macbook" 2>/dev/null || break
    done
  fi

  # Relabel by DISPLAY (not raw index): the MacBook's two spaces are ALWAYS ws9/ws10
  # and the external's are ws1-8, so the Slack rule (space=ws10) always lands on the
  # MacBook. Relabel-by-index broke this once the display arrangement flipped (e.g.
  # after setting the external as the macOS main display) — the MacBook's spaces then
  # took indices 1-2 and ws9/ws10 slid onto the external. Solo: ws1-10 by index.
  # Two-pass (temp labels first) avoids "label already exists" collisions.
  n=0
  for idx in $(yabai -m query --spaces | jq -r '.[].index'); do n=$((n+1)); yabai -m space "$idx" --label "tmp$n" 2>/dev/null; done
  if [ -n "$macbook" ] && [ "$ndisplays" -ge 2 ]; then
    n=0
    for idx in $(yabai -m query --spaces --display "$external" | jq -r '.[].index'); do n=$((n+1)); yabai -m space "$idx" --label "ws$n" 2>/dev/null; done
    for idx in $(yabai -m query --spaces --display "$macbook"  | jq -r '.[].index'); do n=$((n+1)); yabai -m space "$idx" --label "ws$n" 2>/dev/null; done
  else
    n=0
    for idx in $(yabai -m query --spaces | jq -r '.[].index'); do n=$((n+1)); yabai -m space "$idx" --label "ws$n" 2>/dev/null; done
  fi

  # App rules (space=wsN) only fire when a window is CREATED; on a relayout the
  # label under an existing window can shift, so re-pin the pinned apps here to
  # match the rules in yabairc.
  repin() { for wid in $(yabai -m query --windows 2>/dev/null | jq -r --arg a "$1" '.[] | select(.app==$a) | .id'); do yabai -m window "$wid" --space "$2" 2>/dev/null; done; }
  repin "Slack"   ws10
  repin "zoom.us" ws9    # Zoom reports two app names...
  repin "Zoom"    ws9    # ...pin both to ws9
}

# ── Per-monitor gaps (aerospace: built-in flush, externals padded 10/20) ─────
space_gaps() {  # <space> <window_gap> <top> <bottom> <left> <right>
  yabai -m config --space "$1" window_gap     "$2"
  yabai -m config --space "$1" top_padding    "$3"
  yabai -m config --space "$1" bottom_padding "$4"
  yabai -m config --space "$1" left_padding   "$5"
  yabai -m config --space "$1" right_padding  "$6"
}
setup_gaps() {
  # All spaces fully flush. The bar's top strip is reserved by external_bar on all
  # displays (see yabairc), so no per-space padding is needed here — per-space
  # top_padding would stack below the menu bar and open a huge gap.
  local i
  for i in $(seq 1 10); do space_gaps "ws$i" 0 0 0 0 0; done
}

setup_spaces
setup_gaps
