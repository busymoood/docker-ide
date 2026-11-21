# Architecture of a Transparent & Portable Development Environment

This guide summarizes the complete methodology for setting up a consistent development environment across your machines (desktop, laptop, Raspberry Pi, VPS) using **Dev Containers**, a **custom image Dockerfile**, and your **Git dotfiles**.

---

## 1. Architecture Overview

The architecture relies on a strict separation between **system tools (binaries)** and your **personal configurations (dotfiles)**:

*   **Docker image (binaries & tools):** contains the heavy dependencies (`neovim`, `lazygit`, `opencode`, `tmux`, `zsh`, `ripgrep`, etc.). It is built once and reused.
*   **Dotfiles repository (configurations):** hosted on a remote Git repository. It holds your customizations (`.zshrc`, `.tmux.conf`, Neovim/LazyVim configs, `.ssh/config` without private keys) and an installation script.
*   **SSH agent forwarding (security):** dynamically relays the host's SSH socket into the container. **No private SSH key is ever stored in the container or the image.**

---

## 2. The Docker Image (`Dockerfile`)

This file defines the essential base tools for your workflow.

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install base tools and CLI dependencies
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

# 2. Install Neovim (latest stable/nightly)
RUN curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz \
    && tar -C /opt -xzf nvim-linux64.tar.gz \
    && ln -s /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim \
    && rm nvim-linux64.tar.gz

# 3. Install LazyGit
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*') \
    && curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" \
    && tar -xf lazygit.tar.gz lazygit \
    && install lazygit /usr/local/bin \
    && rm lazygit.tar.gz lazygit

# 4. Install OpenCode (or your specific AI CLIs)
# Replace / adjust according to the OpenCode installation method
RUN curl -fsSL https://opencode.ai/install.sh | bash || true

# Set the default user provided by Microsoft Dev Containers images
USER dev
WORKDIR /home/dev
```

---

## 3. The Dotfiles Installation Script (`install.sh`)

Place this script at the root of your **dotfiles Git repository**. It runs automatically on every container creation to create symlinks and set permissions.

```bash
#!/usr/bin/env bash
set -e

DOTFILES_DIR="$HOME/dotfiles"

echo "=== Starting environment setup ==="

# 1. Prepare directories
mkdir -p "$HOME/.config"

# 2. Symlink for Zsh
if [ -f "$DOTFILES_DIR/zsh/.zshrc" ]; then
    ln -sf "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
    echo "[✓] Zsh config linked"
fi

# 3. Symlink for Tmux
if [ -f "$DOTFILES_DIR/tmux/.tmux.conf" ]; then
    ln -sf "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
    echo "[✓] Tmux config linked"
fi

# 4. Symlink for Neovim / LazyVim
if [ -d "$DOTFILES_DIR/nvim" ]; then
    ln -sf "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
    echo "[✓] LazyVim config linked"
fi

# 5. Configure the .ssh directory (config and public keys only)
if [ -d "$DOTFILES_DIR/ssh" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    # Copy the config file and public keys (.pub)
    cp -r "$DOTFILES_DIR/ssh/"* "$HOME/.ssh/" 2>/dev/null || true
    
    # Enforce the strict permissions required by SSH
    chmod 644 "$HOME/.ssh/"*.pub 2>/dev/null || true
    chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
    echo "[✓] SSH config installed and secured"
fi

# 6. Set Zsh as the default shell (if needed)
if [ "$SHELL" != "$(which zsh)" ]; then
    sudo chsh -s $(which zsh) $(whoami) 2>/dev/null || true
fi

echo "=== Environment configured successfully! ==="
```

---

## 4. Dev Container Configuration (`devcontainer.json`)

In your projects (or in your global VS Code configuration), use the `devcontainer.json` below. It connects the Docker image, the dotfiles repository automation, and SSH agent forwarding.

```json
{
  "name": "My Harmonized Dev Environment",
  
  // Use the custom image (or point to a local Dockerfile)
  "build": {
    "dockerfile": "Dockerfile"
  },

  // 1. Declare the dotfiles repository to clone and the script to run
  "dotfiles": {
    "repository": "https://github.com/your-user/your-dotfiles.git",
    "targetPath": "~/dotfiles",
    "installCommand": "./install.sh"
  },

  // 2. Forward the host's SSH agent socket into the container
  "remoteEnv": {
    "SSH_AUTH_SOCK": "${localEnv:SSH_AUTH_SOCK}"
  },
  "mounts": [
    "source=${localEnv:SSH_AUTH_SOCK},target=/ssh-agent,type=bind"
  ],

  // 3. VS Code editor customizations (optional)
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

  // The image already exposes `remoteUser: dev` (metadata) — no need to repeat it
}
```

---

## 5. Overall Workflow & Benefits

1. **On project launch:** VS Code starts the container from your `Dockerfile`.
2. **Config retrieval:** VS Code automatically clones `your-dotfiles.git` into `~/dotfiles` inside the container.
3. **Script execution:** `./install.sh` runs. Your `.zshrc`, `.tmux.conf`, LazyVim and `.ssh/config` are installed in a fraction of a second.
4. **Transparent SSH authentication:** the `SSH_AUTH_SOCK` pipe connects your Git commands (`git push`/`git pull`) directly to your local key manager (Bitwarden, 1Password, native `ssh-agent`), without exposing your private keys.
5. **Simplified maintenance:** changed your Zsh or LazyVim? Push to your dotfiles repo and your other containers pick up the updates instantly without ever rebuilding the Docker image.
