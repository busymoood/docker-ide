#!/usr/bin/env bash
# onstart.sh — devbox environment bootstrap.
#
# Idempotent: runs at every container start.
#   1. State volume (~/.local): permissions + tool state outside the image
#   2. SSH station: make sure github.com is known
#   3. Check the forwarded SSH agent (wait for a relay started in parallel)
#   4. git core.editor = nvim
#   5. Zsh as the default shell
#   6. Start the session (zsh) when an interactive shell is requested
#
# NB: configs (zsh, tmux, NeoVim/LazyVim, lazygit) are baked into the image
# (/opt/devbox-config + symlinks in $HOME). No network clone at startup, even
# without an SSH agent. The SSH relay is still useful for git on the workspace.
#
# Usage:
#   onstart              → bootstrap + zsh (image entrypoint)
#   onstart --no-shell   → bootstrap only (e.g. postStartCommand)
#
# Variables:
#   DEVBOX_SSH_RELAY          1 = recreate the agent socket from a TCP relay
#                             (Docker Desktop, where a non-Docker Unix socket
#                             cannot be mounted). Leave empty for direct mount.
#   DEVBOX_SSH_RELAY_TARGET   relay target (host.docker.internal:4242)
set -euo pipefail

NO_SHELL=0
[[ "${1:-}" == "--no-shell" ]] && NO_SHELL=1

log()  { printf '\033[1;34m[devbox]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[devbox][warning]\033[0m %s\n' "$*" >&2; }

# ----------------------------------------------------------------------------
# 1. State volume: ~/.local is a named volume created by Docker as root:root
#    (the path does not exist in the image), so `dev` cannot write to it and
#    LazyVim/Mason/opencode fail. Only chown when needed: no pointless recursive
#    walk of an already-correct volume (Playwright browsers…).
# ----------------------------------------------------------------------------
LOCAL_DIR="${HOME}/.local"
mkdir -p "$LOCAL_DIR"
if [[ ! -w "$LOCAL_DIR" ]]; then
  log "Volume ${LOCAL_DIR} is not writable — fixing permissions…"
  sudo chown -R "$(id -u):$(id -g)" "$LOCAL_DIR" 2>/dev/null \
    || warn "Could not make ${LOCAL_DIR} writable — nvim plugins unavailable."
fi

# Some tools write to $HOME, outside the volume (and thus lost on container
# recreation): redirect them into the state volume.
#   supermaven-nvim/sm-agent → binary + API key in ~/.supermaven/config.json
SUPERMAVEN_DIR="${LOCAL_DIR}/share/supermaven"
if [[ ! -L "${HOME}/.supermaven" ]]; then
  if [[ -e "${HOME}/.supermaven" ]]; then
    warn "${HOME}/.supermaven exists and is not a symlink — left as is (Supermaven key not persisted)."
  else
    mkdir -p "$SUPERMAVEN_DIR"
    ln -s "$SUPERMAVEN_DIR" "${HOME}/.supermaven"
    log "Supermaven state persisted in the volume (${SUPERMAVEN_DIR})"
  fi
fi

# ----------------------------------------------------------------------------
# 2. SSH station: make sure github.com is known (git on the workspace)
# ----------------------------------------------------------------------------
mkdir -p "${HOME}/.ssh"
if [[ ! -f "${HOME}/.ssh/known_hosts" ]] || ! ssh-keygen -F github.com -f "${HOME}/.ssh/known_hosts" >/dev/null 2>&1; then
  ssh-keyscan -t ssh-ed25519 github.com >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
fi

# ----------------------------------------------------------------------------
# 3. SSH agent: detection
# ----------------------------------------------------------------------------
AGENT_SOCK="${SSH_AUTH_SOCK:-/ssh-agent}"

# Docker Desktop (macOS, Windows/WSL2) cannot mount a non-Docker Unix socket:
# `DEVBOX_SSH_RELAY=1` asks to recreate the local socket from the host TCP
# relay. The helper also arms a retry if the agent is locked at startup
# (Bitwarden).
if [[ "${DEVBOX_SSH_RELAY:-0}" == "1" ]] && command -v devbox-agent-relay >/dev/null 2>&1; then
  devbox-agent-relay start || warn "SSH agent relay unavailable — diagnose with: devbox-agent-relay doctor"
fi

# The socket may be created asynchronously (socat relay started by a parallel
# postStartCommand): allow up to 5 s for it to appear.
for _ in $(seq 1 25); do
  [[ -S "$AGENT_SOCK" ]] && break
  sleep 0.2
done

if [[ -S "$AGENT_SOCK" ]]; then
  if ssh-add -l >/dev/null 2>&1; then
    log "SSH agent OK ($(ssh-add -l 2>/dev/null | wc -l | tr -d ' ') key(s) available)"
  else
    warn "Agent socket present but empty — Bitwarden locked?"
  fi
else
  warn "No forwarded SSH agent — git on GitHub will need HTTPS + PAT."
fi

# ----------------------------------------------------------------------------
# 4. Git: nvim as the commit message editor (unless already set). lazygit's
# `C`/`R` commands go through this setting; file editing (`e`) uses lazygit's
# own config (os.editPreset: nvim-remote).
# Tolerant: ~/.gitconfig may be a single-file bind mount where git cannot
# replace the file (no rename) — must not interrupt onstart.
# ----------------------------------------------------------------------------
if [[ "$(git config --global core.editor || true)" != "nvim" ]]; then
  if git config --global core.editor nvim 2>/dev/null; then
    log "git core.editor = nvim"
  else
    warn "Could not write git core.editor (read-only git config?)."
  fi
fi

# ----------------------------------------------------------------------------
# 5. Zsh as the default shell
# ----------------------------------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
  if [[ "$SHELL" != "$(which zsh)" ]]; then
    sudo chsh -s "$(which zsh)" "$(whoami)" 2>/dev/null || true
  fi
fi

# ----------------------------------------------------------------------------
# 6. Session
# ----------------------------------------------------------------------------
log "Environment ready (baked configs): zsh · tmux · nvim (LazyVim) · lazygit (nvim editor) · opencode · rg/fd/fzf"

if [[ "$NO_SHELL" -eq 1 ]]; then
  exit 0
fi

if [[ $# -gt 0 ]]; then
  exec "$@"
elif [[ -t 0 ]]; then
  exec zsh -l
else
  # No TTY (e.g. docker run without -it): enter via docker exec on demand.
  log "Tip: enter the container with: docker exec -it <container> zsh"
  while :; do sleep 3600; done
fi
