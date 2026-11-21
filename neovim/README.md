# 💤 LazyVim — Neovim Setup

> **In devbox**: this directory is copied into the image (`/opt/devbox-config/nvim`) and linked into `~/.config/nvim`. The installation instructions below describe standalone usage (outside the container) and are not needed in devbox.

This is a fully configured [LazyVim](https://github.com/LazyVim/LazyVim) setup for Neovim.
It includes a custom colorscheme, AI coding assistants, C/C++ language support via clangd,
devcontainer integration, and more.

## ✅ Prerequisites

| Requirement | Version / Notes |
|---|---|
| **Neovim** | ≥ 0.10 (tested with 0.12) |
| **Git** | Installed by default on most Linux distros |
| **clangd** | System binary at `/usr/bin/clangd` (or via Mason on x86_64) |
| **Node.js** (optional) | Required for some LSP servers (tsserver, etc.) |
| **Docker** (optional) | Required for DevContainers feature |

---

## Installer commands : 

```bash
curl -fsSL https://raw.githubusercontent.com/Thejulfi/lazyvim-config/main/install_nvim.sh | bash
```

---

## 🐧 Install on Linux

### 1. Install Neovim

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y neovim git

# Fedora / RHEL
sudo dnf install -y neovim git

# Arch / Manjaro
sudo pacman -S neovim git

# openSUSE
sudo zypper install -y neovim git
```

### 2. Installation of lazygit

**On linux x86_64 only:**

```bash
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
tar xf lazygit.tar.gz lazygit
sudo install lazygit /usr/local/bin
```

**On linux ARM64 only:**

```bash
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_arm64.tar.gz"
tar xf lazygit.tar.gz lazygit
sudo install lazygit /usr/local/bin
rm lazygit.tar.gz
```

> 💡 **Tip**: If your distro ships an older Neovim (< 0.10), install a newer
> version via an AppImage, the [official release](https://github.com/neovim/neovim/releases),
> or a version manager like [bob](https://github.com/MordechaiHadad/bob).

### 3. Open code installation and usage (for AI in neovim)

Installation : 

```bash
# YOLO
curl -fsSL https://opencode.ai/install | bash

# Package managers
npm i -g opencode-ai@latest        # or bun/pnpm/yarn
scoop install opencode             # Windows
choco install opencode             # Windows
brew install anomalyco/tap/opencode # macOS and Linux (recommended, always up to date)
brew install opencode              # macOS and Linux (official brew formula, updated less)
sudo pacman -S opencode            # Arch Linux (Stable)
paru -S opencode-bin               # Arch Linux (Latest from AUR)
mise use -g opencode               # Any OS
nix run nixpkgs#opencode           # or github:anomalyco/opencode for latest dev branch
```

Usage :

```bash
opencode --port
```

Then it's possible to call the opencode in the neovim and catch the request in the opencode terminal.

### 4. (Optional) Install Docker for DevContainers
    
```bash
# Debian / Ubuntu
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER   # re-login afterwards

# Fedora / RHEL
sudo dnf install -y docker-ce docker-ce-cli containerd.io

# Arch / Manjaro
sudo pacman -S docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER   # re-login afterwards
```

### 4. (Optional) Install the `devcontainer` CLI

```bash
# Requires Node.js (see below)
npm install -g @devcontainers/cli
```

### 5. (Optional) Install Node.js

```bash
# Debian / Ubuntu
sudo apt install -y nodejs npm

# Fedora / RHEL
sudo dnf install -y nodejs npm

# Arch / Manjaro
sudo pacman -S nodejs npm
```

---
## 🚀 Clone & Use This Configuration

### 1. Back up any existing config

```bash
mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null
mv ~/.local/share/nvim ~/.local/share/nvim.bak 2>/dev/null
mv ~/.local/state/nvim ~/.local/state/nvim.bak 2>/dev/null
mv ~/.cache/nvim ~/.cache/nvim.bak 2>/dev/null
```

### 2. Clone the repository

```bash
git clone git@github.com:Thejulfi/lazyvim-config.git ~/.config/nvim
```

> 🔁 **Keep it in sync**: If you want to track upstream changes and pull updates,
> clone as a normal git repo and add a `git pull` to your workflow:
> ```bash
> cd ~/.config/nvim && git pull
> ```

### 3. Launch Neovim

```bash
nvim
```

On the first launch, `lazy.nvim` bootstraps itself and installs all plugins
automatically. This may take a few minutes — watch the progress in the Lazy
dashboard.

---
## [Troubleshooting](doc/troubleshoot.md)

---

## 🔄 Updating

```bash
# Update all plugins
nvim +LazyUpdate

# Or inside Neovim
:Lazy update
```

LazyVim itself is updated through the same mechanism. Check the
[LazyVim docs](https://lazyvim.github.io) for upgrade notes between major versions.

## Full command list installation for RPI3/4 (from scratch)

### 1. Installation Neovim

```bash
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.tar.gz
sudo tar -C /opt -xzf nvim-linux-arm64.tar.gz
sudo ln -sf /opt/nvim-linux-arm64/bin/nvim /usr/local/bin/nvim
```

### 2. Installation LazyVim

```bash
git clone git@github.com:Thejulfi/lazyvim-config.git ~/.config/nvim
```

### 3. Installation Lazygit

```bash
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_arm64.tar.gz"
tar xf lazygit.tar.gz lazygit
sudo install lazygit /usr/local/bin
rm lazygit.tar.gz
```

### 4. End

```bash
nvim .
```

## Privates notes

If you need to add private notes that are ignored by git but still are accessible through the <leader> <leader> command, add a `.ignore` file including the files that indicate `fd` not to ignore in its research.

Like in the example below:

```bash
!.private/
!.private/notes.md
```
