# Architecture of a Portable Devbox

This repository builds **ghcr.io/busymoood/dotfiles-docker**: a multi-arch
(linux/amd64 + linux/arm64) development image based on Ubuntu 24.04, with zsh,
tmux, NeoVim/LazyVim, lazygit, ripgrep, fd, fzf and OpenCode.

## 1. Architecture overview

Everything needed to work is self-contained in the image; nothing is cloned or
downloaded at container startup.

- **Image = binaries + configs.** Tools are installed at build time. Personal
  configs are versioned in this repository and baked into the image, then
  symlinked into the `dev` user's `$HOME`.
- **State volume = runtime state.** `~/.local` is a named Docker volume
  (`devbox-home`) for LazyVim/Mason and other tool state that must survive
  container recreation.
- **SSH agent forwarding = authentication.** No private key is ever stored in
  the image or the container: the host's agent socket is forwarded (or relayed
  over TCP on Docker Desktop).

## 2. Repository layout

| Path | Role |
| --- | --- |
| `Dockerfile` | Installs the tools, bakes the configs, creates the symlinks |
| `zshrc/zshrc`, `zshrc/tmux.conf` | Zsh and tmux configs (also used on macOS) |
| `neovim/` | LazyVim configuration |
| `lazygit/config.yml` | Global lazygit config (nvim as editor) |
| `onstart.sh` | Image entrypoint / bootstrap, also usable as `onstart --no-shell` |
| `devbox-agent-relay` | Recreates the host SSH agent socket from a TCP relay |
| `devcontainer.json` | Sample devcontainer definition used in this repository |
| `.github/workflows/ci.yml` | Buildx + publish to GHCR (amd64 + arm64) on push to `main` / tags |

## 3. How configs are installed

`Dockerfile` copies the config folders into `/opt/devbox-config` and creates
symlinks in `$HOME`:

| In the image | Symlink in `$HOME` |
| --- | --- |
| `/opt/devbox-config/zshrc` | `~/.zshrc` |
| `/opt/devbox-config/tmux.conf` | `~/.tmux.conf` |
| `/opt/devbox-config/nvim/` | `~/.config/nvim` |
| `/opt/devbox-config/lazygit/config.yml` | `~/.config/lazygit/config.yml` |

`/opt/devbox-config` stays in an image layer and is never overwritten by the
`~/.local` volume. The zsh copy is patched at build time (SSH socket line,
Oh My Zsh update checks) so the source files in `zshrc/` remain usable on macOS.

To change a config: edit the file here, push to `main`; CI rebuilds and
republishes the image. On each machine, pull the image and recreate the
container. LazyVim plugins are installed at runtime into the `devbox-home`
volume and update independently of the image.

## 4. Editors

- The image exports `EDITOR=nvim VISUAL=nvim`, and `onstart.sh` sets
  `git config --global core.editor nvim`. This is what lazygit uses for commit
  messages (`C` / `R`) and what Git uses for `git commit`.
- `lazygit/config.yml` sets `os.editPreset: nvim-remote` for file editing
  (`e`). In a plain terminal, nvim runs in the same terminal and lazygit
  resumes after `:q`; when `$NVIM` is set (Neovim `:terminal` / floating
  terminal), the file opens in the parent Neovim instance.
- Repo-specific lazygit overrides remain possible via `.git/lazygit.yml` or
  `.lazygit.yml` in a project; they take precedence over the global config.

## 5. Container bootstrap (`onstart.sh`)

Runs at every start (entrypoint, or `onstart --no-shell` from
`postStartCommand`):

1. Fix permissions on the `~/.local` volume and persist the Supermaven state.
2. Add github.com to `~/.ssh/known_hosts`.
3. Detect the forwarded SSH agent (with optional TCP relay retry).
4. Ensure `core.editor = nvim`.
5. Set zsh as the default shell.
6. Start the interactive session (or just exit with `--no-shell`).

## 6. Usage

Dev container (see `README.md` for the full snippet):

```bash
devcontainer up --workspace-folder .
docker exec -it <container> zsh
```

VPS / Raspberry Pi (same multi-arch tag):

```bash
docker run -d --name devbox \
  -v devbox-local:/home/dev/.local \
  -v /opt/devbox/workspaces:/workspace \
  -v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent \
  ghcr.io/busymoood/dotfiles-docker:main sleep infinity
docker exec -it devbox zsh
```

Updating: `docker pull` the new tag, then recreate the container (a mount or
image change cannot be applied in place). The state volume is preserved.
