# devbox — Instructions for an agent: wire up the image instead of configuring by hand

Instruction file aimed at a **coding agent** (OpenCode, Copilot CLI, Claude Code…).
Copy it into the project repository's `.opencode/` directory
(e.g. `.opencode/devbox-install-agents.md`) and reference it from the project's
instructions:

```markdown
## Dev environment
Use the devbox container: follow .opencode/devbox-install-agents.md (do not configure the environment by hand).
```

With OpenCode, you can also have it loaded automatically alongside `AGENTS.md`
by declaring it in `.opencode/opencode.jsonc`:

```jsonc
{
  "instructions": [".opencode/AGENTS.md", ".opencode/devbox-install-agents.md"]
}
```

> Image source of truth: [`busymoood/dotfiles-docker`](https://github.com/busymoood/dotfiles-docker) repository (full README: SSH chains, Raspberry, VPS, WSL2).

---

## Objective

Set up, in the current repository, a **dev container** based on the multi-arch
`ghcr.io/busymoood/dotfiles-docker` image: Ubuntu 24.04 · NeoVim + LazyVim · tmux · zsh ·
LazyGit · ripgrep · fd · fzf · OpenCode · jq · build-essential · openssh-client.

Personal configs (zsh, tmux, NeoVim/LazyVim) are **baked into the image**
(`zshrc/` and `neovim/` from the image repository, copied into `/opt/devbox-config`
then linked into `$HOME`). The `onstart` bootstrap no longer clones anything: it
prepares the state volume, checks the SSH agent and sets the git editor. **No
private key ever lives in the container** — everything goes through the SSH agent
socket, provided either by a direct mount (native Docker) or by the
`devbox-agent-relay` helper baked into the image (Docker Desktop, where a
non-Docker Unix socket cannot be mounted).

---

## 1. Prerequisites (check before anything else)

| Prerequisite | How to check | If missing |
|---|---|---|
| Docker | `docker version` | ask the user to install it |
| Host SSH agent (Bitwarden / `ssh -A` / WSL bridge) | `echo ${SSH_AUTH_SOCK:-}` then `ssh-add -l` | the dev container still starts (configs are in the image), but `git push` to GitHub will need HTTPS + PAT — warn the user |
| **Docker Desktop** (macOS, Windows/WSL2): agent TCP relay | `lsof -iTCP:4242 -sTCP:LISTEN` | launchd service `com.busymoood.socat-ssh-agent` (macOS): `socat TCP-LISTEN:4242,bind=0.0.0.0,reuseaddr,fork UNIX-CONNECT:$HOME/.bitwarden-ssh-agent.sock`; Windows: `socat.exe` on the same port to `//./pipe/openssh-ssh-agent` |

No configuration variable is required. Remove any `.env.example` / wrapper whose
only purpose was to inject `DOTFILES_REPO` or `NVIM_CONFIG_REPO`: those variables
no longer exist.

---

## 2. Create `.devcontainer/devcontainer.json`

Create the file **exactly** as follows (everything is relative to the project repo):

```jsonc
// .devcontainer/devcontainer.json
{
  "name": "devbox",
  "image": "ghcr.io/busymoood/dotfiles-docker:main",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind",
  "workspaceFolder": "/workspace",
  "containerEnv": {
    // Docker Desktop: the local socket is recreated by devbox-agent-relay.
    // Native Docker: set "SSH_AUTH_SOCK": "/ssh-agent" + the commented mount.
    "SSH_AUTH_SOCK": "${localEnv:DEVBOX_SSH_AUTH_SOCK:/tmp/ssh-agent.sock}"
  },
  "mounts": [
    // Native Docker only (Linux, WSL2 without Docker Desktop):
    // "source=${localEnv:SSH_AUTH_SOCK},target=/ssh-agent,type=bind",
    "source=devbox-home,target=/home/dev/.local,type=volume"
  ],
  // 1) SSH agent (direct mount or TCP relay, + retry if locked)
  // 2) onstart local checks (no clone)
  "postStartCommand": "devbox-agent-relay start; onstart --no-shell"
}
```

Points to watch for the agent:

- **Workspace bind**: code lives in the container at `/workspace` (mounted from the repo). Do not propose another path.
- **`devbox-home` volume**: tool state (nvim plugins, Mason, opencode auth, Supermaven key, Playwright browsers) persisting between sessions. Keep the literal name so state is shared with `devbox.sh` sessions. In `docker-compose.yml`, force `volumes: { devbox-home: { name: devbox-home } }` otherwise Compose prefixes it with the project name and creates a second volume.
- **NeoVim config**: already in the image (`/opt/devbox-config/nvim` → `~/.config/nvim`). Do not hand-write config inside the container: edit `neovim/` in the image repository and rebuild the image. Plugins, on the other hand, are installed on first launch into the `devbox-home` volume.
- **SSH agent**: `devbox-agent-relay start` (image helper) handles both direct mounts **and** TCP relays, logs to `~/.cache/devbox-agent-relay.log` and arms a retry (30 s × 10 min) if Bitwarden is locked. `devbox-agent-relay doctor` gives the full state.
- **Project overhead**: anything the project adds (Node, Python, Chromium…) must live in an idempotent script called by `postCreateCommand` (provisioning) and `postStartCommand` (relay + `onstart`), **not** duplicated between `devcontainer.json` and `docker-compose.yml`.
- **Tag naming**: CI runs automatically only on `main` (tags `main` + `latest`). Other branches are published only when the workflow is **manually dispatched** (`gh workflow run ci.yml --ref dev/jfi`), with the branch name as tag (`/` → `-`, e.g. `dev/jfi` → `dev-jfi`). There are no version or SHA tags. To pin an exact build, use the digest (`@sha256:...`) — **never write a tag that does not exist**.
- **`devcontainer up` on an existing container does not replay `postStartCommand`**: for a full cycle, use `--remove-existing-container` (volume preserved) or run `devbox-agent-relay start; onstart --no-shell` manually.
- If `SSH_AUTH_SOCK` does not exist on the host **and** Docker is native, the `mounts` entry will fail: remove it, warn the user, and let `devbox-agent-relay` report the missing agent.

> **`:latest` trap**: the CLI reuses the image if the tag exists locally, even if outdated
> (symptom: stale configs or missing binaries). Run
> `docker pull ghcr.io/busymoood/dotfiles-docker:latest` (or `:main`) before `up`,
> or pin the exact digest.

---

## 3. Start and verify (checklist)

Launch (devcontainers CLI, no VS Code needed):

```bash
# if @devcontainers/cli is not installed:
npm install -g @devcontainers/cli
devcontainer up --workspace-folder .
```

Then verify:
```bash
# container name: printed by devcontainer up (or docker ps --filter label=devcontainer.local_folder)
docker exec -it <container> bash -lc '
  devbox-agent-relay doctor &&
  nvim --version | head -1 && lazygit --version | head -1 && opencode --version &&
  ls -l ~/.zshrc ~/.tmux.conf ~/.config/nvim'
```

Checklist to tick and report:
1. `devbox-agent-relay doctor`: socket present, **keys listed** (Bitwarden unlocked).
2. `onstart` wrote no blocking error (a "muted agent" warning is fine if Bitwarden is locked).
3. `nvim`, `lazygit`, `opencode`, `tmux`, `rg`, `fd`, `fzf` respond.
4. `~/.zshrc` → `/opt/devbox-config/zshrc`, `~/.tmux.conf` → `/opt/devbox-config/tmux.conf`, `~/.config/nvim` → `/opt/devbox-config/nvim`.
5. `nvim` then `:Lazy` responds (first launch: ~1 min of plugin downloads into `devbox-home`).
6. `git -C /workspace config user.name` is OK (commit identity) → otherwise it is a git config matter, not a dev container one.

Leave the session with `docker exec -it <container> zsh -l` (zsh is the default shell; tmux → nvim is the normal flow).

---

## 4. Git / commits interaction

- Authentication goes **through the forwarded SSH agent** (`ssh-add -l` in the session to test). Nothing else to configure.
- If the agent is empty: warn the user ("Bitwarden locked?") without breaking the session — that is exactly `onstart`'s behavior.

---

## 5. Quick troubleshooting

| Symptom | Likely cause | Action |
|---|---|---|
| `ssh-add -l` → `No such file or directory` (Docker Desktop) | local relay dead / never started | `devbox-agent-relay start`; check on the host `lsof -iTCP:4242 -sTCP:LISTEN` |
| `ssh-add -l` → `communication with agent failed` | host agent muted (Bitwarden locked) | unlock Bitwarden; `ssh-add -l` must list keys **on the host** first |
| after `devcontainer up` nothing is replayed | `postStartCommand` does not run on an existing container | `devcontainer up --remove-existing-container` (volume preserved) or `devbox-agent-relay start; onstart --no-shell` |
| configs absent or stale in the container | stale local image (configs are in the image) | `docker pull ghcr.io/busymoood/dotfiles-docker:latest` then recreate the container |
| `Permission denied` on `~/.local/share/nvim` (LazyVim installs no plugin) | `devbox-home` volume created `root:root` by Docker | fixed since v0.4.0 (`onstart` fixes state-volume permissions); otherwise `sudo chown -R dev:dev ~/.local` |
| "Download spell file?" prompt for `fr` | French dictionary missing | fixed since v0.4.1 (fr preinstalled in the NeoVim runtime); otherwise answer `y` once |
| `[supermaven-nvim] sm-agent download failed` | plugin writes a **relative** temporary file; `WORKDIR` not writable | fixed since v0.4.1 (`WORKDIR /home/dev`); otherwise `cd ~` before launching nvim |
| Supermaven key requested for every container | `~/.supermaven/config.json` outside the volume | check that `~/.supermaven` is a symlink to `~/.local/share/supermaven` (created by `onstart` since v0.4.1) |
| `ssh-keyscan`/known_hosts noise at boot | first start without `~/.ssh` | fixed since v0.2.0 — report if seen on an older image |
| slow downloads / GitHub 504s | handled only **at image build time** (CI); a dev container pulls a ready-made image | do nothing; if image pulls keep failing, check GitHub infra status |
| nvim empty / no plugins | first LazyVim launch (~1 min of downloads) | wait; state is cached in `devbox-home` |

---

## 6. After the first setup

- Commit `.devcontainer/devcontainer.json` in the project repo (it contains no secrets, no personal URL and no config variable).
- Document in the project README:
  ```bash
  devcontainer up --workspace-folder .
  docker exec -it <container> zsh
  ```
- Update reminder: `docker pull ghcr.io/busymoood/dotfiles-docker:latest` (or a pinned digest). Configs are in the image: to change them, edit `zshrc/` or `neovim/` in the image repository, push to `main` (CI rebuilds), then pull the image and **Rebuild Container** on each machine.

---

## 7. Appendix — SSH agent in detail

No private key ever leaves **Bitwarden on your main machine**. What travels is only the agent **socket** (`$SSH_AUTH_SOCK`). Depending on the Docker engine, there are two modes:

| Host | Mode | Setup |
|---|---|---|
| **Native Linux** — VPS, Raspberry Pi, WSL2 with native Docker | direct socket mount | `-v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent` (automatic with `bin/devbox.sh`) |
| **Docker Desktop** — macOS, Windows/WSL2 with Docker Desktop integration | **TCP relay** (a non-Docker Unix socket cannot be mounted) | host: `socat TCP-LISTEN:4242,bind=0.0.0.0,reuseaddr,fork UNIX-CONNECT:$HOME/.bitwarden-ssh-agent.sock` (launchd service) · container: `-e SSH_AUTH_SOCK=/tmp/ssh-agent.sock -e DEVBOX_SSH_RELAY=1` |

`bin/devbox.sh` decides on its own: it queries `docker info` (Docker Desktop?) and switches to relay mode if needed.

**`devbox-agent-relay` helper** (baked into the image):

```bash
devbox-agent-relay start    # create the socket (TCP relay) or check a direct mount
devbox-agent-relay doctor   # socket, target, PID, visible keys, configs
devbox-agent-relay stop     # stop the local relay
```

- The relay runs in a **detached session** (`setsid`): it survives the end of `postStartCommand` (a plain `nohup … &` dies with the session → muted agent afterwards).
- **Locked agent** (Bitwarden closed): `start` warns and arms a **retry** (30 s × 10 min) that replays `onstart` as soon as keys appear — no need to recreate the container.
- `onstart` waits up to 5 s for the socket then checks the agent for information only: without an agent, `git push` to GitHub will need HTTPS + PAT (configs, they are already in the image).

**Forwarding chains:**

| Scenario | Chain |
|---|---|
| macOS + Docker Desktop | Bitwarden → `~/.bitwarden-ssh-agent.sock` → socat TCP `4242` (launchd) → container relay → `/tmp/ssh-agent.sock` |
| macOS + native Docker engine (Colima, Docker via Linux VM) | Bitwarden → `~/.bitwarden-ssh-agent.sock` → direct mount `/ssh-agent` |
| WSL2 + native Docker | Bitwarden (Windows) → `openssh-ssh-agent` pipe → npiperelay+socat → `~/.ssh/agent.sock` → mount `/ssh-agent` |
| WSL2 + Docker Desktop | same up to `~/.ssh/agent.sock` → socat TCP `4242` → container relay |
| Raspberry / VPS (native Docker) | Bitwarden (Mac) → `ssh -A` → sshd socket on the host → mount `/ssh-agent` |

> The container can **only request signatures** from the agent — it never reads a private key.
>
> The launchd relay listens on `0.0.0.0:4242` (`host.docker.internal` cannot reach loopback): on an untrusted network, restrict the port to the Docker Desktop subnet with a `pf` rule.

**Quick diagnosis**

```bash
# host (Docker Desktop): is the relay running?
lsof -iTCP:4242 -sTCP:LISTEN
ssh-add -l                                  # keys must appear here first

# container: full state (relay, socket, keys, configs)
devbox-agent-relay doctor
# after unlocking Bitwarden:
devbox-agent-relay start
```

**Typical symptoms:**

| Symptom | Cause | Action |
|---|---|---|
| `ssh-add -l` → `No such file or directory` (container) | dead relay (old `nohup` killed with the session) | `devbox-agent-relay start` |
| `ssh-add -l` → `communication with agent failed` | muted host agent (Bitwarden locked) | unlock Bitwarden, `ssh-add -l` on the host, then `devbox-agent-relay start` |
| stale configs after a `devcontainer up` | `postStartCommand` not replayed on an existing container / stale local image | `docker pull …` then `devcontainer up --remove-existing-container` (volume preserved) |

**Dev container variant — native Docker** (README default = Docker Desktop): in `.devcontainer/devcontainer.json`, replace `"SSH_AUTH_SOCK": "${localEnv:DEVBOX_SSH_AUTH_SOCK:/tmp/ssh-agent.sock}"` with `"SSH_AUTH_SOCK": "/ssh-agent"` and uncomment in `mounts`:

```jsonc
"source=${localEnv:SSH_AUTH_SOCK},target=/ssh-agent,type=bind"
```
