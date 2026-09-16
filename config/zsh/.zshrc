#!/usr/bin/env zsh
# Slim interactive zshrc for the k8s-debug container.
# Derived from kwtucker/dotfiles zsh/.zshrc + env.zsh, with all
# workstation-only dependencies removed:
#   NO macOS/Homebrew paths, NO mise, NO WHALEBYTE secrets,
#   NO gohome/dotpull/dotpush, NO tldr/exa, NO git-open (needs a browser).
# Works standalone as /root/.zshrc with HOME=/root.

bindkey -e

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

export HIST_STAMPS="mm/dd/yyyy"
# History lives under XDG_STATE_HOME (per-user, writable) — never under the
# shared read-only XDG_DATA_HOME, or every shell exit would log a write error.
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
mkdir -p "${HISTFILE:h}"
export HISTSIZE=999999999
export SAVEHIST=${HISTSIZE}

export EDITOR=nvim
export PAGER=less

export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v fzf >/dev/null 2>&1; then
  # fzf keybindings (Ctrl-R/T). stderr silenced: fzf 0.54's --zsh script
  # eval-restores every shell option including `zle`, which zsh refuses to
  # toggle this way ("can't change option: zle"). Harmless — real options
  # are still restored, zle stays on.
  eval "$(fzf --zsh 2>/dev/null)" 2>/dev/null || true
fi

ZSH_COMPLETIONS_DIR="${XDG_DATA_HOME}/zsh/completions"
mkdir -p "$ZSH_COMPLETIONS_DIR"
fpath=($ZSH_COMPLETIONS_DIR $fpath)

autoload -Uz compinit
if [[ -n ${XDG_CACHE_HOME}/zsh/zcompdump(#qN.mh+24) ]]; then
  compinit -i -d $XDG_CACHE_HOME/zsh/zcompdump
else
  compinit -C $XDG_CACHE_HOME/zsh/zcompdump
fi

# Antigen plugins (pre-warmed at build time). No git-open: needs a browser.
source ${XDG_CONFIG_HOME}/zsh-antigen.zsh 2>/dev/null \
  || source $HOME/.config/zsh-antigen.zsh 2>/dev/null || true
if (( $+functions[antigen] )); then
  antigen bundle zsh-users/zsh-syntax-highlighting
  antigen bundle zsh-users/zsh-autosuggestions
  antigen bundle Aloxaf/fzf-tab
  antigen apply
fi

# --- Portable aliases (subset of dotfiles zsh/aliases.zsh) ---
alias reload!='exec "$SHELL" -l'

alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

alias c='clear'
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

alias ls='ls -F --color'
alias la="ls -lah"
alias ll="ls -lh"

# --- Minimal portable functions ---
function up() {
  cd .. && find . -maxdepth 1 -type f -exec ls -l {} \; | awk '{print $9}'
}
