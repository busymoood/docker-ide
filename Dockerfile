# devbox — Portable development environment (terminal-first)
# Multi-arch: linux/amd64 + linux/arm64
# Ubuntu 24.04 (glibc 2.39) is required by the prebuilt Treesitter parsers of
# nvim-treesitter (main branch) — on 22.04 (glibc 2.35) they fail with
# "version `GLIBC_2.39' not found".
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# Default editor: nvim (used by lazygit, git, opencode…)
ENV EDITOR=nvim VISUAL=nvim

USER root

# --- "dev" user --------------------------------------------------------------
# The base image provides a `vscode` account (UID 1000). Rename it to `dev`
# (environment name, independent of any editor): home /home/dev, dev group,
# renamed sudoers entry, updated devcontainer metadata so `remoteUser`
# defaults to `dev`.
RUN set -eux; \
    usermod -l dev -d /home/dev -m vscode; \
    groupmod -n dev vscode; \
    if [ -f /etc/sudoers.d/vscode ]; then \
      mv /etc/sudoers.d/vscode /etc/sudoers.d/dev; \
      sed -i 's/^vscode/dev/' /etc/sudoers.d/dev; \
    fi; \
    chown -R dev:dev /home/dev
LABEL devcontainer.metadata='[{"remoteUser":"dev"}]'

# --- Base system tools -------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    zsh \
    tmux \
    ripgrep \
    fd-find \
    fzf \
    build-essential \
    unzip \
    openssh-client \
    socat \
    iproute2 \
    ca-certificates \
    jq \
  && rm -rf /var/lib/apt/lists/* \
  && ln -sf /usr/bin/fdfind /usr/local/bin/fd

# --- Oh My Zsh plugins -------------------------------------------------------
# The base image already ships Oh My Zsh in ~/.oh-my-zsh; the baked zshrc
# enables these two plugins, which are absent from the base image.
RUN set -eux; \
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true; \
    OMZ=/home/dev/.oh-my-zsh; \
    test -f "$OMZ/oh-my-zsh.sh"; \
    for plugin in zsh-autosuggestions zsh-syntax-highlighting; do \
      dest="$OMZ/custom/plugins/${plugin}"; \
      rm -rf "$dest"; \
      for i in 1 2 3; do \
        git clone --depth=1 "https://github.com/zsh-users/${plugin}.git" "$dest" && break; \
        rm -rf "$dest"; sleep 5; \
      done; \
      test -d "$dest"; \
    done; \
    chown -R dev:dev "$OMZ/custom"

# --- TPM (tmux plugins: tpm + tmux-resurrect) --------------------------------
# The baked tmux.conf ends with `run '~/.tmux/plugins/tpm/tpm'`.
RUN set -eux; \
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true; \
    TPM=/home/dev/.tmux/plugins/tpm; \
    RESURRECT=/home/dev/.tmux/plugins/tmux-resurrect; \
    for i in 1 2 3; do \
      git clone --depth=1 https://github.com/tmux-plugins/tpm.git "$TPM" && break; \
      rm -rf "$TPM"; sleep 5; \
    done; \
    test -f "$TPM/tpm"; \
    for i in 1 2 3; do \
      git clone --depth=1 https://github.com/tmux-plugins/tmux-resurrect.git "$RESURRECT" && break; \
      rm -rf "$RESURRECT"; sleep 5; \
    done; \
    test -f "$RESURRECT/resurrect.tmux"; \
    chown -R dev:dev /home/dev/.tmux

# --- User configs baked into the image --------------------------------------
# The content is versioned in this repository (zshrc/, neovim/, lazygit/): no
# network clone at container startup. /opt/devbox-config stays in the image
# layer and is not overwritten by the ~/.local volume; the symlinks live in
# $HOME.
COPY zshrc/zshrc        /opt/devbox-config/zshrc
COPY zshrc/tmux.conf    /opt/devbox-config/tmux.conf
COPY neovim/            /opt/devbox-config/nvim/
COPY lazygit/           /opt/devbox-config/lazygit/

RUN set -eux; \
    # These files are also used on macOS: patch the IMAGE COPY, not the source.
    sed -i 's|^export SSH_AUTH_SOCK=.*|# SSH_AUTH_SOCK provided by devbox (agent relay) - do not override|' /opt/devbox-config/zshrc; \
    sed -i 's|^source .*oh-my-zsh.sh|zstyle ":omz:update" mode disabled\n&|' /opt/devbox-config/zshrc; \
    ln -sf /opt/devbox-config/zshrc     /home/dev/.zshrc; \
    ln -sf /opt/devbox-config/tmux.conf /home/dev/.tmux.conf; \
    mkdir -p /home/dev/.config; \
    ln -sfn /opt/devbox-config/nvim      /home/dev/.config/nvim; \
    mkdir -p /home/dev/.config/lazygit; \
    ln -sf /opt/devbox-config/lazygit/config.yml /home/dev/.config/lazygit/config.yml; \
    chown -R dev:dev /opt/devbox-config

# --- NeoVim (latest stable, official multi-arch binary) ---------------------
# Assets: nvim-linux-x86_64.tar.gz / nvim-linux-arm64.tar.gz
# NB: download via the GitHub API (assets/<id> + Accept: octet-stream) rather
# than releases/latest/download — github.com redirects return intermittent
# 504s (buildx CI, Docker Desktop proxy).
RUN set -eux; \
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true; \
    case "$(dpkg --print-architecture)" in \
      amd64)  NVIM_ARCH="x86_64" ;; \
      arm64)  NVIM_ARCH="arm64"  ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    NVIM_ASSET="nvim-linux-${NVIM_ARCH}.tar.gz"; \
    NVIM_URL="$(curl -fsSL --retry 10 --retry-delay 5 --retry-all-errors \
      "https://api.github.com/repos/neovim/neovim/releases/latest" \
      | jq -r --arg n "${NVIM_ASSET}" '.assets[] | select(.name == $n) | .url')"; \
    test -n "${NVIM_URL}"; \
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
      -H 'Accept: application/octet-stream' -o /tmp/nvim.tar.gz "${NVIM_URL}"; \
    tar -C /opt -xzf /tmp/nvim.tar.gz; \
    mv "/opt/nvim-linux-${NVIM_ARCH}" /opt/nvim; \
    ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim; \
    rm /tmp/nvim.tar.gz

# --- LazyGit (latest stable, official multi-arch binary) --------------------
# Same remark as nvim: download via the GitHub API, not releases/latest.
RUN set -eux; \
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true; \
    LG_META="$(curl -fsSL --retry 10 --retry-delay 5 --retry-all-errors \
      https://api.github.com/repos/jesseduffield/lazygit/releases/latest)"; \
    LG_VERSION="$(printf '%s' "${LG_META}" | jq -r '.tag_name | sub("^v";"")')"; \
    case "$(dpkg --print-architecture)" in \
      amd64)  LG_ARCH="x86_64" ;; \
      arm64)  LG_ARCH="arm64"  ;; \
    esac; \
    lg_asset="lazygit_${LG_VERSION}_linux_${LG_ARCH}.tar.gz"; \
    LG_URL="$(printf '%s' "${LG_META}" \
      | jq -r --arg n "${lg_asset}" '.assets[] | select(.name == $n) | .url')"; \
    test -n "${LG_URL}"; \
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
      -H 'Accept: application/octet-stream' -o /tmp/lazygit.tar.gz "${LG_URL}"; \
    tar -C /tmp -xzf /tmp/lazygit.tar.gz lazygit; \
    install /tmp/lazygit /usr/local/bin/lazygit; \
    rm /tmp/lazygit /tmp/lazygit.tar.gz

# --- French spell dictionaries -----------------------------------------------
# NeoVim only ships English (en.utf-8.spl). Without fr.utf-8.spl, setting
# `spelllang=fr` triggers a "Download spell file?" prompt at startup.
# Vim publishes dictionaries on its official mirror (not on GitHub).
RUN set -eux; \
    SPELL_DIR=/opt/nvim/share/nvim/runtime/spell; \
    mkdir -p "$SPELL_DIR"; \
    for f in fr.utf-8.spl fr.utf-8.sug; do \
      curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
        -o "${SPELL_DIR}/${f}" "https://ftp.nluug.nl/pub/vim/runtime/spell/${f}"; \
      test -s "${SPELL_DIR}/${f}"; \
    done; \
    ls -l "$SPELL_DIR"

# --- Bootstrap + SSH agent relay --------------------------------------------
COPY onstart.sh /tmp/onstart.sh
RUN install -m 0755 /tmp/onstart.sh /usr/local/bin/onstart && rm /tmp/onstart.sh

# SSH agent relay: direct mount (native Docker) or TCP relay (Docker Desktop,
# where a non-Docker Unix socket cannot be mounted).
COPY devbox-agent-relay /tmp/devbox-agent-relay
RUN install -m 0755 /tmp/devbox-agent-relay /usr/local/bin/devbox-agent-relay \
  && rm /tmp/devbox-agent-relay

# --- OpenCode V2 (official installer from opencode.ai) ----------------------
USER dev
RUN set -eux; \
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true; \
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
      https://opencode.ai/v2/install | bash; \
    test -x "$HOME/.opencode/bin/opencode"; \
    sudo ln -sf "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode

# --- Default session ---------------------------------------------------------
# Writable WORKDIR: some plugins (supermaven-nvim) download via a RELATIVE
# temporary file — with WORKDIR=/ (base image default), curl fails with a
# "write error" (exit 23) and the binary is never fetched.
WORKDIR /home/dev

# The bootstrap (onstart) runs automatically before the shell:
#   docker run -it ghcr.io/busymoood/dotfiles-docker:latest
# Without a TTY (e.g. postStartCommand), use: onstart --no-shell
ENTRYPOINT ["/usr/local/bin/onstart"]
CMD ["zsh", "-l"]
