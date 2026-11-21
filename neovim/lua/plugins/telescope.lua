return {
  "nvim-telescope/telescope.nvim",
  opts = {
    defaults = {
      -- Force Telescope find_files to include hidden files
      file_ignore_patterns = { "%.git/" }, -- Optional: Ignore .git directory so it doesn't clutter results
    },
    pickers = {
      find_files = {
        hidden = true, -- Shows dotfiles (.devcontainer, .env, etc.)
      },
    },
  },
}
