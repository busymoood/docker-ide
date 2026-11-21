-- Override clangd configuration to use the system clangd binary.
--
-- mason cannot install clangd on aarch64 ("The current platform is unsupported"),
-- so we set `mason = false` to force LazyVim to enable the server directly
-- using the system clangd binary at /usr/bin/clangd.
--
-- NOTE: we intentionally do NOT pass --compile-commands-dir here. The project
-- uses hierarchical .clangd files (root .clangd -> build/ for the firmware,
-- tests/.clangd -> ../build/tests for the native unit tests). Forcing a single
-- compile-commands-dir would override those and break parsing of the tests.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          mason = false,
          cmd = {
            "/usr/bin/clangd",
            "--background-index",
            "--clang-tidy",
            "--header-insertion=iwyu",
            "--completion-style=detailed",
            "--function-arg-placeholders",
            "--fallback-style=llvm",
          },
        },
      },
    },
  },
}

