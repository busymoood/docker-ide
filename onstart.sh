#!/usr/bin/env bash
# onstart.sh — Bootstrap de l'environnement devbox.
#
# Idempotent : exécutable à chaque démarrage de conteneur.
#   1. Volume d'état (~/.local) : permissions + états outils hors volume
#   2. Station SSH : s'assurer que github.com est connu
#   3. Vérifie l'agent SSH forwardé (attente du relais si créé en parallèle)
#   4. Clone ou met à jour le repo de dotfiles (DOTFILES_REPO)
#   5. Clone ou met à jour la config NeoVim/LazyVim (NVIM_CONFIG_REPO)
#   6. Crée les symlinks de configuration (zsh, tmux, ssh)
#   7. Lance la session (zsh) si un shell interactif est demandé
#
# Usage :
#   onstart              → bootstrap + zsh (entrypoint de l'image)
#   onstart --no-shell   → bootstrap uniquement (ex: postStartCommand)
#
# Variables :
#   DOTFILES_REPO     URL du repo de dotfiles (git@… ou https://…)
#   NVIM_CONFIG_REPO  URL du repo de config NeoVim/LazyVim
#                     (défaut : git@github.com:Thejulfi/lazyvim-config.git,
#                      NVIM_CONFIG_REPO="" pour désactiver)
#   DEVBOX_SSH_RELAY  1 = recréer le socket de l'agent depuis un relais TCP
#                     (Docker Desktop, où un socket Unix non-docker ne peut
#                     pas être monté). Laisser vide pour un montage direct.
#   DEVBOX_SSH_RELAY_TARGET  cible du relais (host.docker.internal:4242)
set -euo pipefail

DOTFILES_DIR="${HOME:-/home/dev}/dotfiles"
NVIM_DIR="${HOME:-/home/dev}/.config/nvim"
NVIM_REPO="${NVIM_CONFIG_REPO-git@github.com:Thejulfi/lazyvim-config.git}"
NO_SHELL=0
[[ "${1:-}" == "--no-shell" ]] && NO_SHELL=1

log()  { printf '\033[1;34m[devbox]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[devbox][attention]\033[0m %s\n' "$*" >&2; }

# ----------------------------------------------------------------------------
# 1. Volume d'état : ~/.local est un volume nommé créé par Docker en root:root
#    (le chemin n'existe pas dans l'image) → dev ne peut rien y écrire et
#    LazyVim/Mason/opencode échouent. On ne chown que si nécessaire : pas de
#    parcours récursif inutile d'un volume déjà correct (browsers Playwright…).
# ----------------------------------------------------------------------------
LOCAL_DIR="${HOME}/.local"
mkdir -p "$LOCAL_DIR"
if [[ ! -w "$LOCAL_DIR" ]]; then
  log "Volume ${LOCAL_DIR} non inscriptible — correction des permissions…"
  sudo chown -R "$(id -u):$(id -g)" "$LOCAL_DIR" 2>/dev/null \
    || warn "Impossible de rendre ${LOCAL_DIR} inscriptible — plugins nvim indisponibles."
fi

# Certains outils écrivent dans $HOME, hors volume (donc perdus à chaque
# recréation du conteneur) : les rediriger vers le volume d'état.
#   supermaven-nvim/sm-agent → binaire + clé API dans ~/.supermaven/config.json
SUPERMAVEN_DIR="${LOCAL_DIR}/share/supermaven"
if [[ ! -L "${HOME}/.supermaven" ]]; then
  if [[ -e "${HOME}/.supermaven" ]]; then
    warn "${HOME}/.supermaven existe et n'est pas un lien — laissé intact (clé Supermaven non persistante)."
  else
    mkdir -p "$SUPERMAVEN_DIR"
    ln -s "$SUPERMAVEN_DIR" "${HOME}/.supermaven"
    log "État Supermaven persisté dans le volume (${SUPERMAVEN_DIR})"
  fi
fi

# ----------------------------------------------------------------------------
# 2. Station SSH : s'assurer que github.com est connu (clone via agent SSH)
# ----------------------------------------------------------------------------
mkdir -p "${HOME}/.ssh"
if [[ ! -f "${HOME}/.ssh/known_hosts" ]] || ! ssh-keygen -F github.com -f "${HOME}/.ssh/known_hosts" >/dev/null 2>&1; then
  ssh-keyscan -t ssh-ed25519 github.com >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
fi

# ----------------------------------------------------------------------------
# 3. Agent SSH : détection (avant tout clonage, qui en dépend)
# ----------------------------------------------------------------------------
AGENT_SOCK="${SSH_AUTH_SOCK:-/ssh-agent}"

# Docker Desktop (macOS, Windows/WSL2) ne peut pas monter un socket Unix
# non-docker : `DEVBOX_SSH_RELAY=1` demande de recréer le socket local depuis
# le relais TCP de l'hôte. Le helper arme aussi un rattrapage si l'agent est
# verrouillé au démarrage (Bitwarden).
if [[ "${DEVBOX_SSH_RELAY:-0}" == "1" ]] && command -v devbox-agent-relay >/dev/null 2>&1; then
  devbox-agent-relay start || warn "Relais agent SSH indisponible — diagnostic : devbox-agent-relay doctor"
fi

# Le socket peut être créé de façon asynchrone (relais socat lancé par un
# postStartCommand en parallèle) : on lui laisse jusqu'à 5 s pour apparaître.
for _ in $(seq 1 25); do
  [[ -S "$AGENT_SOCK" ]] && break
  sleep 0.2
done

AGENT_OK=0
if [[ -S "$AGENT_SOCK" ]]; then
  if ssh-add -l >/dev/null 2>&1; then
    AGENT_OK=1
    log "Agent SSH OK ($(ssh-add -l 2>/dev/null | wc -l | tr -d ' ') clé(s) disponible(s))"
  else
    warn "Socket agent présent mais vide — Bitwarden verrouillé ?"
  fi
else
  warn "Aucun agent SSH forwardé — git sur GitHub nécessitera HTTPS + PAT."
fi

# ----------------------------------------------------------------------------
# 4. Repo de dotfiles : clone ou pull
# ----------------------------------------------------------------------------
REPO="${DOTFILES_REPO:-}"

# Si l'agent SSH est opérationnel et que l'URL est HTTPS, convertir en SSH :
# permet de cloner des repos privés via la clé forwardée (Bitwarden, etc.)
if [[ -n "$REPO" && "$REPO" == https://github.com/* && "$AGENT_OK" -eq 1 ]]; then
  REPO="git@github.com:${REPO#https://github.com/}"
  log "Agent SSH détecté → clonage via git@github.com"
fi

if [[ -z "$REPO" ]]; then
  warn "DOTFILES_REPO n'est pas défini — configurations non installées."
  warn "Lancez avec : -e DOTFILES_REPO=https://github.com/<user>/<dotfiles>.git"
elif [[ "$REPO" == git@* && "$AGENT_OK" -eq 0 ]]; then
  warn "Agent SSH indisponible → dotfiles non clonées (${REPO})."
elif [[ -d "${DOTFILES_DIR}/.git" ]]; then
  log "Mise à jour des dotfiles (${DOTFILES_DIR})…"
  git -C "${DOTFILES_DIR}" pull --ff-only || warn "git pull a échoué — dotfiles conservées"
else
  log "Clonage des dotfiles depuis ${REPO}…"
  rm -rf "${DOTFILES_DIR}"
  git clone "${REPO}" "${DOTFILES_DIR}" || warn "Le clone a échoué — vérifiez l'URL ou l'agent SSH"
fi

# ----------------------------------------------------------------------------
# 5. Config NeoVim / LazyVim : dépôt dédié, prioritaire sur dotfiles/nvim
# ----------------------------------------------------------------------------
# Ce dépôt est privé : le clone exige l'agent SSH forwardé. Sans agent,
# l'avertissement est explicite et la tentative sera refaite au prochain
# démarrage (jamais de dossier à moitié cloné : clone dans un tmp puis mv).
if [[ -n "$NVIM_REPO" ]]; then
  if [[ "$NVIM_REPO" == git@* && "$AGENT_OK" -eq 0 ]]; then
    warn "Agent SSH indisponible → config NeoVim non clonée (nvim restera nu)."
  elif [[ -d "${NVIM_DIR}/.git" ]]; then
    log "Mise à jour de la config NeoVim (${NVIM_DIR})…"
    git -C "${NVIM_DIR}" pull --ff-only || warn "git pull nvim a échoué — config conservée"
  elif [[ -e "${NVIM_DIR}" ]]; then
    warn "${NVIM_DIR} existe mais n'est pas un dépôt git — laissé intact."
  else
    log "Clonage de la config NeoVim depuis ${NVIM_REPO}…"
    nvim_tmp="${HOME}/.config/.nvim.clone.$$"
    rm -rf "$nvim_tmp"
    if git clone "$NVIM_REPO" "$nvim_tmp"; then
      mv "$nvim_tmp" "$NVIM_DIR"
      log "Config LazyVim installée"
    else
      rm -rf "$nvim_tmp"
      warn "Le clone de la config NeoVim a échoué — nvim restera nu ce démarrage."
    fi
  fi
fi

# ----------------------------------------------------------------------------
# 6. Symlinks de configuration
# ----------------------------------------------------------------------------
mkdir -p "${HOME}/.config"

# Zsh : layout dotfiles/zsh/.zshrc, avec repli sur .zshrc à la racine du repo
for src in "${DOTFILES_DIR}/zsh/.zshrc" "${DOTFILES_DIR}/.zshrc"; do
  [[ -f "$src" ]] || continue
  ln -sf "$src" "${HOME}/.zshrc"
  log "Config Zsh liée"
  break
done

# Tmux : layout dotfiles/tmux/.tmux.conf, avec repli sur .tmux.conf à la racine
for src in "${DOTFILES_DIR}/tmux/.tmux.conf" "${DOTFILES_DIR}/.tmux.conf"; do
  [[ -f "$src" ]] || continue
  ln -sf "$src" "${HOME}/.tmux.conf"
  log "Config Tmux liée"
  break
done

# NeoVim : le dépôt dédié (étape 4) est prioritaire ; le symlink dotfiles/nvim
# ne s'applique que si ~/.config/nvim est encore libre.
if [[ -d "${DOTFILES_DIR}/nvim" ]]; then
  if [[ -e "${NVIM_DIR}" ]]; then
    warn "${NVIM_DIR} déjà fourni (dépôt dédié) — symlink dotfiles/nvim ignoré."
  else
    ln -sfn "${DOTFILES_DIR}/nvim" "${NVIM_DIR}"
    log "Config LazyVim liée (dotfiles)"
  fi
fi

# LazyGit : layout dotfiles/lazygit/config.yml (éditeur nvim par défaut)
if [[ -f "${DOTFILES_DIR}/lazygit/config.yml" ]]; then
  mkdir -p "${HOME}/.config/lazygit"
  ln -sf "${DOTFILES_DIR}/lazygit/config.yml" "${HOME}/.config/lazygit/config.yml"
  log "Config LazyGit liée"
fi

# Git : nvim comme éditeur des messages de commit (si non déjà défini)
if [[ "$(git config --global core.editor || true)" != "nvim" ]]; then
  git config --global core.editor nvim
  log "git core.editor = nvim"
fi

# SSH : config + clés publiques uniquement (jamais de clé privée)
if [[ -d "${DOTFILES_DIR}/ssh" ]]; then
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  cp -r "${DOTFILES_DIR}/ssh/"* "${HOME}/.ssh/" 2>/dev/null || true
  find "${HOME}/.ssh" -name "*private*" -not -name "*.pub" -delete 2>/dev/null || true
  chmod 644 "${HOME}/.ssh/"*.pub 2>/dev/null || true
  chmod 600 "${HOME}/.ssh/config" 2>/dev/null || true
  log "Config SSH installée (sans clé privée)"
fi

# Zsh comme shell par défaut
if command -v zsh >/dev/null 2>&1; then
  if [[ "$SHELL" != "$(which zsh)" ]]; then
    sudo chsh -s "$(which zsh)" "$(whoami)" 2>/dev/null || true
  fi
fi

# ----------------------------------------------------------------------------
# 7. Session
# ----------------------------------------------------------------------------
log "Environnement prêt. zsh · tmux · nvim (LazyVim) · lazygit · opencode · rg/fd/fzf"

if [[ "$NO_SHELL" -eq 1 ]]; then
  exit 0
fi

if [[ $# -gt 0 ]]; then
  exec "$@"
elif [[ -t 0 ]]; then
  exec zsh -l
else
  # Pas de TTY (ex: docker run sans -it) : shell via docker exec à la demande.
  log "Astuce : entrez dans le conteneur avec : docker exec -it <conteneur> zsh"
  while :; do sleep 3600; done
fi
