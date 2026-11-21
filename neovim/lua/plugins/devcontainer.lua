return {
  {
    "jedrzejboczar/devcontainers.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {
      -- Use the official devcontainer CLI
      devcontainers_binary = "devcontainer",
      -- Automatically generate LSP attach commands
      autocommands = true,
    },
    config = function(_, opts)
      require("devcontainers").setup(opts)
    end,
  },
}
