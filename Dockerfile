# devbox — Environnement de développement portable (terminal-first)
# Multi-arch : linux/amd64 + linux/arm64
# Ubuntu 24.04 (glibc 2.39) : requis par les parsers Treesitter précompilés
# de nvim-treesitter (branche main) — sur 22.04 (glibc 2.35) ils échouent avec
# « version `GLIBC_2.39' not found ».
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

USER root

# --- Utilisateur « dev » -----------------------------------------------------
# L'image de base fournit un compte `vscode` (UID 1000). On le renomme en `dev`
# (nom de l'environnement, indépendant de tout éditeur) : home /home/dev,
# groupe dev, sudoers renommé, metadata devcontainer mise à jour pour que
# `remoteUser` vaille `dev` par défaut.
RUN set -eux; \
    usermod -l dev -d /home/dev -m vscode; \
    groupmod -n dev vscode; \
    if [ -f /etc/sudoers.d/vscode ]; then \
      mv /etc/sudoers.d/vscode /etc/sudoers.d/dev; \
      sed -i 's/^vscode/dev/' /etc/sudoers.d/dev; \
    fi; \
    chown -R dev:dev /home/dev
LABEL devcontainer.metadata='[{"remoteUser":"dev"}]'

# --- Outils système de base -------------------------------------------------
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
    ca-certificates \
    jq \
  && rm -rf /var/lib/apt/lists/* \
  && ln -sf /usr/bin/fdfind /usr/local/bin/fd

# --- NeoVim (dernière version stable, binaire officiel multi-arch) ----------
# Assets : nvim-linux-x86_64.tar.gz / nvim-linux-arm64.tar.gz
# NB : on télécharge via l'API GitHub (assets/<id> + Accept: octet-stream)
# plutôt que via releases/latest/download — les redirections github.com
# renvoient des 504 intermittents (buildx CI, Docker Desktop proxy).
RUN set -eux; \
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true; \
    case "$(dpkg --print-architecture)" in \
      amd64)  NVIM_ARCH="x86_64" ;; \
      arm64)  NVIM_ARCH="arm64"  ;; \
      *) echo "arch non supportée" >&2; exit 1 ;; \
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

# --- LazyGit (dernière version stable, binaire officiel multi-arch) ---------
# Même remarque que nvim : download via l'API GitHub, pas via releases/latest.
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

# --- Dictionnaires spell (FR) ------------------------------------------------
# NeoVim n'embarque que l'anglais (en.utf-8.spl). Sans fr.utf-8.spl, un
# `spelllang=fr` déclenche un prompt « Download spell file? » au démarrage.
# Vim publie les dictionnaires sur son miroir officiel (pas sur GitHub).
RUN set -eux; \
    SPELL_DIR=/opt/nvim/share/nvim/runtime/spell; \
    mkdir -p "$SPELL_DIR"; \
    for f in fr.utf-8.spl fr.utf-8.sug; do \
      curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
        -o "${SPELL_DIR}/${f}" "https://ftp.nluug.nl/pub/vim/runtime/spell/${f}"; \
      test -s "${SPELL_DIR}/${f}"; \
    done; \
    ls -l "$SPELL_DIR"

# --- Bootstrap des dotfiles + relais agent SSH ------------------------------
COPY onstart.sh /tmp/onstart.sh
RUN install -m 0755 /tmp/onstart.sh /usr/local/bin/onstart && rm /tmp/onstart.sh

# Relais agent SSH : montage direct (Docker natif) ou relais TCP (Docker
# Desktop, où un socket Unix non-docker ne peut pas être monté).
COPY devbox-agent-relay /tmp/devbox-agent-relay
RUN install -m 0755 /tmp/devbox-agent-relay /usr/local/bin/devbox-agent-relay \
  && rm /tmp/devbox-agent-relay

# --- OpenCode V2 (installeur officiel opencode.ai) ---------------------------
USER dev
RUN set -eux; \
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true; \
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
      https://opencode.ai/v2/install | bash; \
    test -x "$HOME/.opencode/bin/opencode"; \
    sudo ln -sf "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode

# --- Session par défaut -----------------------------------------------------
# WORKDIR inscriptible : certains plugins (supermaven-nvim) téléchargent via un
# fichier temporaire RELATIF — avec WORKDIR=/ (défaut de l'image de base), curl
# échoue en « write error » (exit 23) et le binaire n'est jamais récupéré.
WORKDIR /home/dev

# Le bootstrap (onstart) s'exécute automatiquement avant le shell :
#   docker run -it ghcr.io/busymoood/dotfiles-docker:latest
# Sans terminal (ex: postStartCommand), utiliser : onstart --no-shell
ENTRYPOINT ["/usr/local/bin/onstart"]
CMD ["zsh", "-l"]
