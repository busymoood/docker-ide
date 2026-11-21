return {
  "folke/snacks.nvim",
  opts = {
    terminal = {
      win = {
        position = "float",
      }
    },
    picker = {
      sources = {
        files = {
          hidden = true, -- Includes hidden files (e.g., .devcontainer, .env)
          ignored = false, -- Set to true if you also want to show files ignored by .gitignore
        },
      },
    },
  },
}
