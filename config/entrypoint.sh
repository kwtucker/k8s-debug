#!/usr/bin/env bash
# debug-entrypoint.sh — interactive-first entrypoint for k8s-debug.
# No args (plain `docker run -it`) → exec zsh.
# Args (e.g. `kubectl debug … -- zsh`) → exec them.
# Self-heals lazy.nvim if a volume ever overlays an empty data dir.
set -euo pipefail

export PATH="/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

LAZY_DIR="$HOME/.local/share/nvim/lazy/lazy.nvim"
if [ ! -d "$LAZY_DIR/lua" ]; then
  echo "entrypoint: lazy.nvim missing — cloning (one-time self-heal)..." >&2
  mkdir -p "$(dirname "$LAZY_DIR")"
  git clone --filter=blob:none --branch=stable \
    https://github.com/folke/lazy.nvim.git "$LAZY_DIR" >&2
fi

if [ "$#" -eq 0 ]; then
  exec zsh
fi
exec "$@"
