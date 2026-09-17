# k8s-debug — ephemeral Kubernetes troubleshooting container.
#
# Build from the repo root:
#   docker build -t ghcr.io/kwtucker/k8s-debug:local .
#   docker build --build-arg DOTFILES_REF=<sha> -t ghcr.io/kwtucker/k8s-debug:local .
#
# Design notes:
# - Ubuntu 24.04 (glibc): same package names as dotfiles-devenv, apt tooling,
#   Neovim 0.11.x compatible. Deliberately NOT devenv: no Go/Node/Rust,
#   no Terraform/Helm/Docker/AWS CLIs, no tmux, no language servers.
# - Runs as root by default, but ALSO supports uid 1000: kubectl debug
#   inherits the target pod's pod-level securityContext, so debugging a pod
#   with runAsUser: 1000 (e.g. the workspace pod) lands this container in
#   uid 1000 with /root unreadable. A pre-provisioned `dev` user (uid 1000,
#   HOME /home/dev) plus a shared world-readable data dir (/opt/data:
#   pre-warmed nvim plugins/parsers, fzf completions) keeps the full shell
#   and editor working in both cases. Other uids are out of scope.
# - Dotfiles consumed at a PINNED commit (ARG DOTFILES_REF), never `main`.
#   Bump = one-line, reviewable change.
# - Neovim config symlinked from the pinned dotfiles clone; Lazy.nvim plugins
#   pre-warmed, Mason LSPs intentionally skipped (see K8S_DEBUG below).

FROM ubuntu:24.04

ARG TARGETARCH
# Pinned dotfiles commit — source of truth for nvim config.
# Refresh: pick a tested commit from kwtucker/dotfiles, bump here + in Makefile.
ARG DOTFILES_REF=5ee050c368f192253717616aa2ec3b9a772a3910

# Pinned binary versions (match image/mise.workspace.toml known-good set).
ARG NVIM_VERSION=0.11.6
ARG STARSHIP_VERSION=1.24.2
ARG FZF_VERSION=0.54.3
ARG YQ_VERSION=4.53.6
ARG GRPCURL_VERSION=1.9.4

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/root \
    XDG_CONFIG_HOME=/root/.config \
    XDG_CACHE_HOME=/root/.cache \
    XDG_DATA_HOME=/opt/data \
    SHELL=/bin/zsh \
    EDITOR=nvim \
    STARSHIP_CONFIG=/root/.config/starship.toml \
    K8S_DEBUG=1

# NOTE: XDG_DATA_HOME is a shared world-readable dir (not per-user): it holds
# only runtime-readonly payload (nvim plugins/parsers, fzf completions), so
# both root and the uid-1000 dev user below can use one pre-warmed copy.
# Per-user writable state (history, compdump, antigen runtime) stays under
# each $HOME. The entrypoint re-points HOME/XDG_CONFIG/XDG_CACHE (never
# XDG_DATA_HOME) when running as uid 1000.

# Non-root debug identity: matches the runAsUser: 1000 convention used by the
# workspace pod (see dotfiles image/k8s/dev-pod.yaml). kubectl debug subjects
# ephemeral containers to the target pod's pod-level securityContext.
# Ubuntu ships an `ubuntu` user on uid 1000 — remove it so `dev` can take it.
RUN (id ubuntu >/dev/null 2>&1 && userdel -r ubuntu || true) \
    && useradd -m -s /usr/bin/zsh -u 1000 dev

# Base deps: shell + networking/debugging + filesystem/data/TLS/process tools.
# iproute2 provides `ss` + `ip`; dnsutils provides `dig`; fd-find/bat have
# Debian-style names (fdfind/batcat) — symlinked below to upstream names.
RUN apt-get update && apt-get install -y --no-install-recommends \
      zsh git curl wget ca-certificates less locales unzip \
      iproute2 iputils-ping dnsutils netcat-openbsd socat traceroute \
      ripgrep fd-find bat less tree file \
      jq python3 openssl \
      procps htop lsof strace \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen C.UTF-8 \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# Pinned release binaries (no mise: keeps Go/Node toolchains out of the image).
# TARGETARCH handling keeps a future arm64 build working.
RUN set -eux; \
    case "$TARGETARCH" in \
      arm64) NVIM_ARCH=arm64; BINARY_ARCH=arm64; GRPCURL_ARCH=arm64 ;; \
      *)     NVIM_ARCH=x86_64; BINARY_ARCH=amd64; GRPCURL_ARCH=x86_64 ;; \
    esac; \
    curl -fsSL -o /tmp/nvim.tar.gz \
      "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz"; \
    mkdir -p /opt/nvim && tar -xzf /tmp/nvim.tar.gz -C /opt/nvim --strip-components=1; \
    ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim; \
    curl -fsSL -o /tmp/starship.tar.gz \
      "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${NVIM_ARCH}-unknown-linux-gnu.tar.gz"; \
    tar -xzf /tmp/starship.tar.gz -C /usr/local/bin; \
    curl -fsSL -o /tmp/fzf.tar.gz \
      "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${BINARY_ARCH}.tar.gz"; \
    tar -xzf /tmp/fzf.tar.gz -C /usr/local/bin; \
    curl -fsSL -o /usr/local/bin/yq \
      "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${BINARY_ARCH}"; \
    chmod +x /usr/local/bin/yq; \
    curl -fsSL -o /tmp/grpcurl.tar.gz \
      "https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_${GRPCURL_ARCH}.tar.gz"; \
    tar -xzf /tmp/grpcurl.tar.gz -C /usr/local/bin grpcurl; \
    rm -f /tmp/nvim.tar.gz /tmp/starship.tar.gz /tmp/fzf.tar.gz /tmp/grpcurl.tar.gz; \
    for b in nvim starship fzf yq grpcurl; do command -v "$b" >/dev/null || { echo "MISSING binary: $b"; exit 1; }; done

# Dotfiles at the pinned ref — nvim config source of truth.
RUN git clone --filter=blob:none https://github.com/kwtucker/dotfiles /opt/dotfiles \
    && git -C /opt/dotfiles checkout "$DOTFILES_REF" \
    && git -C /opt/dotfiles rev-parse HEAD

# Shell + editor wiring. nvim config is a symlink into the pinned clone
# (never a forked copy). antigen.zsh is fetched from upstream (same content
# dotfiles vendors via `make zsh`).
COPY config/zsh/.zshrc /root/.zshrc
COPY config/zsh/zshenv /etc/zsh/zshenv
COPY config/starship-debug.toml /root/.config/starship.toml
COPY config/entrypoint.sh /usr/local/bin/debug-entrypoint.sh
COPY scripts/verify.sh /usr/local/bin/k8s-debug-verify.sh
RUN mkdir -p /root/.config /root/.cache/zsh "${XDG_DATA_HOME}/zsh/completions" /root/.local/bin /workspace \
    && ln -sfn /opt/dotfiles/nvim /root/.config/nvim \
    && curl -fsSL https://raw.githubusercontent.com/zsh-users/antigen/develop/bin/antigen.zsh \
         -o /root/.config/zsh-antigen.zsh \
    && chmod +x /usr/local/bin/debug-entrypoint.sh /usr/local/bin/k8s-debug-verify.sh \
    && (command -v fzf >/dev/null && fzf --zsh > "${XDG_DATA_HOME}/zsh/completions/_fzf" || true)

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Pre-warm: one non-interactive login shell so antigen clones its bundles and
# compinit writes its dump into this layer (same trick as devenv).
RUN zsh -ic true

# Dev-user skeleton: same shell/editor config as root, owned by dev. Antigen
# bundles are copied (not re-cloned: works without cluster egress), but the
# generated caches are dropped — they embed absolute /root paths, so the
# first dev shell regenerates them offline in seconds.
# /opt/data + /opt/dotfiles are made world-readable: the dev user consumes
# the single shared pre-warmed copy, no 200MB+ duplication.
RUN mkdir -p /home/dev/.config /home/dev/.cache/zsh /home/dev/.local/share/zsh /home/dev/.local/bin \
    && cp /root/.zshrc /home/dev/.zshrc \
    && cp /root/.config/starship.toml /home/dev/.config/starship.toml \
    && cp /root/.config/zsh-antigen.zsh /home/dev/.config/zsh-antigen.zsh \
    && ln -sfn /opt/dotfiles/nvim /home/dev/.config/nvim \
    && cp -r /root/.antigen /home/dev/.antigen \
    && rm -f /home/dev/.antigen/init.zsh* /home/dev/.antigen/.zcompdump* /home/dev/.antigen/.resources /home/dev/.antigen/debug.log \
    && chown -R dev:dev /home/dev \
    && chmod -R a+rX /opt/data /opt/dotfiles

# Pre-warm editor: Lazy.nvim + plugins + treesitter parsers, headless.
# `Lazy! sync` (NOT `install`): verified in devenv that `sync` fully engages
# headless while `install` silently no-ops. No MasonInstall: K8S_DEBUG=1 tells
# mason.lua to ensure nothing (requires the K8S_DEBUG guard upstream).
# nvim-treesitter needs a C compiler to build parsers, but compilers are
# excluded from the final image by design (§7) — so gcc is installed and
# purged WITHIN this single layer: the compiled parser .so files persist
# while the compiler leaves no trace in the shipped image.
# NOTE: `sync` only clones plugins; parsers install when nvim-treesitter
# loads. `:TSInstall <lang>` forces that load, and its config installs every
# missing ensure_installed parser (~40 langs) into .../nvim/site/parser/.
# `:sleep` lets the async jobs finish headless (verified: 45s suffices
# locally; 120s gives CI margin). The `test -n` fails the build LOUD if no
# parsers materialized — a highlighter-less editor must never ship silently.
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf "${XDG_DATA_HOME}/nvim/lazy/lazy.nvim" \
    && git clone --filter=blob:none --branch=stable \
         https://github.com/folke/lazy.nvim.git "${XDG_DATA_HOME}/nvim/lazy/lazy.nvim" \
    && test -d "${XDG_DATA_HOME}/nvim/lazy/lazy.nvim/lua" \
    && { nvim --headless "+Lazy! sync" +qa || true; } \
    && test -d "${XDG_DATA_HOME}/nvim/lazy/lazy.nvim/lua" \
    && { nvim --headless -c "TSInstall yaml" -c "sleep 120" +qa || true; } \
    && test -n "$(ls -A "${XDG_DATA_HOME}/nvim/site/parser" 2>/dev/null)" \
    && apt-get purge -y --auto-remove gcc libc6-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /root/.cache/* /tmp/* \
    && chmod -R a+rX /opt/data /opt/dotfiles

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/debug-entrypoint.sh"]
CMD ["zsh"]
