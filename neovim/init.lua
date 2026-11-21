-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.spell = true
vim.opt.spelllang = { 'fr', 'en' }

vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained" }, {
  callback = function(args)
    if vim.bo[args.buf].buftype == "" and not vim.bo[args.buf].modifiable then
      vim.bo[args.buf].modifiable = true
    end
  end,
})

vim.opt.wrap = true
