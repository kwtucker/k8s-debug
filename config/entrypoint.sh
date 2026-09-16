#!/usr/bin/env bash
# debug-entrypoint.sh — interactive-first entrypoint for k8s-debug.
# No args (plain `docker run -it`) → exec zsh.
# Args (e.g. `kubectl debug … -- zsh`) → exec them.
# Self-heals lazy.nvim if a volume ever overlays an empty data dir.
#
# Non-root support: kubectl debug subjects ephemeral containers to the target
# pod's pod-level securityContext, so debugging a pod with runAsUser: 1000
# runs THIS container as uid 1000 with /root unreadable. In that case switch
# to the pre-provisioned dev home (same shell/editor config; XDG_DATA_HOME
# stays on the shared read-only pre-warmed copy by design).
# NOTE: keep in sync with config/zsh/zshenv. `kubectl debug ... -- zsh`
# defaults to Command (overrides this ENTRYPOINT); /etc/zsh/zshenv re-applies
# the same remap for zsh when this entrypoint is bypassed. Prefer
# `kubectl debug ... --arguments-only -- zsh` so this entrypoint runs (fixes
# HOME for ALL tools, not just zsh).
set -euo pipefail

export PATH="/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ "$(id -u)" -eq 1000 ] && [ -d /home/dev ]; then
  export HOME=/home/dev
  export XDG_CONFIG_HOME=/home/dev/.config
  export XDG_CACHE_HOME=/home/dev/.cache
  export STARSHIP_CONFIG=/home/dev/.config/starship.toml
fi

LAZY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim"
if [ ! -d "$LAZY_DIR/lua" ]; then
  echo "entrypoint: lazy.nvim missing — cloning (one-time self-heal)..." >&2
  if mkdir -p "$(dirname "$LAZY_DIR")" 2>/dev/null \
    && git clone --filter=blob:none --branch=stable \
      https://github.com/folke/lazy.nvim.git "$LAZY_DIR" >&2; then
    true
  else
    echo "entrypoint: WARNING: cannot restore lazy.nvim (directory not writable?) — nvim plugins may fail to load." >&2
  fi
fi

if [ "$#" -eq 0 ]; then
  exec zsh
fi
exec "$@"
