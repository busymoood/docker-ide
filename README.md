# Devbox — Dev Container

Une image Docker tout-en-un (**NeoVim + LazyVim**, **tmux**, **zsh**, **LazyGit**, **ripgrep**, **fd**, **fzf**, **OpenCode**…), buildée en **amd64 + arm64** et publiée automatiquement sur **GHCR** par CI.

Dans n'importe quel clone du projet, le dev container démarre l'image : le bootstrap (`onstart`, entrypoint) clône vos repos de **dotfiles** et de **config NeoVim/LazyVim** (`NVIM_CONFIG_REPO`) et installe les configurations par symlinks. Aucune clé privée n'est jamais stockée dans l'image.

## Quickstart

### 1. `.devcontainer/devcontainer.json`

À la racine du repo du projet :

```jsonc
// .devcontainer/devcontainer.json
{
  "name": "devbox",
  "image": "ghcr.io/busymoood/dotfiles-docker:main", // ou :latest — voir « Mise à jour de l'image »
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind",
  "workspaceFolder": "/workspace",
  "containerEnv": {
    "DOTFILES_REPO": "${localEnv:DOTFILES_REPO}",
    "NVIM_CONFIG_REPO": "${localEnv:NVIM_CONFIG_REPO}",
    "SSH_AUTH_SOCK": "${localEnv:DEVBOX_SSH_AUTH_SOCK:/tmp/ssh-agent.sock}"
  },
  "mounts": [
    "source=devbox-home,target=/home/dev/.local,type=volume" // état des outils, conservé entre les sessions
  ],
  // agent SSH puis bootstrap dotfiles + NeoVim
  "postStartCommand": "devbox-agent-relay start; onstart --no-shell"
}
```

### 2. Variables : `.env.devbox` (gitignoré)

```dotenv
# .env.devbox.example — copier en .env.devbox (gitignoré) : cp .env.devbox.example .env.devbox
DOTFILES_REPO=git@github.com:<vous>/<dotfiles>.git
NVIM_CONFIG_REPO=git@github.com:<vous>/<lazyvim-config>.git
```

Dans `.gitignore` :

```
.env.devbox
.env.devbox.*
!.env.devbox.example
```

### 3. Wrapper : `scripts/devbox-up.sh`

La CLI devcontainers **ne lit pas** les fichiers `.env` : elle substitue `${localEnv:VAR}` depuis l'environnement du shell. Le wrapper charge `.env.devbox` avant `devcontainer up`, pour ne jamais coder en dur `DOTFILES_REPO` / `NVIM_CONFIG_REPO` dans `devcontainer.json`.

```bash
mkdir -p scripts
# créer scripts/devbox-up.sh avec le contenu ci-dessous
chmod +x scripts/devbox-up.sh
```

```bash
#!/usr/bin/env bash
# scripts/devbox-up.sh — start the dev container with the devbox variables.
#
# The devcontainers CLI does not read .env files: it substitutes
# ${localEnv:VAR} from the shell environment. This wrapper exports
# .env.devbox (gitignored) then runs `devcontainer up`, so that personal
# repository URLs are not hard-coded in .devcontainer/devcontainer.json.
#
# Usage: ./scripts/devbox-up.sh [devcontainer up args]
#   e.g. ./scripts/devbox-up.sh --remove-existing-container
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env.devbox ]]; then
  echo "ERREUR : .env.devbox absent — copier le modèle puis l'ajuster :" >&2
  echo "  cp .env.devbox.example .env.devbox" >&2
  exit 1
fi

# Load .env.devbox (shell format: KEY=value, quotes accepted, # comments).
set -a
# shellcheck disable=SC1091
. ./.env.devbox
set +a

: "${DOTFILES_REPO:?DOTFILES_REPO manquant dans .env.devbox}"

exec devcontainer up --workspace-folder . "$@"
```

Usage :

```bash
./scripts/devbox-up.sh                              # premier démarrage
./scripts/devbox-up.sh --remove-existing-container  # recréer (rejoue postStartCommand, volume conservé)
```

### 4. Démarrer

```bash
npm install -g @devcontainers/cli                      # si la CLI n'est pas déjà installée
cp .env.devbox.example .env.devbox && $EDITOR .env.devbox
./scripts/devbox-up.sh                                 # postStartCommand lance onstart --no-shell
docker exec -it <nom-du-conteneur> zsh                 # entrer dans le conteneur
```

## Agent SSH (résumé)

Aucune clé privée ne quitte votre machine — le conteneur ne peut **que demander des signatures** à l'agent (`$SSH_AUTH_SOCK`).

| Moteur Docker | Mode |
|---|---|
| **Natif** (Linux, WSL2) | montage direct du socket — voir [« Aller plus loin »](#aller-plus-loin) pour la ligne `mounts` à ajouter |
| **Docker Desktop** (macOS, Windows) | relais TCP de l'hôte, socket recréé dans le conteneur par `devbox-agent-relay` (défaut de la config ci-dessus) |

Le relais gère aussi Bitwarden verrouillé (rattrapage automatique ≤ 10 min). Dépannage : `devbox-agent-relay doctor` dans le conteneur — détails complets dans [« Aller plus loin »](#aller-plus-loin).

## Mise à jour de l'image

Les binaires (nvim, lazygit, opencode…) arrivent par l'image, pas par les configs. La CLI devcontainers réutilise l'image locale si le tag existe, même périmée : il faut **forcer le pull** puis **recréer** le conteneur pour rejouer `postStartCommand`. Le volume `devbox-home` est conservé.

```bash
# Tag :latest — re-pull explicite, sinon l'image locale périmée est réutilisée
docker pull ghcr.io/busymoood/dotfiles-docker:latest
./scripts/devbox-up.sh --remove-existing-container

# Tag épinglé (:v0.6.0) — bumper le tag dans .devcontainer/devcontainer.json puis recréer
./scripts/devbox-up.sh --remove-existing-container
```

Puis entrer dans le conteneur recréé : `docker exec -it <nom-du-conteneur> zsh`.

Vos configurations n'ont **pas** besoin de MAJ d'image : poussez dans le repo de dotfiles ou de config NeoVim — `onstart` fait le `git pull` des deux à chaque démarrage du conteneur.

## Aller plus loin

- [`devbox-install-agents.md`](devbox-install-agents.md) — instructions complètes pour un agent de code (câblage automatique, checklist de vérification, dépannage) + **annexe Agent SSH détaillée** : chaînes de forwarding, diagnostic, symptômes, variante Docker natif (montage direct du socket).
