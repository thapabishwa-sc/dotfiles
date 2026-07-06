# yabai

Tiling WM config ported from `aerospace/aerospace.toml`. Keybindings live in
`skhd/skhdrc` (yabai has no built-in hotkey daemon).

## Install

```sh
brew install koekeishiya/formulae/yabai koekeishiya/formulae/skhd
# stow the repo so yabai/yabairc -> ~/.config/yabai/yabairc and skhd/skhdrc -> ~/.config/skhd/skhdrc
brew services start yabai     # or: yabai --start-service
brew services start skhd      # or: skhd --start-service
```

## The SIP tradeoff (read before committing)

Unlike aerospace, yabai uses **native macOS Spaces**. Space focus, moving
windows to spaces, per-app space rules, and space↔monitor pinning — the bindings
marked `[SA]` — only work after you **partially disable SIP** and load the
scripting addition. Steps are at the top of `yabairc`.

Everything SA-dependent is gated behind one switch in `yabairc`:

```sh
SA_ENABLED="no"     # "no" = pure in-space tiler, zero errors (default)
                    # "yes" = full parity — set only after the SIP + sudoers steps
```

- **`SA_ENABLED=no` (SIP on)** → solid in-space tiler: bsp layout, gaps,
  `alt-hjkl` focus/move, resize & service modes, float rules. The `alt-1..0`
  space keys become harmless no-ops. Optionally switch spaces via macOS's own
  shortcuts (see the NO-SIP ALTERNATIVE note in `skhd/skhdrc`).
- **`SA_ENABLED=yes` (SIP partially disabled)** → full aerospace parity.

## Notes / deviations from aerospace

- accordion → `stack` layout (yabai has no orientable accordion).
- `join-with` → `--insert` (sets where the next window splits).
- Per-monitor gaps: aerospace gave the built-in display 0 gaps; yabai gaps are
  global here. A `display_changed` signal script would be needed to vary them.
- `flatten-workspace-tree` → `--balance` (closest equivalent).
- Focus/move wrap-around is approximated with `|| --focus first/last`.
