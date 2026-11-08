#!/usr/bin/env bash
# devbox.sh — Lancer l'environnement devbox sur n'importe quelle hôte.
#
# Détecte automatiquement l'agent SSH disponible :
#   1. $SSH_AUTH_SOCK              (session `ssh -A`, pont WSL déjà lancé, etc.)
#   2. ~/.bitwarden-ssh-agent.sock (macOS — agent Bitwarden, chemin par défaut)
#   3. ~/.ssh/agent.sock           (WSL2 — pont npiperelay/socat)
#
# Docker natif (VPS, Raspberry Pi, WSL2) : socket monté sur /ssh-agent.
# Docker Desktop (macOS, Windows/WSL2) : un socket Unix non-docker ne peut pas
# être monté → relais TCP de l'hôte (launchd socat:4242) et le conteneur
# recrée le socket local via `devbox-agent-relay`.
#
# Variables :
#   DEVBOX_IMAGE       image docker                     (ghcr.io/busymoood/dotfiles-docker:latest)
#   DEVBOX_NAME        nom du conteneur permanent       (devbox)
#   DEVBOX_STATE       volume d'état                    (devbox-home)
#   DEVBOX_WORKSPACE   dossier monté sur /workspace     ($PWD pour run, /srv/projets pour up)
#   DOTFILES_REPO      URL du repo de dotfiles          (obligatoire pour run/up)
#   NVIM_CONFIG_REPO   URL du repo de config NeoVim/LazyVim (optionnel ; défaut
#                      embarqué dans l'image : git@…/lazyvim-config.git, "" = désactivé)
#   DEVBOX_SSH_RELAY_TARGET  cible du relais TCP        (host.docker.internal:4242)
#   DEVBOX_EXTRA_ARGS  arguments docker supplémentaires (ex: "-p 3000:3000")
set -euo pipefail

IMAGE="${DEVBOX_IMAGE:-ghcr.io/busymoood/dotfiles-docker:latest}"
NAME="${DEVBOX_NAME:-devbox}"
STATE_VOLUME="${DEVBOX_STATE:-devbox-home}"

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

command="${1:-run}"
case "$command" in
  -h|--help|help) usage ;;
esac

# ---------------------------------------------------------------------------
# Agent SSH : détection
# ---------------------------------------------------------------------------
detect_ssh_socket() {
  local sock
  sock="${SSH_AUTH_SOCK:-}"
  if [[ -n "$sock" && -S "$sock" ]]; then echo "$sock"; return 0; fi

  sock="${HOME}/.bitwarden-ssh-agent.sock"   # macOS · Bitwarden
  [[ -S "$sock" ]] && { echo "$sock"; return 0; }

  sock="${HOME}/.ssh/agent.sock"             # WSL2 · pont npiperelay/socat
  [[ -S "$sock" ]] && { echo "$sock"; return 0; }

  return 1
}

docker_desktop() {
  docker info --format '{{.OperatingSystem}}' 2>/dev/null | grep -qi "docker desktop"
}

SSH_ARGS=()
if sock="$(detect_ssh_socket)"; then
  if docker_desktop; then
    # Docker Desktop ne peut pas monter un socket Unix non-docker : on passe
    # par le relais TCP de l'hôte (launchd socat sur 4242) et l'image recrée
    # le socket local via `devbox-agent-relay`.
    SSH_ARGS=(
      -e "SSH_AUTH_SOCK=/tmp/ssh-agent.sock"
      -e "DEVBOX_SSH_RELAY=1"
      -e "DEVBOX_SSH_RELAY_TARGET=${DEVBOX_SSH_RELAY_TARGET:-host.docker.internal:4242}"
    )
    echo "[devbox] Docker Desktop → relais TCP de l'agent SSH (${DEVBOX_SSH_RELAY_TARGET:-host.docker.internal:4242})"
    echo "         (Mac : service launchd com.busymoood.socat-ssh-agent)"
  else
    SSH_ARGS=(-v "${sock}:/ssh-agent" -e "SSH_AUTH_SOCK=/ssh-agent")
    echo "[devbox] Agent SSH détecté : ${sock}"
  fi
else
  echo "[devbox] Aucun agent SSH détecté — auth git par clé indisponible dans le conteneur." >&2
  echo "         (Mac : ssh -A vers l'hôte · WSL : relancez le pont npiperelay/socat)" >&2
fi

require_repo() {
  [[ -n "${DOTFILES_REPO:-}" ]] || {
    echo "ERREUR : DOTFILES_REPO doit être défini (ex: https://github.com/busymoood/dotfiles.git)" >&2
    exit 1
  }
}

# Variables passées au bootstrap `onstart` du conteneur.
# NVIM_CONFIG_REPO omis → l'image applique son défaut (repo LazyVim personnel).
ENV_ARGS=(-e "DOTFILES_REPO=${DOTFILES_REPO:-}")
if [[ -n "${NVIM_CONFIG_REPO:-}" ]]; then
  ENV_ARGS+=(-e "NVIM_CONFIG_REPO=${NVIM_CONFIG_REPO}")
fi

# ---------------------------------------------------------------------------
# Commandes
# ---------------------------------------------------------------------------
case "$command" in

  run)
    require_repo
    # Session jetable interactive : le dossier courant devient /workspace,
    # l'état des outils (plugins nvim, Mason, auth opencode) vit dans le volume.
    # shellcheck disable=SC2086  # DEVBOX_EXTRA_ARGS doit être découpé en mots
    exec docker run -it --rm \
      --hostname devbox \
      -v "${DEVBOX_WORKSPACE:-$PWD}:/workspace" \
      -v "${STATE_VOLUME}:/home/dev/.local" \
      "${SSH_ARGS[@]}" \
      "${ENV_ARGS[@]}" \
      ${DEVBOX_EXTRA_ARGS:-} \
      "$IMAGE"
    ;;

  up)
    require_repo
    ws="${DEVBOX_WORKSPACE:-/srv/projets}"
    [[ -d "$ws" ]] || mkdir -p "$ws"
    # Conteneur permanent, démarré en arrière-plan, relancé après reboot.
    # L'agent SSH (si détecté) est monté au démarrage — privilégiez une session
    # `ssh -A` pour créer le conteneur, et ControlPersist pour la maintenir.
    # shellcheck disable=SC2086
    docker run -d \
      --name "$NAME" \
      --hostname devbox \
      --restart unless-stopped \
      -v "${ws}:/workspace" \
      -v "${STATE_VOLUME}:/home/dev/.local" \
      "${SSH_ARGS[@]}" \
      "${ENV_ARGS[@]}" \
      ${DEVBOX_EXTRA_ARGS:-} \
      "$IMAGE"
    echo "[devbox] Conteneur '$NAME' démarré. Entrer dedans : ./bin/devbox.sh exec"
    ;;

  exec)
    exec docker exec -it "$NAME" zsh
    ;;

  stop)
    docker rm -f "$NAME" || true
    echo "[devbox] Conteneur '$NAME' supprimé (l'état du volume ${STATE_VOLUME} est conservé)."
    ;;

  update)
    docker pull "$IMAGE"
    docker rm -f "$NAME" 2>/dev/null || true
    "$0" up
    ;;
  *)
    usage
    ;;

esac
