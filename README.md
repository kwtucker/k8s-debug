# k8s-debug

An ephemeral Kubernetes troubleshooting container: small, fast, familiar, disposable.
Not a development environment — that remains [`kwtucker/dotfiles`](https://github.com/kwtucker/dotfiles)
(`dotfiles-devenv` image). This image is for `kubectl debug` sessions and quick
`docker run` inspections.

Prompt shows `🐳 debug ❯` so you always know you are inside the debug container.

## Included tools

Shell:

- `zsh` (+ syntax-highlighting, autosuggestions, fzf-tab via Antigen, pre-warmed)
- `starship` (debug prompt), `fzf`

Editor:

- `nvim` v0.11.6 with your LazyVim config from dotfiles (pinned commit, symlinked —
  never a forked copy). Plugins + treesitter parsers pre-warmed. **No Mason LSPs.**

Networking:

- `curl`, `wget`, `iproute2` (`ip`, `ss`), `iputils-ping`, `dnsutils` (`dig`),
  `netcat-openbsd` (`nc`), `socat`, `traceroute`
- `getent` (glibc/`libc-bin`: NSS + `resolv.conf` checks, e.g.
  `getent hosts service.namespace`)

Filesystem / text:

- `ripgrep` (`rg`), `fd`, `bat`, `less`, `tree`, `file`

Data:

- `jq`, `yq`, `grpcurl` (gRPC reflection: `list`, `describe`, calls)
- `python3` (ad-hoc scripting, e.g. `curl -s ... | python3 -m json.tool`)

TLS:

- `openssl`, `ca-certificates`

Process / system:

- `procps` (`ps`), `htop`, `lsof`, `strace`

Deliberately excluded: Go/Node/Rust, Terraform, Helm, kubectl (use host-side
`kubectl`; the debug container inherits the pod's usually permission-less
ServiceAccount), Docker/AWS CLIs, language
servers, compilers, tmux, GUI tools, fonts. If a debugging session proves a new
tool is needed, add it — otherwise keep the image lean.

## Usage

Local Docker:

```bash
make build
make run            # mounts $PWD at /workspace, drops into zsh
cd /workspace && nvim .
make test           # functional verification of every tool
```

Kubernetes (ephemeral debug container):

```bash
kubectl debug -it pod/<pod> \
  --image=ghcr.io/kwtucker/k8s-debug:v0.1.3 \
  --profile=general --share-processes --target=<container> \
  --arguments-only -- zsh
```

`--arguments-only` is required: without it `kubectl debug ... -- zsh` sets
`Command=[zsh]`, which overrides the image `ENTRYPOINT` (`debug-entrypoint.sh`)
and skips the uid-1000 `HOME=/home/dev` remap. The symptom is a bare
`pod-name%` prompt instead of `🐳 debug ❯`. The image also ships
`/etc/zsh/zshenv` as a fallback so interactive `zsh` self-heals even when the
entrypoint is bypassed, but `--arguments-only` fixes `HOME` for *all* tools
(`nvim`, etc.), not just `zsh` — always use it.

Prefer pinned tags (`:v0.1.0`, `:sha-…`) over `:latest`. If you keep the `kdebug`
helper from dotfiles, point it at this image:

```bash
export KDEBUG_IMAGE=ghcr.io/kwtucker/k8s-debug:v0.1.3
kdebug
```

> The `kdebug` helper must also pass `--arguments-only` (and should not claim
> the debug image always runs as root — a target pod with `runAsUser: 1000`
> runs the debug container as uid 1000).

## Examples

HTTP connectivity:

```bash
curl -v http://service:8080
curl -v https://service
```

DNS:

```bash
dig service.namespace.svc.cluster.local
```

Listening ports / connections:

```bash
ss -lntp
```

TCP probing (`socat` covers what `nc` cannot — TLS, UNIX sockets):

```bash
echo -e "GET / HTTP/1.0\r\n\r\n" | socat - TCP:service:8080
```

gRPC (plaintext in-cluster; drop `-plaintext` for TLS):

```bash
grpcurl -plaintext service:8080 list
grpcurl -plaintext service:8080 describe package.Service
grpcurl -plaintext -d '{"key":"value"}' service:8080 package.Service/Method
```

Process inspection (shares the target's process namespace with `--share-processes`):

```bash
ps aux
htop
lsof -i
```

Filesystem inspection:

```bash
rg "pattern" /path
fd . /path
tree /path
nvim /path/to/file
```

JSON / YAML:

```bash
curl -s http://service:8080/config | jq .
yq . /path/to/config.yaml
```

TLS:

```bash
openssl s_client -connect service:443
```

Neovim:

```bash
cd /workspace && nvim .
```

## Limitations

Some operations require additional Linux capabilities or privileges depending on
what is being inspected — this is a Kubernetes invocation concern, not an image
defect:

- `strace -p <pid>` against another container's processes may need
  `SYS_PTRACE` / shared PIDs (`--share-processes`).
- Packet capture tooling (e.g. `tcpdump`, intentionally not installed) would need
  `NET_RAW` / `NET_ADMIN`.
- Targets running as non-root trigger a `kubectl debug --profile=general`
  warning: the profile's extra capabilities cannot fully apply. Stay as-is, or
  re-run with a `--custom` profile granting `runAsUser: 0` when root is truly needed.
- `kubectl debug` itself needs `get pods` + `update pods/ephemeralcontainers`.
  A bare ServiceAccount context returns `Forbidden` — switch to an admin context.
- The debug container inherits the target pod's **pod-level securityContext**:
  debugging a pod with `runAsUser: 1000` runs this container as uid 1000, not
  root. The image handles both cases with the same prompt and config — root
  uses `/root`, uid 1000 uses the pre-provisioned `dev` home (`/home/dev`)
  with a shared read-only copy of the pre-warmed editor data. Other uids get
  a degraded shell (no provisioned home); use a `--custom` profile with
  `runAsUser: 0` if you truly need root there.

The image defaults to **root** (standard for ephemeral debug containers).
It holds no persistent state: treat every session as disposable.

## Reproducibility

`Dockerfile` clones `kwtucker/dotfiles` at the pinned `DOTFILES_REF` commit
(default set in `Makefile`, overridable via `--build-arg`). Bumping the Neovim
config = bumping one SHA, reviewable in git history. The image never tracks
`main` implicitly.

> Prerequisite: dotfiles `nvim/lua/plugins/mason.lua` must honor `K8S_DEBUG=1`
> by ensuring zero packages (otherwise the first `nvim` launch async-installs
> the full LSP set into the ephemeral container). The image sets `K8S_DEBUG=1`.

## Versioning

Tags: `vX.Y.Z` + `latest` + `sha-<short>`. Prefer versioned tags in
`kubectl debug` invocations.
