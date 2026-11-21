
## Quick Troubleshooting

### `clangd` not found / LSP not starting

This setup uses a system `clangd`. Make sure the binary is installed and on
`PATH`:

```bash
clangd --version
```

- **Linux**: see the install section above. If your distro names it
  `clangd-XX`, symlink it to `/usr/bin/clangd`.
- **macOS**: make sure Xcode Command Line Tools are installed.

### Plugins fail to install

On first launch, ensure you have a stable internet connection. If a plugin fails:

```bash
# Inside Neovim
:Lazy install
:Lazy build     # rebuild if a build step failed
```

### Avante (AI chat) not working

1. Make sure `DEEPSEEK_API_KEY` is set in your environment.
2. Restart Neovim so the environment variable is picked up.
3. Run `:Avante` to open the chat panel.

### Supermaven not suggesting

- The free tier doesn't require an API key.
- If you have a paid key, set `SUPERMAVEN_API_KEY`.
- Toggle suggestions with `<C-]>` (clear) or `<Tab>` (accept).

### Reset everything

```bash
rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
# Then re-clone and launch nvim again
```

---

## Trouble shooting history

### Issue Summary on RPI3 (04-08-2026)

Neovim fails on launch with vim/loader: write_cachefile error and Unknown system error -74 (or assertion failures). This occurs when system package managers install an outdated Neovim version (e.g., < 0.9.0), or when the bytecode cache (vim.loader) becomes corrupted due to SD card/filesystem write errors.

#### Step-by-Step Fix
1. Purge Outdated Neovim Binaries

```Bash
sudo apt remove --purge neovim
sudo apt autoremove
sudo rm -f /usr/bin/nvim
```
2. Clean Corrupted Caches & States

```Bash
rm -rf ~/.cache/nvim ~/.local/state/nvim ~/.local/share/nvim
```

3. Install Neovim 0.10+ (ARM64)

```Bash
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.tar.gz
sudo tar -C /opt -xzf nvim-linux-arm64.tar.gz
sudo ln -sf /opt/nvim-linux-arm64/bin/nvim /usr/local/bin/nvim
```

4. Resolve Filesystem Errors & Disable vim.loader (If Cache Fails)

Fix corrupt SD card sectors: Run `sudo touch forcefsck && sudo reboot` to perform a disk repair on boot.

Bypass bytecode caching: Comment out `vim.loader.enable()` in your `~/.config/nvim/init.lua` (or `lua/config/lazy.lua`):

---

## Old alias nvim fix

If when you launch Neovim, you get the following error:

```bash
```bash
-bash: /home/jfi/projects/nvim-linux-arm64/bin/nvim: No such file or directory
```

You need to make sure to remove the old `nvim` and get rid of potential aliases.

```bash
unalias nvim
```

Then you can safely reinstall Neovim.
