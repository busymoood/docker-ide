-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
-- Delete the previous word in insert mode with Option + \ (⌥ + \)

vim.keymap.set("i", "<M-BS>", "<C-w>", { desc = "Delete previous word" })

local opts = { noremap = true, silent = true, nowait = true }

-- Start of line (Ctrl + a) and end of line (Ctrl + e) in insert mode
vim.keymap.set("i", "<C-a>", "<C-o>^", { desc = "Start of line" })
vim.keymap.set("i", "<C-e>", "<C-o>$", { desc = "End of line" })

-- Move word by word with Ctrl + arrows (if cmux lets Ctrl through)
vim.keymap.set("i", "<C-Left>", "<C-o>b", { desc = "Previous word" })
vim.keymap.set("i", "<C-Right>", "<C-o>w", { desc = "Next word" })
-- Leave terminal mode with a double Escape
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Leave terminal mode" })

vim.api.nvim_set_keymap("i", "jj", "<Esc>", { noremap = false })
vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = false })

-- Open LazyVim's native floating terminal with Ctrl+t
-- Replace <C-t> with a global shortcut for the Snacks floating terminal
vim.keymap.set({ "n", "t", "i" }, "<C-t>", function()
  Snacks.terminal.toggle()
end, { desc = "Floating terminal" })
