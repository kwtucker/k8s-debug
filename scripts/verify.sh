#!/usr/bin/env bash
# scripts/verify.sh — functional verification for the k8s-debug image.
# Tests that binaries EXECUTE, not just exist. Tolerant of differing
# --version/-V/-h flag conventions across distributions.
# Usage: make test  (or: docker run --rm <image> bash /verify.sh)
set -u
PASS=0
FAIL=0

check() { # check <label> <command...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label ($*)"
    FAIL=$((FAIL + 1))
  fi
}

check_exists() { # check_exists <label> <binary>
  local label="$1" bin="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label ($bin not on PATH)"
    FAIL=$((FAIL + 1))
  fi
}

echo "== Shell =="
check "zsh runs" zsh -c 'true'
check "starship runs" starship --version
check "fzf runs" fzf --version
check "/etc/zsh/zshenv fallback exists" test -f /etc/zsh/zshenv
check "zshenv handles uid-1000 remap" grep -q "HOME=/home/dev" /etc/zsh/zshenv

echo "== Editor =="
check "nvim runs" nvim --version
check "nvim config loads headless" nvim --headless +qa

echo "== Networking =="
check "curl" curl --version
check "wget" wget --version
check "dig" dig -v
check "ping" ping -V
check "nc" nc -h
check "ip" ip -V
check "ss" ss -V
check_exists "traceroute binary" traceroute

echo "== Filesystem / text inspection =="
check "rg" rg --version
check "fd" fd --version
check "bat" bat --version
check "tree" tree --version
check "file" file --version
check "less" less --version

echo "== Data =="
check "jq" jq --version
check "yq" yq --version

echo "== TLS =="
check "openssl" openssl version

echo "== Process / system =="
check "ps" ps --version
check "htop" htop --version
check "lsof" lsof -v
check "strace" strace -V

echo
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
