# Architecture d'un Environnement de Développement Transparent & Portable

Ce guide récapitule la méthodologie complète pour configurer un environnement de développement homogène à travers vos machines (PC fixe, portable, Raspberry Pi, VPS) en utilisant les **Dev Containers**, un **Dockerfile d'image personnalisée**, et vos **Dotfiles Git**.

---

## 1. Vue d'ensemble de l'Architecture

L'architecture repose sur la séparation stricte entre les **outils système (binaires)** et vos **configurations personnelles (dotfiles)** :

*   **Image Docker (Binaires & Outils) :** Contient les dépendances lourdes (`neovim`, `lazygit`, `opencode`, `tmux`, `zsh`, `ripgrep`, etc.). Elle est construite une fois et réutilisée.
*   **Dépôt Dotfiles (Configurations) :** Hébergé sur un dépôt Git distant. Il contient vos personnalisations (`.zshrc`, `.tmux.conf`, configs Neovim/LazyVim, `.ssh/config` sans clés privées) et un script d'installation.
*   **SSH Agent Forwarding (Sécurité) :** Relaye dynamiquement le socket SSH de la machine hôte vers le conteneur. **Aucune clé privée SSH n'est stockée dans le conteneur ou l'image.**

---

## 2. L'Image Docker (`Dockerfile`)

Ce fichier définit les outils de base indispensables à votre flux de travail.

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Éviter les invites interactives pendant l'installation des paquets
ENV DEBIAN_FRONTEND=noninteractive

# 1. Installation des outils de base et dépendances CLI
RUN apt-get update && apt-get install -y \
    curl \
    git \
    zsh \
    tmux \
    ripgrep \
    fd-find \
    fzf \
    build-essential \
    unzip \
    socat \
    && rm -rf /var/lib/apt/lists/*

# 2. Installation de Neovim (dernière version stable/nightly)
RUN curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz \
    && tar -C /opt -xzf nvim-linux64.tar.gz \
    && ln -s /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim \
    && rm nvim-linux64.tar.gz

# 3. Installation de LazyGit
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
    && curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" \
    && tar -xf lazygit.tar.gz lazygit \
    && install lazygit /usr/local/bin \
    && rm lazygit.tar.gz lazygit

# 4. Installation d'OpenCode (ou vos CLI AI spécifiques)
# Remplacez / ajustez selon la méthode d'installation d'OpenCode
RUN curl -fsSL https://opencode.ai/install.sh | bash || true

# Définir l'utilisateur par défaut fourni par les images Microsoft Dev Containers
USER dev
WORKDIR /home/dev
```

---

## 3. Le Script d'Installation des Dotfiles (`install.sh`)

Placez ce script à la racine de votre dépôt **Git de dotfiles**. Il s'exécutera automatiquement à chaque création d'un conteneur pour créer les liens symboliques et configurer les permissions.

```bash
#!/usr/bin/env bash
set -e

DOTFILES_DIR="$HOME/dotfiles"

echo "=== Début de la configuration de l'environnement ==="

# 1. Préparation des dossiers
mkdir -p "$HOME/.config"

# 2. Liaison symbolique pour ZSH
if [ -f "$DOTFILES_DIR/zsh/.zshrc" ]; then
    ln -sf "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
    echo "[✓] Config Zsh liée"
fi

# 3. Liaison symbolique pour Tmux
if [ -f "$DOTFILES_DIR/tmux/.tmux.conf" ]; then
    ln -sf "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
    echo "[✓] Config Tmux liée"
fi

# 4. Liaison symbolique pour Neovim / LazyVim
if [ -d "$DOTFILES_DIR/nvim" ]; then
    ln -sf "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
    echo "[✓] Config LazyVim liée"
fi

# 5. Configuration du dossier .ssh (Uniquement config et clés publiques)
if [ -d "$DOTFILES_DIR/ssh" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Copier le fichier config et les clés publiques (.pub)
    cp -r "$DOTFILES_DIR/ssh/"* "$HOME/.ssh/" 2>/dev/null || true
    
    # Ajustement obligatoire des permissions strictes requises par SSH
    chmod 644 "$HOME/.ssh/"*.pub 2>/dev/null || true
    chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
    echo "[✓] Config SSH installée et sécurisée"
fi

# 6. Définir ZSH comme shell par défaut (si nécessaire)
if [ "$SHELL" != "$(which zsh)" ]; then
    sudo chsh -s $(which zsh) $(whoami) 2>/dev/null || true
fi

echo "=== Environnement configuré avec succès ! ==="
```

---

## 4. Configuration du Dev Container (`devcontainer.json`)

Dans vos projets (ou dans votre configuration globale VS Code), utilisez le fichier `devcontainer.json` ci-dessous. Il relie l'image Docker, l'automatisation du dépôt de dotfiles et le forwarding de l'agent SSH.

```json
{
  "name": "Mon Environnement de Dev Harmonisé",
  
  // Utiliser l'image personnalisée (ou pointer vers un Dockerfile local)
  "build": {
    "dockerfile": "Dockerfile"
  },

  // 1. Déclarer le dépôt de dotfiles à cloner et le script à exécuter
  "dotfiles": {
    "repository": "https://github.com/votre-utilisateur/vos-dotfiles.git",
    "targetPath": "~/dotfiles",
    "installCommand": "./install.sh"
  },

  // 2. Transmettre le socket de l'agent SSH de l'hôte vers le conteneur
  "remoteEnv": {
    "SSH_AUTH_SOCK": "${localEnv:SSH_AUTH_SOCK}"
  },
  "mounts": [
    "source=${localEnv:SSH_AUTH_SOCK},target=/ssh-agent,type=bind"
  ],

  // 3. Personnalisations de l'éditeur VS Code (facultatif)
  "customizations": {
    "vscode": {
      "settings": {
        "terminal.integrated.defaultProfile.linux": "zsh"
      },
      "extensions": [
        "asvetliakov.vscode-neovim",
        "eamodio.gitlens"
      ]
    }
  },

  // L'image expose déjà `remoteUser: dev` (metadata) — inutile de le répéter
}
```

---

## 5. Fonctionnement global & Avantages

1. **Au lancement du projet :** VS Code démarre le conteneur basé sur votre `Dockerfile`.
2. **Récupération des configs :** VS Code clone automatiquement `vos-dotfiles.git` dans `~/dotfiles` à l'intérieur du conteneur.
3. **Exécution du script :** Le fichier `./install.sh` est déclenché. Vos fichiers `.zshrc`, `.tmux.conf`, LazyVim et `.ssh/config` s'installent en une fraction de seconde.
4. **Authentification SSH transparente :** Le tuyau `SSH_AUTH_SOCK` connecte vos commandes Git (`git push`/`git pull`) directement à votre gestionnaire de clés local (Bitwarden, 1Password, `ssh-agent` natif), sans exposer vos clés privées.
5. **Maintenance simplifiée :** Une modification sur votre Zsh ou LazyVim ? Vous poussez sur votre repo de dotfiles, et vos autres conteneurs récupèrent les mises à jour instantanément sans jamais reconstruire l'image Docker.
