# Devbox — Dev Container

An all-in-one Docker image (**NeoVim + LazyVim**, **tmux**, **zsh**, **LazyGit**, **ripgrep**, **fd**, **fzf**, **OpenCode**…), built for **amd64 + arm64** and published automatically to **GHCR** by CI.

Personal configs (**zsh**, **tmux**, **NeoVim/LazyVim**) are **baked into the image**: no network clone at startup, even without an SSH agent. They are versioned here in `zshrc/` and `neovim/`, copied into `/opt/devbox-config` and linked into `$HOME`. No private key is ever stored in the image.

## Quickstart

### 1. `.devcontainer/devcontainer.json`

At the root of the project repository:

```jsonc
// .devcontainer/devcontainer.json
{
  "name": "devbox",
  "image": "ghcr.io/busymoood/dotfiles-docker:main", // or :latest — see "Updating the image"
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind",
  "workspaceFolder": "/workspace",
  "containerEnv": {
    "SSH_AUTH_SOCK": "${localEnv:DEVBOX_SSH_AUTH_SOCK:/tmp/ssh-agent.sock}"
  },
  "mounts": [
    "source=devbox-home,target=/home/dev/.local,type=volume" // tool state, kept between sessions
  ],
  // SSH agent then local bootstrap (no clone)
  "postStartCommand": "devbox-agent-relay start; onstart --no-shell"
}
```

### 2. Start

```bash
npm install -g @devcontainers/cli                       # if the CLI is not installed yet
devcontainer up --workspace-folder .
docker exec -it <container-name> zsh                    # enter the container
```

`onstart` (the image entrypoint) prepares the state volume, checks the SSH agent and sets the git editor. Configs are already present in the image.

## Updating the image

Binaries **and** configs come from the image. The devcontainers CLI reuses the local image if the tag exists, even if outdated: you must **force a pull** then **recreate** the container. The `devbox-home` volume is preserved.

```bash
# :latest tag — explicit re-pull, otherwise the stale local image is reused
docker pull ghcr.io/busymoood/dotfiles-docker:main
devcontainer up --workspace-folder . --remove-existing-container
```

Then enter the recreated container: `docker exec -it <container-name> zsh`.

To change a config: edit `zshrc/` or `neovim/` in this repository and push to `main` — CI rebuilds and republishes the image. On each machine, pull the image then **Rebuild Container**. LazyVim plugins, on the other hand, are installed at runtime into the `devbox-home` volume and stay up to date independently.
