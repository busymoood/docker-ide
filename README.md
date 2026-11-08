# devbox — Environnement de développement portable, versionné, prêt à l'emploi

Une image Docker contenant tout l'environnement de développement (**NeoVim + LazyVim**, **tmux**, **zsh**, **LazyGit**, **ripgrep**, **fd**, **fzf**, **OpenCode**, **openssh-client**…), buildée en **amd64 + arm64** et publiée automatiquement sur **GHCR** par CI.

Au démarrage du conteneur, le bootstrap (`onstart`, entrypoint de l'image) clône votre repo de **dotfiles** hébergé sur GitHub, clone votre repo de **config NeoVim/LazyVim** (`NVIM_CONFIG_REPO`) et installe les configurations par symlinks. Aucune clé privée n'est jamais stockée dans l'image.

> Terminal pur : zéro IDE. L'éditeur, c'est NeoVim/LazyVim, dans le conteneur.

---

## Sommaire

- [L'image](#limage)
- [Config NeoVim / LazyVim](#config-neovim--lazyvim)
- [Agent SSH / Bitwarden (commun aux 4 scénarios)](#agent-ssh--bitwarden)
- [Déploiement 1 — Raspberry Pi (ARM64)](#déploiement-1--raspberry-pi-arm64)
- [Déploiement 2 — VPS x86](#déploiement-2--vps-x86)
- [Déploiement 3 — Dev Container (par projet)](#déploiement-3--dev-container-par-projet)
- [Déploiement 4 — WSL2 (Windows)](#déploiement-4--wsl2-windows)
- [Mises à jour](#mises-à-jour)
- [Récapitulatif](#récapitulatif)

---

## L'image

```bash
docker pull ghcr.io/busymoood/dotfiles-docker:latest
```

- **Contenu** : Ubuntu 24.04 · NeoVim (dernier stable) · LazyVim (config clonée au boot) · dictionnaires spell `fr` + `en` · tmux · zsh · LazyGit · ripgrep · fd · fzf · OpenCode · openssh-client · socat + `devbox-agent-relay` · build-essential
- **Architectures** : `amd64` (x86_64) et `arm64` (Raspberry Pi 64-bit, Apple Silicon) — Docker choisit automatiquement la bonne variante.
- **Version courante** : **`v0.6.0`** (`docker pull ghcr.io/busymoood/dotfiles-docker:v0.6.0`) — les exemples ci-dessous utilisent `:latest`, épinglez `:v0.6.0` pour un VPS/Raspberry qui doit rester stable.
- **Tags** : `latest` (sur semver uniquement) · `main` (branche) · `vX.Y.Z` (versions) · SHA du commit.
- **Configs** : non incluses dans l'image — fournies au démarrage par le repo de dotfiles (`DOTFILES_REPO`) et le repo de config NeoVim (`NVIM_CONFIG_REPO`) via `onstart`.
- **Utilisateur** : `dev` (non-root, UID 1000) — le compte de l'image de base est renommé au build.

Variables d'environnement clés :

| Variable | Défaut | Rôle |
|---|---|---|
| `DOTFILES_REPO` | *(obligatoire)* | URL du repo Git contenant vos dotfiles (zsh, tmux, ssh) |
| `NVIM_CONFIG_REPO` | `git@github.com:Thejulfi/lazyvim-config.git` | URL du repo de config NeoVim/LazyVim, cloné dans `~/.config/nvim` puis `git pull` à chaque démarrage. `NVIM_CONFIG_REPO=""` désactive |

Le **entrypoint** de l'image est `onstart` : chaque `docker run -it …` exécute automatiquement le bootstrap (vérif agent SSH → clone/pull dotfiles → clone/pull config NeoVim → symlinks) puis ouvre `zsh`. Sans TTY, le message vous indique d'entrer via `docker exec -it <conteneur> zsh`.

---

## Config NeoVim / LazyVim

L'image fournit **NeoVim** (binaire), pas la configuration : celle-ci vit dans un dépôt Git dédié, cloné au premier démarrage dans `~/.config/nvim` puis `git pull` aux suivants.

```bash
# Docker natif : VPS, Raspberry Pi, WSL2 (socket monté directement)
docker run -it --rm \
  -e DOTFILES_REPO=git@github.com:<vous>/<dotfiles>.git \
  -e NVIM_CONFIG_REPO=git@github.com:<vous>/<lazyvim-config>.git \
  -v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent \
  ghcr.io/busymoood/dotfiles-docker:latest

# Docker Desktop (macOS, Windows/WSL2) : relais TCP + socket recréé
docker run -it --rm \
  -e DOTFILES_REPO=git@github.com:<vous>/<dotfiles>.git \
  -e NVIM_CONFIG_REPO=git@github.com:<vous>/<lazyvim-config>.git \
  -e SSH_AUTH_SOCK=/tmp/ssh-agent.sock -e DEVBOX_SSH_RELAY=1 \
  ghcr.io/busymoood/dotfiles-docker:latest
```

- **Défaut** : `git@github.com:Thejulfi/lazyvim-config.git` (dépôt **privé** → le clone exige l'agent SSH forwardé). Surchargez `NVIM_CONFIG_REPO`, ou mettez-le à `""` pour un nvim nu.
- **Sans agent** (Bitwarden verrouillé, pas de `ssh -A`) : le clone est sauté avec un avertissement explicite (`nvim restera nu`), et retenté au démarrage suivant.
- **Priorité** : le dépôt dédié gagne sur un éventuel `nvim/` présent dans les dotfiles (le symlink `dotfiles/nvim` n'est posé que si `~/.config/nvim` est libre).
- **Clone atomique** : clonage dans un dossier temporaire puis `mv` — un clone interrompu ne bloque pas les démarrages suivants.
- **État** (plugins, Mason, Treesitter) : dans `~/.local/share/nvim`, donc dans le volume `devbox-home`. Seule la config est versionnée ; `lazy-lock.json` est dans le dépôt.
- **Volume d'état** : Docker crée `~/.local` en `root:root` (le chemin n'existe pas dans l'image) ; `onstart` le rend inscriptible au premier démarrage. Sans ça, LazyVim échoue en `Permission denied` sur `~/.local/share/nvim`.
- **Treesitter** : l'image est basée sur **Ubuntu 24.04** (glibc 2.39), requis par les parsers précompilés de `nvim-treesitter` (branche `main`). Sur 22.04 ils échouent avec `GLIBC_2.39 not found`.
- **Spell** : `fr.utf-8.spl` / `fr.utf-8.sug` sont préinstallés dans le runtime NeoVim (`/opt/nvim/share/nvim/runtime/spell`) — `spelllang = { 'fr', 'en' }` ne déclenche plus le prompt « Download spell file? ».
- **Supermaven** (`supermaven-nvim`) : le binaire `sm-agent` **et la clé API** vivent dans `~/.supermaven/config.json`. `onstart` y crée un symlink vers `~/.local/share/supermaven` (volume `devbox-home`) → le binaire et l'authentification survivent à la recréation du conteneur. Authentification : `:SupermavenUsePro` (lien `https://supermaven.com/activate-extension?linkId=…`) ou `:SupermavenUseFree`, puis `:SupermavenShowLog` pour vérifier.

---

## Agent SSH / Bitwarden

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

Symptômes typiques :

| Symptôme | Cause | Action |
|---|---|---|
| `ssh-add -l` → `No such file or directory` (conteneur) | relais mort (ancien `nohup` tué avec la session) | `devbox-agent-relay start` |
| `ssh-add -l` → `communication with agent failed` | agent hôte muet (Bitwarden verrouillé) | déverrouiller Bitwarden, `ssh-add -l` sur l'hôte, puis `devbox-agent-relay start` |
| `nvim` nu après un `devcontainer up` | `postStartCommand` non rejoué sur un conteneur existant | `devcontainer up --remove-existing-container` (volume conservé) ou `devbox-agent-relay start; onstart --no-shell` |

---

## Déploiement 1 — Raspberry Pi (ARM64)

> Session jetable en mode terminal direct. Idéal pour un usage local ou nomade.

### Pré-requis

- Raspberry Pi OS **64-bit** (obligatoire — pas d'image arm64 sur un OS 32-bit).
- Docker :

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER   # puis se reconnecter
```

### Étapes

```bash
# 1. (Optionnel mais recommandé) cloner le wrapper devbox.sh
git clone https://github.com/busymoood/dotfiles-docker.git
cd dotfiles-docker

# 2. Session interactive — arm64 tirée automatiquement, bootstrap auto
DEVBOX_WORKSPACE=/home/pi/projets \
DOTFILES_REPO=https://github.com/busymoood/<votre-dotfiles>.git \
./bin/devbox.sh run
```

Dans le conteneur : `tmux` → `nvim` — LazyVim est cloné dans `~/.config/nvim` depuis `NVIM_CONFIG_REPO` (défaut : `git@github.com:Thejulfi/lazyvim-config.git`), puis `git pull` à chaque démarrage.

ou en `docker run` manuel :

```bash
docker run -it --rm \
  --hostname devbox \
  -v /home/pi/projets:/workspace \
  -v devbox-home:/home/dev/.local \
  -e SSH_AUTH_SOCK=/ssh-agent \
  -v "$SSH_AUTH_SOCK:/ssh-agent" \
  -e DOTFILES_REPO=https://github.com/busymoood/<votre-dotfiles>.git \
  -e NVIM_CONFIG_REPO=git@github.com:<vous>/<lazyvim-config>.git \
  ghcr.io/busymoood/dotfiles-docker:v0.6.0
```

> **Auth git par clé** : connectez-vous au Pi **depuis votre Mac avec `ssh -A`** — le socket forwardé est monté dans le conteneur (Docker natif, aucun relais nécessaire). Vérifier ensuite : `docker exec -it <conteneur> devbox-agent-relay doctor`.

### Notes Raspberry

- **Premier lancement de LazyVim** : ~1 min (download des plugins/Treesitter). Mis en cache dans le volume `devbox-home` → sessions suivantes instantanées.
- **Carte SD** : le volume `devbox-home` isole les écritures récurrentes (plugins, Mason, historiques) et préserve la SD. Pour un usage intensif, privilégier un SSD USB comme disque système.
- **Persistance** : le code vit sur l'hôte (`/home/pi/projets`), l'état des outils dans le volume. Détruire le conteneur ne perd rien.
- **Ressources** : 2 Go de RAM = confortable ; 1 Go = utilisable, mais comptez sur le premier install de Mason/Treesitter.

---

## Déploiement 2 — VPS x86

> Conteneur **permanent**, démarré en arrière-plan et relancé automatiquement après reboot. Idéal pour des sessions nvim résidentes (tmux) accessibles à tout moment.

### Étapes

```bash
git clone https://github.com/busymoood/dotfiles-docker.git
cd dotfiles-docker

ws="${DEVBOX_WORKSPACE:-/srv/projets}"
sudo mkdir -p "$ws"

# Conteneur permanent (amd64 tiré automatiquement)
DOTFILES_REPO=https://github.com/busymoood/<votre-dotfiles>.git \
DEVBOX_WORKSPACE=/srv/projets \
ssh -A mon-vps  # connectez-vous à votre VPS avec l'option -A (agent forwarded)
./bin/devbox.sh up

# Entrer dedans, depuis le VPS ou n'importe où via SSH
ssh mon-vps docker exec -it devbox zsh
```

Dans le conteneur : `tmux attach` → vos sessions nvim **tournent en permanence sur le serveur**. Déconnectez-vous le soir, retrouvez vos buffers ouverts le lendemain — le modèle "session résidente".

**Conseil important** : préférez utiliser `ssh -A mon-vps` **à chaque session** (`-A` active agent forwarding) pour **coordonner l'auth avec Bitwarden même** (ControlPersist régule 24h) :

```sshconfig
# ~/.ssh/config, dans vos dotfiles :
Host *
    ControlMaster auto
    ControlPath /tmp/ssh-%r@%h:%p
    ControlPersist 24h
    ForwardAgent yes
```

(le conteneur a été créé depuis une session avec l'agent - le socket reste monté à travers ControlPersist, donc vos commits fonctionnent tant que le maître SSH reste en vie.)

### Notes VPS

- **`--restart unless-stopped`** : le conteneur relit vos dotfiles et redémarre seul après un reboot du serveur.
- **Agent SSH** : Docker natif → le socket est monté directement. Il provient de `sshd` (`/tmp/ssh-*/agent.*`) et **vit tant que la session `ssh -A` vit** (d'où `ControlPersist`) ; si le maître SSH meurt, recréer le conteneur (`./bin/devbox.sh update`) pour remonter le socket, puis vérifier avec `docker exec -it devbox devbox-agent-relay doctor`.
- **Épingler la version** : `DEVBOX_IMAGE=ghcr.io/busymoood/dotfiles-docker:v0.6.0 ./bin/devbox.sh up` (au lieu de `:latest`) — recommandé pour un serveur qui ne doit pas bouger.
- **Ports de test** : si vous développez une web app, ajoutez `DEVBOX_EXTRA_ARGS="-p 3000:3000"` avant `./bin/devbox.sh up`.
- **À côté des services de prod** : ce conteneur est un environnement de *dev* ; il ne remplace pas vos services de production — il vit à leurs côtés, isolé dans son conteneur.

---

## Déploiement 3 — Dev Container (par projet)

> L'environnement attaché à **un projet** : n'importe quel clone du repo, sur n'importe quelle machine, devient prêt à l'emploi avec la même image.

> **Agent de code** : pour câbler cette image automatiquement dans un projet (fichier à copier, checklist, dépannage) → [`devbox-install-agents.md`](devbox-install-agents.md).

### Configuration

Dans le repository du projet, à la racine :

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
    // Docker natif (Linux/WSL2) : mettre "/ssh-agent" + le montage ci-dessous.
    "SSH_AUTH_SOCK": "${localEnv:DEVBOX_SSH_AUTH_SOCK:/tmp/ssh-agent.sock}"
  },
  "mounts": [
    // Décommenter sur Docker natif uniquement (Linux, WSL2 sans Docker Desktop) :
    // "source=${localEnv:SSH_AUTH_SOCK},target=/ssh-agent,type=bind",
    "source=devbox-home,target=/home/dev/.local,type=volume"
  ],
  // agent SSH (montage direct ou relais TCP) puis bootstrap dotfiles + NeoVim
  "postStartCommand": "devbox-agent-relay start; onstart --no-shell"
}
```

### Étapes

```bash
git clone https://github.com/busymoood/mon-projet.git
cd mon-projet

# Démarrer le conteneur du projet (postStartCommand lance onstart --no-shell)
devcontainer up --workspace-folder .

# Entrer dans le conteneur
docker exec -it <nom-du-conteneur> zsh
```

### Notes dev container

- **Agent SSH** : `devbox-agent-relay start` gère les deux cas (socket monté sur Docker natif, relais TCP sur Docker Desktop) et arme un rattrapage si Bitwarden est verrouillé. Diagnostic : `devbox-agent-relay doctor`.
- **Variables** : ne pas figer `DOTFILES_REPO`/`NVIM_CONFIG_REPO` dans `devcontainer.json`. Fournir un `.env.example` + un wrapper qui exporte les variables avant `devcontainer up` (la CLI ignore les `.env`, contrairement à `docker compose`). Modèle complet dans [`devbox-install-agents.md`](devbox-install-agents.md).
- **Piège `:latest`** : la CLI réutilise l'image locale si le tag existe, même périmée → `docker pull` avant `up`, ou épingler `:v0.6.0`.
- **Isolation par projet** : chaque projet a son conteneur, sa config, ses dépendances — aucun état parasite entre projets.
- **Tag pinnable** : un projet peut rester sur `:v0.6.0` et un autre sur `:latest` — ne jamais écrire un tag inexistant.
- **`devcontainer up` sur un conteneur existant ne rejoue pas `postStartCommand`** : recréer (`--remove-existing-container`, volume conservé) ou lancer `devbox-agent-relay start; onstart --no-shell` à la main.
- **Partage** : tout collaborateur disposant de Docker obtient le même environnement via `devcontainer up`.

---

## Déploiement 4 — WSL2 (Windows)

> Un PC Windows avec WSL2 est une **vraie machine Linux** : même déploiement que le scénario local. Seule la chaîne d'agent SSH diffère — Bitwarden tourne sur Windows et expose une **named pipe Windows**, invisible depuis WSL2 → il faut un pont `npiperelay + socat`.

### Étapes

```bash
# 1. Docker natif dans la distro WSL (ou Docker Desktop avec intégration WSL)
curl -fsSL https://get.docker.com | sh

# 2. Pont d'agent SSH Windows → WSL (une seule fois, dans WSL)
#    a. télécharger npiperelay.exe dans ~/bin (release GitHub)
#    b. socat :
sudo apt-get install -y socat
#    c. fonction de démarrage du pont (à mettre dans ~/.zshrc/.bashrc de vos dotfiles) :
start-ssh-agent-relay() {
  if [[ ! -S ~/.ssh/agent.sock ]]; then
    socat UNIX-LISTEN:$HOME/.ssh/agent.sock,fork \
      EXEC:"$HOME/bin/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &
  fi
}
#    Le chemin ~/.ssh/agent.sock est FIXE → détecté automatiquement par devbox.sh
```

```bash
# 3. Session (Docker natif dans WSL : le socket est monté directement)
DOTFILES_REPO=https://github.com/busymoood/<votre-dotfiles>.git \
./bin/devbox.sh run
```

> **Docker Desktop avec intégration WSL2** : même limitation que macOS (un socket Unix non-docker ne peut pas être monté). Exposer l'agent côté Windows via `socat.exe TCP-LISTEN:4242,bind=0.0.0.0,reuseaddr,fork EXEC:".../npiperelay.exe -ei -s //./pipe/openssh-ssh-agent"` puis lancer avec `-e SSH_AUTH_SOCK=/tmp/ssh-agent.sock -e DEVBOX_SSH_RELAY=1`. `bin/devbox.sh` détecte Docker Desktop (`docker info`) et bascule automatiquement en mode relais.

### Notes WSL2

- **Filesystem** : travaillez *dans* WSL (`~/projets`), pas sous `/mnt/c/...` (3–5× plus lent sur git/npm).
- **Le pont peut tourner au démarrage du shell** → le socket à chemin fixe vit en permanence, pas besoin de `ControlPersist` : c'est le scénario le plus simple après macOS.
- **Vérifier** : dans le conteneur, `devbox-agent-relay doctor` (socket + clés) puis `ssh-add -l`.
- **Windows ARM ?** sur un laptop Snapdragon, WSL2 est arm64 → l'image `arm64` est tirée automatiquement.
- **Version** : `DEVBOX_IMAGE=ghcr.io/busymoood/dotfiles-docker:v0.6.0 ./bin/devbox.sh run` pour épingler.

---

## Mises à jour

Les nouvelles versions des binaires (nvim, lazygit, opencode…) arrivent par l'image, pas via vos configs :

```bash
# Raspberry / session jetable : juste re-pull, la session suivante aura la nouvelle image
docker pull ghcr.io/busymoood/dotfiles-docker:latest

# VPS (conteneur permanent) : pull + recréation
./bin/devbox.sh update
```

Vos configurations changent **sans toucher à l'image** : poussez dans votre repo de dotfiles ou dans votre repo de config NeoVim, redémarrez le conteneur — `onstart` fait un `git pull` des deux à chaque démarrage.

> Version courante : **v0.6.0** (agent SSH : socat + `devbox-agent-relay`, spell FR, Ubuntu 24.04). Les tags `vX.Y.Z` sont publiés sur GHCR à chaque release.

---

## Récapitulatif

| | Raspberry | VPS x86 | Dev container | WSL2 |
|---|---|---|---|---|
| Mode de vie | jetable (`-it --rm`) | **permanent** (`-d`, restart) | jetable, par projet | jetable |
| Entrée | `devbox.sh run` | `devbox.sh up` → `exec` | `devcontainer up` → `exec` | `devbox.sh run` |
| Code | volume hôte | volume hôte | bind du dossier projet | volume hôte (FS WSL) |
| État outils | volume `devbox-home` | volume `devbox-home` | volume `devbox-home` | volume `devbox-home` |
| Archi | arm64 | amd64 | les deux | amd64 (ou arm64) |
| Agent SSH | montage direct (`ssh -A`) | montage direct (`ssh -A` + ControlPersist) | montage direct **ou** relais TCP (Docker Desktop) | montage direct (Docker natif) **ou** relais (Docker Desktop) |
