# Startup profiler — toggle with `ZSH_PROFILE=1 zsh -i -c exit` (no-op otherwise).
[[ -n $ZSH_PROFILE ]] && zmodload zsh/zprof

# ─────────────────────────────────────────────────────────────────────────────
# Locale
# ─────────────────────────────────────────────────────────────────────────────
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ─────────────────────────────────────────────────────────────────────────────
# Completion
# ─────────────────────────────────────────────────────────────────────────────
setopt prompt_subst
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
# Docker CLI completions (fpath must be set before compinit)
fpath=($HOME/.docker/completions $fpath)
# compinit + bashcompinit run in _deferred_init (after the first prompt) — you
# don't tab-complete in the first few ms, so the completion system can wait.

# Cache the output of slow generators (tool `init` scripts, completions) to a
# file and source that, instead of spawning the tool on every startup. Rebuilds
# only when the tool's binary is newer than the cached file.
_evalcache() {
  local cache="$HOME/.cache/zsh/${1}.zsh"
  if [[ ! -s "$cache" || "$(command -v "$1")" -nt "$cache" ]]; then
    mkdir -p "${cache:h}"; "$@" >| "$cache" 2>/dev/null
  fi
  source "$cache"
}

# kubectl completion, fzf, zoxide, atuin, direnv, and autosuggestions are loaded
# AFTER the first prompt (see _deferred_init at the bottom) so the prompt appears
# instantly, even on a cold start.

# ─────────────────────────────────────────────────────────────────────────────
# Keybindings  (autosuggest keys are bound in _deferred_init once it's sourced)
# ─────────────────────────────────────────────────────────────────────────────
ZSH_AUTOSUGGEST="/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
bindkey -e                      # default emacs keymap; otherwise zsh infers vi mode from $EDITOR=nvim

# Option+←/→ word jump. iTerm2 (with "Treat ⌥ as Alt for special keys like
# arrows" on) sends CSI-modifier sequences; bind them so words jump instead of
# leaking "[C"/"[D". The ^[b / ^[f fallbacks cover Option-key = "Esc+".
bindkey '^[[1;3D' backward-word   # ⌥←
bindkey '^[[1;3C' forward-word    # ⌥→
bindkey '^[[1;9D' backward-word   # ⌥← (alt reporting variant)
bindkey '^[[1;9C' forward-word    # ⌥→ (alt reporting variant)
bindkey '^[b'     backward-word   # ⌥← when Left Option = Esc+
bindkey '^[f'     forward-word    # ⌥→ when Right Option = Esc+

# ─────────────────────────────────────────────────────────────────────────────
# History
# macOS /etc/zshrc sets a 2000/1000 history with NO timestamps — an entry is just
# the command text, so when it ran and how long it took are lost. EXTENDED_HISTORY
# switches $HISTFILE to ': <start-epoch>:<elapsed-seconds>;<command>', recording
# both. Old plain-format lines stay readable, so there's nothing to migrate.
#   fc -li 1     # every command with its start time
#   fc -lDi 1    # ...plus how long it ran
# INC_APPEND_HISTORY_TIME appends as each command FINISHES, so a killed terminal
# doesn't lose the session AND the elapsed time is real — plain INC_APPEND_HISTORY
# (and SHARE_HISTORY) write the entry before the command runs and stamp every one
# of them 0s. Sub-second precision, exit code and cwd live in atuin's DB:
#   atuin history list --format "{time} {duration} {command}"
# ─────────────────────────────────────────────────────────────────────────────
HISTFILE=$HOME/.zsh_history
HISTSIZE=100000                  # entries held in memory for this session
SAVEHIST=100000                  # entries persisted to $HISTFILE
setopt EXTENDED_HISTORY          # store start timestamp + duration per entry
setopt INC_APPEND_HISTORY_TIME   # write on completion, not at shell exit

# ─────────────────────────────────────────────────────────────────────────────
# Prompt (starship). Kube context comes from starship's [kubernetes] module now,
# not kube-ps1 — enable/style it in ~/.config/starship/starship.toml.
# ─────────────────────────────────────────────────────────────────────────────
command -v starship >/dev/null && _evalcache starship init zsh
export STARSHIP_CONFIG=~/.config/starship/starship.toml

# ─────────────────────────────────────────────────────────────────────────────
# Environment
# ─────────────────────────────────────────────────────────────────────────────
export EDITOR=/opt/homebrew/bin/nvim
export GPG_TTY=$(tty)
# Don't clobber kubie's isolated KUBECONFIG when a kubie shell re-sources .zshrc.
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
export XDG_CONFIG_HOME="$HOME/.config"
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
export NIX_CONF_DIR="$HOME/.config/nix"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow'

# ─────────────────────────────────────────────────────────────────────────────
# PATH  (built additively — no destructive resets)
# ─────────────────────────────────────────────────────────────────────────────
# GNU coreutils/tools ahead of the macOS BSD versions
for gnu in coreutils findutils gnu-indent gnu-sed grep gnu-tar gawk ed gnu-which gpatch make; do
  PATH="/opt/homebrew/opt/$gnu/libexec/gnubin:$PATH"
done
PATH="/opt/homebrew/opt/binutils/bin:$PATH"
PATH="/opt/homebrew/opt/flex/bin:$PATH"
PATH="/opt/homebrew/opt/zip/bin:$PATH"
PATH="/opt/homebrew/opt/helm@3/bin:$PATH"
PATH="/run/current-system/sw/bin:$PATH"            # nix
PATH="$HOME/.cargo/bin:$PATH"
PATH="$GOBIN:$PATH"
PATH="$HOME/.local/bin:$PATH"                       # pipx / uv
PATH="$HOME/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
export PATH

# ─────────────────────────────────────────────────────────────────────────────
# Aliases
# ─────────────────────────────────────────────────────────────────────────────
alias la=tree
alias cl='clear'
command -v bat >/dev/null && alias cat=bat   # fall back to real cat if bat absent

# Git
alias gc="git commit -m"
alias gca="git commit -a -m"
alias gp="git push origin HEAD"
alias gpu="git pull origin"
alias gst="git status"
alias glog="git log --graph --topo-order --pretty='%w(100,0,6)%C(yellow)%h%C(bold)%C(black)%d %C(cyan)%ar %C(green)%an%n%C(bold)%C(white)%s %N' --abbrev-commit"
alias gdiff="git diff"
alias gco="git checkout"
alias gb='git branch'
alias gba='git branch -a'
alias gadd='git add'
alias ga='git add -p'
alias gcoall='git checkout -- .'
alias gre='git reset'

# Docker
alias dco="docker compose"
alias dps="docker ps"
alias dpa="docker ps -a"
alias dl="docker ps -l -q"
alias dx="docker exec -it"

# Dirs
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ......="cd ../../../../.."

# K8S
alias k="kubectl"
alias ka="kubectl apply -f"
alias kg="kubectl get"
alias kd="kubectl describe"
alias kdel="kubectl delete"
alias kgpo="kubectl get pod"
alias kgd="kubectl get deployments"
alias kc="kubectx"
alias kns="kubens"
alias kl="kubectl logs -f"
alias ke="kubectl exec -it"
alias kcns='kubectl config set-context --current --namespace'
alias kctx="kubie ctx"
alias kgsecd="kubectl ksd get secret -o yaml"   # decode secret values (needs the kubectl-ksd plugin)

# Eza
alias l="eza -l --icons --git -a"
alias lt="eza --tree --level=2 --long --icons --git"
alias ltree="eza --tree --level=2  --icons --git"

# Editors / misc
alias v="$HOME/.nix-profile/bin/nvim"
alias http="xh"                 # HTTP requests with xh
alias nm="nmap -sC -sV -oN nmap"
alias darkman="dark-mode toggle; nightlight toggle"
alias rr='ranger'
alias mat='osascript -e "tell application \"System Events\" to key code 126 using {command down}" && tmux neww "cmatrix"'

# Security tooling
alias gobust='gobuster dir --wordlist ~/security/wordlists/diccnoext.txt --wildcard --url'
alias dirsearch='python dirsearch.py -w db/dicc.txt -b -u'
alias massdns='~/hacking/tools/massdns/bin/massdns -r ~/hacking/tools/massdns/lists/resolvers.txt -t A -o S bf-targets.txt -w livehosts.txt -s 4000'
alias server='python -m http.server 4445'
alias tunnel='ngrok http 4445'
alias fuzz='ffuf -w ~/hacking/SecLists/content_discovery_all.txt -mc all -u'
alias gf='~/go/src/github.com/tomnomnom/gf/gf'

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────
function ranger {
	local IFS=$'\t\n'
	local tempfile="$(mktemp -t tmp.XXXXXX)"
	local ranger_cmd=(
		command
		ranger
		--cmd="map Q chain shell echo %d > "$tempfile"; quitall"
	)
	${ranger_cmd[@]} "$@"
	if [[ -f "$tempfile" ]] && [[ "$(cat -- "$tempfile")" != "$(echo -n `pwd`)" ]]; then
		cd -- "$(cat "$tempfile")" || return
	fi
	command rm -f -- "$tempfile" 2>/dev/null
}

# navigation
cx() { cd "$@" && l; }
fcd() { cd "$(find . -type d -not -path '*/.*' | fzf)" && l; }
f() { echo "$(find . -type f -not -path '*/.*' | fzf)" | pbcopy }
fv() { nvim "$(find . -type f -not -path '*/.*' | fzf)" }

# nix daemon (eager — sets up the nix profile PATH)
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
	. '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

# ─────────────────────────────────────────────────────────────────────────────
# Deferred init — load non-prompt integrations AFTER the first prompt renders,
# so the shell is usable instantly (especially on a cold start). Runs once, then
# removes itself. Trade-off: for the ~tens of ms until it fires, atuin (Ctrl-R),
# fzf keys, and autosuggestions aren't active yet.
# ─────────────────────────────────────────────────────────────────────────────
autoload -Uz add-zsh-hook
_deferred_init() {
  add-zsh-hook -d precmd _deferred_init
  # Completion system (deferred; -C skips the slow security scan). If a new
  # tool's completions don't show up, refresh once: rm ~/.zcompdump && compinit
  autoload -Uz compinit && compinit -C
  if [ -f "$ZSH_AUTOSUGGEST" ]; then
    source "$ZSH_AUTOSUGGEST"
    bindkey '^w' autosuggest-execute
    bindkey '^e' autosuggest-accept
    bindkey '^u' autosuggest-toggle
  fi
  command -v kubectl >/dev/null && _evalcache kubectl completion zsh
  command -v fzf     >/dev/null && _evalcache fzf --zsh
  command -v zoxide  >/dev/null && _evalcache zoxide init zsh
  command -v atuin   >/dev/null && _evalcache atuin init zsh
  command -v direnv  >/dev/null && _evalcache direnv hook zsh
}
add-zsh-hook precmd _deferred_init

# Print the startup profile when ZSH_PROFILE is set (see top of file).
[[ -n $ZSH_PROFILE ]] && zprof
# ─────────────────────────────────────────────────────────────────────────────
# Machine-local overrides (NOT tracked in dotfiles)
# Per-machine / per-OS shell config lives in ~/.config/zsh/local.d/*.zsh, sourced
# last so it wins over anything above. Shell analogue of ~/.ssh/config.d/*.conf:
# the dir isn't in the repo, so these survive `git pull`/`reset` across machines.
# (N) = null_glob, so it's a no-op when the dir is empty/absent — no error.
# ─────────────────────────────────────────────────────────────────────────────
for _localrc in ${XDG_CONFIG_HOME:-$HOME/.config}/zsh/local.d/*.zsh(N); do
  source "$_localrc"
done
unset _localrc