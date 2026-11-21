# Dotfiles (zshrc, tmux)

> **In devbox**: these files are baked into the image and linked into `$HOME`; the standalone instructions below are not needed in the container.

Command to create a symlink:

```bash
ln -s ~/dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/dotfiles/zshrc ~/.zshrc
```

## Tmux plugin installation and activation

Clone the tpm repository

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Add the plugin to `~/.tmux.conf`

```bash
# Plugin list
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'

# Optional: restore pane contents
set -g @resurrect-capture-pane-contents 'on'

# Initialize TPM (must stay at the very end)
run '~/.tmux/plugins/tpm/tpm'
```

Reload tmux configuration

```bash
tmux source ~/.tmux.conf
```

Install the plugin from tmux by launching tmux and pressing `Ctrl + b` and then `Shift + i`.
