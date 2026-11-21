-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.tabstop = 4      -- Number of spaces a tab character displays as
vim.opt.shiftwidth = 4   -- Number of spaces per indentation level (<< or >>)
vim.opt.softtabstop = 4  -- Number of spaces inserted when pressing Tab
vim.opt.expandtab = true -- Convert tabs to spaces
vim.g.autoformat = false -- Disable auto-formatting on save (conform.nvim)
vim.opt.clipboard = "unnamedplus"
vim.g.clipboard = {
  name = 'OSC 52',
  copy = {
    ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
    ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
  },
  paste = {
    ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
    ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
  },
}
vim.opt.relativenumber = false
vim.opt.number = true
vim.opt.modeline = false -- Disabled to avoid modeline detection on clangd comments such as "ex: "

-- Make sure node (via nvm) is available for the markdown-preview.nvim plugin
if vim.fn.executable("node") == 0 then
  local nvm_dir = vim.fn.expand("$HOME/.nvm")
  local node_bin = nvm_dir .. "/versions/node"
  local handle = io.popen("ls " .. node_bin .. " 2>/dev/null")
  if handle then
    local version = handle:read("*l")
    handle:close()
    if version and version ~= "" then
      vim.env.PATH = node_bin .. "/" .. version .. "/bin:" .. vim.env.PATH
    end
  end
end
