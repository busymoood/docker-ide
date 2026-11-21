# my personal IDE

My personal IDE, a docker image that I can deploy everywhere and contains everything and need and nothing I don't.

An all-in-one Docker image (**NeoVim + LazyVim**, **tmux**, **zsh**, **LazyGit**, **ripgrep**, **fd**, **fzf**, **OpenCode**…), built for **amd64 + arm64** and published automatically to **GHCR** by CI.

Personal configs (**zsh**, **tmux**, **NeoVim/LazyVim**, **lazygit**) are **baked into the image**: no network clone at startup, even without an SSH agent. They are versioned here in `zshrc/`, `neovim/` and `lazygit/`, copied into `/opt/devbox-config` and linked into `$HOME`. No private key is ever stored in the image.

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

## VPS / Raspberry Pi

On any SSH host (VPS, RPi 4/5 **64-bit**), the image runs as a long-lived container that you enter with `docker exec`. The image is multi-arch (amd64 + arm64), so the **same tag** works everywhere — verify with `docker image inspect ... --format '{{.Architecture}}'`.

### 1. Host prerequisites

```bash
# Docker
curl -fsSL https://get.docker.com | sh
# or: apt update && apt install -y docker.io docker-compose-plugin
```

**Allow your user to run Docker (no `sudo`).** The Docker socket `/var/run/docker.sock` belongs to `root:docker`. Until your user is in the `docker` group, every command fails with:

Add the user once, right after installing Docker:

```bash
sudo usermod -aG docker $USER     # e.g. sudo usermod -aG docker jfi
getent group docker              # your user must appear in the member list
```

⚠️ **This is not active in the current shell.** Group membership is read when the login session starts, so `usermod` alone is not enough — you must start a fresh session:

```bash
newgrp docker        # quick: new shell with the docker group active
```

### 2. Pull the image

```bash
docker pull ghcr.io/busymoood/dotfiles-docker:main
```

### 3. Run the container with your projects mounted

From your laptop, connect **with agent forwarding** so no private key is ever copied to the server:

```bash
mkdir -p /opt/devbox/workspaces

docker run -d --name devbox \
  -v devbox-local:/home/dev/.local \
  -v /opt/devbox/workspaces:/workspace \
  -v <your-projects-home>:/host-home \
  -v "$SSH_AUTH_SOCK:/ssh-agent" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  ghcr.io/busymoood/dotfiles-docker:main \
  sleep infinity

docker exec -it devbox zsh
```


| Path in container | Source on the host | Purpose |
| --- | --- | --- |
| `/workspace` | `/opt/devbox/workspaces` | your projects (read/write) |
| `/host-home` | `<your-projects-home>` | host files |
| `/home/dev/.local` | `devbox-local` volume | LazyVim/Mason state, kept across recreations |
| `/ssh-agent` | `$SSH_AUTH_SOCK` via `ssh -A` | `git push` uses your local agent |

Useful shortcut (created inside the bind mount, so it survives recreations):

```bash
docker exec -it devbox zsh -lc 'ln -sfn /host-home /workspace/vps-home'
# then: cd /workspace/vps-home && nvim . && lazygit
```

### 4. Update on a `docker run` host

A mount cannot be added to an existing container: remove and recreate it. The volume and bind mounts are preserved.

```bash
docker pull ghcr.io/busymoood/dotfiles-docker:main
docker stop devbox && docker rename devbox devbox-old   # keep a fallback
# re-run the exact same `docker run` command from step 3
docker exec -it devbox zsh -lc 'nvim --version | head -1'
docker rm -f devbox-old
```

Or simply `docker rm -f devbox` before re-running. Note that `$SSH_AUTH_SOCK` is tied to the `ssh -A` session: re-run the container from a fresh forwarded session (or relay the agent through a stable host socket with `socat`) if `git push` stops authenticating.

## Updating the image

Binaries **and** configs come from the image. The devcontainers CLI reuses the local image if the tag exists, even if outdated: you must **force a pull** then **recreate** the container. The `devbox-home` volume is preserved.

```bash
# :latest tag — explicit re-pull, otherwise the stale local image is reused
docker pull ghcr.io/busymoood/dotfiles-docker:main
devcontainer up --workspace-folder . --remove-existing-container
```

Then enter the recreated container: `docker exec -it <container-name> zsh`.

On a `docker run` host (VPS / Raspberry Pi), the equivalent is `docker pull` + `docker rm -f devbox` + the same `docker run` command — see [Update on a `docker run` host](#4-update-on-a-docker-run-host). In both cases the state volume is preserved; only the image layers change.

To change a config: edit `zshrc/`, `neovim/` or `lazygit/` in this repository and push to `main` — CI rebuilds and republishes the image. On each machine, pull the image then **Rebuild Container**. LazyVim plugins, on the other hand, are installed at runtime into the `devbox-home` volume and stay up to date independently.

`lazygit/config.yml` sets `os.editPreset: nvim-remote`: `e` opens files in nvim (in the same terminal, or in the parent Neovim instance when `$NVIM` is set). Commit messages use git's `core.editor = nvim`, configured by `onstart`.
