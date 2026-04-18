" nvim-treesitter configuration
if filereadable(expand('~/.config/nvim/plugged/nvim-treesitter/plugin/nvim-treesitter.lua'))
lua << EOF
require('nvim-treesitter.configs').setup {
  ensure_installed = {
    "c", "cpp", "python", "javascript", "typescript", "lua",
    "bash", "json", "yaml", "html", "css", "markdown",
    "latex", "java", "vim", "vimdoc", "query",
  },
  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
  },
  indent = {
    enable = true,
  },
  incremental_selection = {
    enable = true,
    keymaps = {
      init_selection = "<C-Space>",
      node_incremental = "<C-Space>",
      scope_incremental = false,
      node_decremental = "<C-BS>",
    },
  },
}
EOF
endif
