# devbox — Instructions pour un agent : câbler l'image au lieu de la faire à la main

Fichier d'instructions destiné à un **agent de code** (OpenCode, Copilot CLI, Claude Code…).
Copie-le à la racine du repo projet (ex: `devbox-install-agents.md`) et référence-le depuis le
`AGENTS.md` du projet :

```markdown
## Environnement de dev
Utilise le conteneur devbox : suivre devbox-install-agents.md (ne pas configurer l'environnement à la main).
```

> Source de vérité de l'image : repo [`busymoood/dotfiles-docker`](https://github.com/busymoood/dotfiles-docker) (README complet : chaînes SSH, Raspberry, VPS, WSL2).

---

## Objectif

Mettre en place, dans le repo courant, un **dev container** basé sur l'image multi-arch
`ghcr.io/busymoood/dotfiles-docker` : Ubuntu 24.04 · NeoVim + LazyVim · tmux · zsh ·
LazyGit · ripgrep · fd · fzf · OpenCode · jq · build-essential · openssh-client.

L'environnement est fourni à chaque démarrage par le bootstrap `onstart` : il clone le repo
de dotfiles défini par `DOTFILES_REPO` (zsh, tmux, ssh) **et** le repo de config
NeoVim/LazyVim défini par `NVIM_CONFIG_REPO` (dans `~/.config/nvim`), puis fait un `git pull`
des deux. **Aucune clé privée ne vit jamais dans le conteneur** — tout passe par le socket de
l'agent SSH, fourni soit par un montage direct (Docker natif), soit par le relais
`devbox-agent-relay` embarqué dans l'image (Docker Desktop, où un socket Unix non-docker ne
peut pas être monté).

---

## 1. Prérequis (à vérifier avant tout)

| Prérequis | Comment vérifier | Si absent |
|---|---|---|
| Docker | `docker version` | demander à l'utilisateur de l'installer |
| `DOTFILES_REPO` (URL du repo de dotfiles) | `echo ${DOTFILES_REPO:-}` | **demander à l'utilisateur** (obligatoire au runtime) |
| `NVIM_CONFIG_REPO` (URL du repo de config NeoVim) | `echo ${NVIM_CONFIG_REPO:-}` | facultatif : l'image a un défaut (`git@…/lazyvim-config.git`, dépôt **privé**). Ne le surcharger que si l'utilisateur le demande ; `""` = nvim nu |
| Agent SSH du poste hôte (Bitwarden / `ssh -A` / pont WSL) | `echo ${SSH_AUTH_SOCK:-}` puis `ssh-add -l` | les dev containers marchent quand même, mais **rien n'est cloné** : dotfiles et config NeoVim sont ignorés (avertissement, rattrapage automatique 10 min) — prévenir l'utilisateur |
| **Docker Desktop** (macOS, Windows/WSL2) : relais TCP de l'agent | `lsof -iTCP:4242 -sTCP:LISTEN` | service launchd `com.busymoood.socat-ssh-agent` (macOS) : `socat TCP-LISTEN:4242,bind=0.0.0.0,reuseaddr,fork UNIX-CONNECT:$HOME/.bitwarden-ssh-agent.sock` ; Windows : `socat.exe` sur le même port vers `//./pipe/openssh-ssh-agent` |

Ne jamais inventer la valeur de `DOTFILES_REPO`. Si l'utilisateur ne l'a pas, proposer
`https://github.com/busymoood/<dotfiles>.git` et attendre sa confirmation.

---

## 2. Créer `.devcontainer/devcontainer.json`

Créer le fichier **exactement** comme suit (tout est relatif au repo projet) :

```jsonc
// .devcontainer/devcontainer.json
{
  "name": "devbox",
  "image": "ghcr.io/busymoood/dotfiles-docker:v0.6.0",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind",
  "workspaceFolder": "/workspace",
  "containerEnv": {
    "DOTFILES_REPO": "${localEnv:DOTFILES_REPO}",
    "NVIM_CONFIG_REPO": "${localEnv:NVIM_CONFIG_REPO}",
    // Docker Desktop : le socket local est recréé par devbox-agent-relay.
    // Docker natif : mettre "SSH_AUTH_SOCK": "/ssh-agent" + le mount commenté.
    "SSH_AUTH_SOCK": "${localEnv:DEVBOX_SSH_AUTH_SOCK:/tmp/ssh-agent.sock}"
  },
  "mounts": [
    // Docker natif uniquement (Linux, WSL2 sans Docker Desktop) :
    // "source=${localEnv:SSH_AUTH_SOCK},target=/ssh-agent,type=bind",
    "source=devbox-home,target=/home/dev/.local,type=volume"
  ],
  // 1) agent SSH (montage direct ou relais TCP, + rattrapage si verrouillé)
  // 2) dotfiles + config NeoVim (pull), permissions du volume
  "postStartCommand": "devbox-agent-relay start; onstart --no-shell"
}
```

Points d'attention pour l'agent :

- **Workspace bind** : le code vit dans le conteneur sur `/workspace` (monté depuis le repo). Ne pas proposer d'autre chemin.
- **Volume `devbox-home`** : état des outils (plugins nvim, Mason, auth opencode, clé Supermaven, browsers Playwright) persistant entre sessions. Laisser le nom tel quel pour partager l'état avec les sessions `devbox.sh`. Dans `docker-compose.yml`, forcer `volumes: { devbox-home: { name: devbox-home } }` sinon Compose préfixe par le nom du projet et crée un second volume.
- **Config NeoVim** : clonée par `onstart` dans `~/.config/nvim` (dépôt privé → agent SSH requis). Ne pas y écrire de config à la main : elle est versionnée dans `NVIM_CONFIG_REPO`.
- **Agent SSH** : `devbox-agent-relay start` (helper de l'image) gère montage direct **et** relais TCP, journalise dans `~/.cache/devbox-agent-relay.log` et arme un rattrapage (30 s × 10 min) si Bitwarden est verrouillé. `devbox-agent-relay doctor` donne l'état complet.
- **Surcoût projet** : tout ce que le projet ajoute (Node, Python, Chromium…) doit vivre dans un script idempotent appelé par `postCreateCommand` (provisionnement) et `postStartCommand` (relais + `onstart`), **pas** dupliqué entre `devcontainer.json` et `docker-compose.yml`.
- **Tag pinnable** : `:latest` ou une version publiée (`:v0.6.0`, `:0.6.0`) — **ne jamais écrire un tag qui n'existe pas** (tags publiés : `latest`, `main`, `vX.Y.Z`, `X.Y.Z`, `X.Y`, `X`, `sha-<commit>`).
- **`devcontainer up` sur un conteneur existant ne rejoue pas `postStartCommand`** : pour un cycle complet, `--remove-existing-container` (volume conservé) ou exécuter `devbox-agent-relay start; onstart --no-shell` à la main.
- Si `SSH_AUTH_SOCK` n'existe pas sur l'hôte **et** que Docker est natif, l'entrée de `mounts` échoue : la retirer, prévenir l'utilisateur, et laisser `devbox-agent-relay` signaler l'absence d'agent.

### Variables d'environnement : `.env.example` + wrapper

La CLI devcontainers **ne lit pas** les fichiers `.env` : elle substitue `${localEnv:VAR}`
depuis l'environnement du shell. Ne figez donc pas les valeurs dans
`devcontainer.json` — fournissez un modèle `.env.example` (versionné) et un wrapper :

```dotenv
# .env.example — copier en .env (gitignoré) : cp .env.example .env
DOTFILES_REPO=git@github.com:<vous>/<dotfiles>.git
NVIM_CONFIG_REPO=git@github.com:<vous>/<lazyvim-config>.git
# Optionnel — cible du relais agent SSH (défaut : host.docker.internal:4242)
# DEVBOX_SSH_RELAY_TARGET=host.docker.internal:4242
# Optionnel — socket de l'agent dans le conteneur
# DEVBOX_SSH_AUTH_SOCK=/tmp/ssh-agent.sock
```

```bash
# scripts/devbox-up.sh — charge .env puis lance la CLI
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo "ERREUR : cp .env.example .env"; exit 1; }
set -a; . ./.env; set +a
: "${DOTFILES_REPO:?DOTFILES_REPO manquant dans .env}"
exec devcontainer up --workspace-folder . "$@"
```

Dans `devcontainer.json`, utiliser `${localEnv:VAR:}` (défaut vide) ou
`${localEnv:VAR:défaut}` — **ne pas** utiliser `${localEnv:SSH_AUTH_SOCK…}` : la variable
de l'hôte (chemin macOS/Bitwarden) serait injectée dans le conteneur. Préfixer
(`DEVBOX_SSH_AUTH_SOCK`) pour éviter la collision.

`docker compose` lit `.env` nativement (interpolation `${VAR}`), donc le même fichier sert les
deux modes. Ajouter au `.gitignore` :
```
.env
.env.*
!.env.example
```

> **Piège `:latest`** : la CLI réutilise l'image si le tag existe localement, même périmée
> (symptôme : ancien utilisateur / binaires manquants). Soit épingler une version (`:v0.6.0`),
> soit `docker pull ghcr.io/busymoood/dotfiles-docker:latest` avant `up`.

---

## 3. Démarrer et vérifier (checklist)

Lancer (CLI devcontainers, pas besoin de VS Code) :

```bash
# si @devcontainers/cli n'est pas installé :
npm install -g @devcontainers/cli

# variables puis démarrage (le wrapper exporte .env, la CLI ne le lit pas)
cp .env.example .env && $EDITOR .env
./scripts/devbox-up.sh            # = devcontainer up --workspace-folder .
```

Puis vérifier :
```bash
# nom du conteneur : devcontainer up l'affiche (ou docker ps --filter label=devcontainer.local_folder)
docker exec -it <conteneur> bash -lc '
  devbox-agent-relay doctor &&
  nvim --version | head -1 && lazygit --version | head -1 && opencode --version &&
  ls /workspace && [ -d "$HOME/dotfiles" ] && echo "dotfiles: OK" &&
  [ -d "$HOME/.config/nvim/.git" ] && echo "nvim config: OK"'
```

Checklist à cocher et rapporter :
1. `devbox-agent-relay doctor` : socket présent, **clés listées** (Bitwarden déverrouillé), `~/.config/nvim` et `~/dotfiles` présents.
2. `onstart` n'a pas écrit d'erreur bloquante (avertissements « agent muet » tolérés si Bitwarden verrouillé → le rattrapage rejoue `onstart` après déverrouillage).
3. `nvim`, `lazygit`, `opencode`, `tmux`, `rg`, `fd`, `fzf` répondent.
4. `$HOME/dotfiles` existe et `$HOME/.zshrc` pointe vers `~/dotfiles/zsh/.zshrc` (ou `~/dotfiles/.zshrc` selon le layout du repo).
5. `$HOME/.config/nvim/.git` existe (config LazyVim clonée) ; `nvim` puis `:Lazy` répond. Sinon : agent SSH / `NVIM_CONFIG_REPO`.
6. `git -C /workspace config user.name` OK (identité de commits) → sinon c'est un sujet dotfiles, pas dev container.

Sortie de session : `docker exec -it <conteneur> zsh -l` (zsh est le shell par défaut; tmux → nvim sont le flux normal).

---

## 4. Interaction git / commits

- L'authentification se fait **via l'agent SSH forwardé** (`ssh-add -l` dans la session pour tester). Rien d'autre à configurer.
- Si l'agent est vide : prévenir l'utilisateur ("Bitwarden verrouillé ?") sans casser la session — c'est exactement le comportement d'`onstart`.

---

## 5. Dépannage rapide

| Symptôme | Cause probable | Action |
|---|---|---|
| `DOTFILES_REPO` vide dans le conteneur | variable non exportée dans le shell hôte avant `devcontainer up` | relancer avec `DOTFILES_REPO=… devcontainer up …` |
| échec clonage dotfiles | repo privé + agent SSH absent/verrouillé | `devbox-agent-relay doctor` ; `ssh-add -l` sur l'hôte ; `devbox-agent-relay start` après déverrouillage |
| `~/.config/nvim` absent, `nvim` nu | agent SSH absent/verrouillé **au moment du clone** (le repo LazyVim est privé) ou `NVIM_CONFIG_REPO=""` | déverrouiller, puis `devbox-agent-relay start; onstart --no-shell` (le rattrapage automatique le fait seul ≤10 min) ; vérifier `NVIM_CONFIG_REPO` |
| `ssh-add -l` → `No such file or directory` (Docker Desktop) | relais local mort / jamais démarré | `devbox-agent-relay start` ; vérifier côté hôte `lsof -iTCP:4242 -sTCP:LISTEN` |
| `ssh-add -l` → `communication with agent failed` | agent de l'hôte muet (Bitwarden verrouillé) | déverrouiller Bitwarden ; `ssh-add -l` doit lister les clés **sur l'hôte** d'abord |
| après un `devcontainer up` rien n'est rejoué | `postStartCommand` ne tourne pas sur un conteneur existant | `devcontainer up --remove-existing-container` (volume conservé) ou `devbox-agent-relay start; onstart --no-shell` |
| `~/.config/nvim` existe mais pas de `.git` | dossier créé à la main / clone interrompu par une version antérieure | `mv ~/.config/nvim ~/.config/nvim.old` puis redémarrer (le bootstrap ne supprime jamais un dossier existant) |
| `Permission denied` sur `~/.local/share/nvim` (LazyVim n'installe aucun plugin) | volume `devbox-home` créé en `root:root` par Docker | corrigé depuis v0.4.0 (`onstart` corrige les permissions du volume d'état) ; sinon `sudo chown -R dev:dev ~/.local` |
| prompt « Download spell file? » pour `fr` | dictionnaire français absent | corrigé depuis v0.4.1 (fr préinstallé dans le runtime NeoVim) ; sinon répondre `y` une fois |
| `[supermaven-nvim] sm-agent download failed` | le plugin écrit un fichier temporaire **relatif** ; `WORKDIR` non inscriptible | corrigé depuis v0.4.1 (`WORKDIR /home/dev`) ; sinon `cd ~` avant de lancer nvim |
| clé Supermaven à redemander à chaque conteneur | `~/.supermaven/config.json` hors volume | vérifier que `~/.supermaven` est un symlink vers `~/.local/share/supermaven` (créé par `onstart` depuis v0.4.1) |
| `ssh-keyscan`/known_hosts bruit au boot | premier démarrage sans `~/.ssh` | corrigé depuis v0.2.0 — signaler si observé sur une image plus ancienne |
| downloads lents/504 GitHub | intercepté seulement **à la construction de l'image** (CI) ; un dev container tire une image toute prête | ne rien faire ; si ça persiste sur les pulls d'image, vérifier l'état de l'infra GitHub |
| nvim vide/pas de plugins, mais `~/.config/nvim/.git` présent | premier lancement de LazyVim (~1 min téléchargements) | patienter ; état en cache dans `devbox-home` |

---

## 6. Après la première mise en place

- Commiter `.devcontainer/devcontainer.json` dans le repo projet (n'inclut ni secrets ni URL personnelle — `DOTFILES_REPO` vient de l'environnement).
- Documenter dans le README du projet :
  ```bash
  devcontainer up --workspace-folder .   # DOTFILES_REPO à exporter
  docker exec -it <conteneur> zsh
  ```
- Rappel de mise à jour du tooling : `docker pull ghcr.io/busymoood/dotfiles-docker:latest` (ou `:v0.6.0` épinglé). Les configs n'ont **pas** besoin de rebuild d'image : pousser dans le repo de dotfiles ou dans le repo de config NeoVim + redémarrer la session suffit.

---

## 7. Annexe — Agent SSH détaillé

Aucune clé privée ne quitte **Bitwarden sur votre machine principale**. Ce qui circule, c'est uniquement le **socket** de l'agent (`$SSH_AUTH_SOCK`). Selon le moteur Docker, deux modes :

| Hôte | Mode | Mise en place |
|---|---|---|
| **Linux natif** — VPS, Raspberry Pi, WSL2 avec Docker natif | montage direct du socket | `-v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent` (automatique avec `bin/devbox.sh`) |
| **Docker Desktop** — macOS, Windows/WSL2 avec intégration Docker Desktop | **relais TCP** (un socket Unix non-docker ne peut pas être monté) | hôte : `socat TCP-LISTEN:4242,bind=0.0.0.0,reuseaddr,fork UNIX-CONNECT:$HOME/.bitwarden-ssh-agent.sock` (service launchd) · conteneur : `-e SSH_AUTH_SOCK=/tmp/ssh-agent.sock -e DEVBOX_SSH_RELAY=1` |

`bin/devbox.sh` choisit tout seul : il interroge `docker info` (Docker Desktop ?) et bascule en mode relais si nécessaire.

**Helper `devbox-agent-relay`** (embarqué dans l'image) :

```bash
devbox-agent-relay start    # crée le socket (relais TCP) ou vérifie un montage direct
devbox-agent-relay doctor   # socket, cible, PID, clés visibles, configs
devbox-agent-relay stop     # arrête le relais local
```

- Le relais tourne en **session détachée** (`setsid`) : il survit à la fin du `postStartCommand` (un `nohup … &` seul est tué avec la session → agent muet ensuite).
- **Agent verrouillé** (Bitwarden fermé) : `start` prévient et arme un **rattrapage** (30 s × 10 min) qui rejoue `onstart` dès que des clés apparaissent — inutile de recréer le conteneur.
- `onstart` attend le socket jusqu'à 5 s, puis vérifie l'agent **avant** les clonages : sans agent, les repos `git@…` (dotfiles privés, config NeoVim) sont sautés pour ce démarrage.

**Chaînes de forwarding :**

| Scénario | Chaîne |
|---|---|
| macOS + Docker Desktop | Bitwarden → `~/.bitwarden-ssh-agent.sock` → socat TCP `4242` (launchd) → relais conteneur → `/tmp/ssh-agent.sock` |
| macOS + moteur Docker natif (Colima, Docker via VM Linux) | Bitwarden → `~/.bitwarden-ssh-agent.sock` → montage direct `/ssh-agent` |
| WSL2 + Docker natif | Bitwarden (Windows) → pipe `openssh-ssh-agent` → npiperelay+socat → `~/.ssh/agent.sock` → montage `/ssh-agent` |
| WSL2 + Docker Desktop | idem jusqu'à `~/.ssh/agent.sock` → socat TCP `4242` → relais conteneur |
| Raspberry / VPS (Docker natif) | Bitwarden (Mac) → `ssh -A` → socket sshd sur l'hôte → montage `/ssh-agent` |

> Le conteneur ne peut **que demander des signatures** à l'agent — il ne lit jamais de clé privée.
>
> Le relais launchd écoute sur `0.0.0.0:4242` (`host.docker.internal` n'atteint pas la loopback) : sur un réseau non fiable, restreindre le port au sous-réseau Docker Desktop avec une règle `pf`.

**Diagnostic rapide**

```bash
# hôte (Docker Desktop) : le relais tourne-t-il ?
lsof -iTCP:4242 -sTCP:LISTEN
ssh-add -l                                  # les clés doivent apparaître ici d'abord

# conteneur : état complet (relais, socket, clés, configs)
devbox-agent-relay doctor
# après déverrouillage de Bitwarden :
devbox-agent-relay start
```

**Symptômes typiques :**

| Symptôme | Cause | Action |
|---|---|---|
| `ssh-add -l` → `No such file or directory` (conteneur) | relais mort (ancien `nohup` tué avec la session) | `devbox-agent-relay start` |
| `ssh-add -l` → `communication with agent failed` | agent hôte muet (Bitwarden verrouillé) | déverrouiller Bitwarden, `ssh-add -l` sur l'hôte, puis `devbox-agent-relay start` |
| `nvim` nu après un `devcontainer up` | `postStartCommand` non rejoué sur un conteneur existant | `devcontainer up --remove-existing-container` (volume conservé) ou `devbox-agent-relay start; onstart --no-shell` |

**Variante dev container — Docker natif** (défaut du README = Docker Desktop) : dans `.devcontainer/devcontainer.json`, remplacer `"SSH_AUTH_SOCK": "${localEnv:DEVBOX_SSH_AUTH_SOCK:/tmp/ssh-agent.sock}"` par `"SSH_AUTH_SOCK": "/ssh-agent"` et décommenter dans `mounts` :

```jsonc
"source=${localEnv:SSH_AUTH_SOCK},target=/ssh-agent,type=bind"
```
