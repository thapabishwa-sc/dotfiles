#!/usr/bin/env bash
# Symlink all dotfiles into place with GNU stow.
#
#   ~/.config packages  ->  --target from .stowrc (~/.config), one whole-dir
#                           symlink per package (yabai, sketchybar, atuin, ...).
#   zshrc               ->  ~/.zshrc         (lives in $HOME, not ~/.config)
#   kube                ->  ~/.kube/kubie.yaml
#   ssh                 ->  ~/.ssh/config    (SSH reads ~/.ssh, not ~/.config)
#   iterm2              ->  NOT stowed — it's a binary plist in ~/Library and
#                           symlinking corrupts it; import instead (iterm2/README.md).
#
# --adopt pulls any pre-existing real file into the repo instead of erroring, so
# a first run on a populated machine won't conflict. Re-runs are idempotent.
set -euo pipefail
cd "$(dirname "$0")"

# Packages that do NOT go into ~/.config (handled with their own target, or not
# stow-managed at all).
non_config='zshrc kube ssh iterm2'

# Everything else is a ~/.config package.
config_pkgs=()
for d in */; do
  d=${d%/}
  case " $non_config " in *" $d "*) continue ;; esac
  config_pkgs+=("$d")
done

echo "stow -> ~/.config : ${config_pkgs[*]}"
stow --adopt "${config_pkgs[@]}"                 # --target=~/.config from .stowrc

echo "stow -> \$HOME      : zshrc"
stow --adopt --target="$HOME" zshrc              # ~/.zshrc

echo "stow -> ~/.kube    : kube"
mkdir -p "$HOME/.kube"
stow --adopt --target="$HOME/.kube" kube         # ~/.kube/kubie.yaml

echo "stow -> ~/.ssh     : ssh"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
stow --adopt --target="$HOME/.ssh" ssh           # ~/.ssh/config

echo "skipped (import-only): iterm2  ->  see iterm2/README.md"
