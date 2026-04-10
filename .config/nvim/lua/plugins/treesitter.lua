-- lua/plugins/treesitter.lua
-- nvim-treesitter: properly configured with parsers for all languages in use.
-- Previously installed but had ZERO configuration.

return {
  {
    'nvim-treesitter/nvim-treesitter',
    build  = ':TSUpdate',
    event  = { 'BufReadPost', 'BufNewFile' },
    config = function()
      require('nvim-treesitter').setup({
        ensure_installed = {
          -- Neovim config
          'lua', 'vim', 'vimdoc',
          -- Primary languages (from autocommands + plugin usage)
          'python', 'javascript', 'typescript',
          'c', 'cpp', 'java', 'kotlin',
          -- Web / data
          'html', 'css', 'json', 'yaml',
          -- Shell / docs
          'bash', 'markdown', 'markdown_inline',
          -- Other (from BufEnter autocommands)
          'prolog',
        },

        auto_install = true,

        highlight = {
          enable = true,
          disable = function(_, buf)
            local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
            if ok and stats and stats.size > 100 * 1024 then return true end
            local ft = vim.bo[buf].filetype
            if ft == 'javascript' then return true end
            return false
          end,
          additional_vim_regex_highlighting = { 'javascript' },
        },

        indent = { enable = true },

        incremental_selection = {
          enable  = true,
          keymaps = {
            -- Default treesitter keymaps — don't conflict with map.vim
            -- (map.vim uses ; and + for vim-expand-region instead)
            init_selection    = 'gnn',
            node_incremental  = 'grn',
            scope_incremental = 'grc',
            node_decremental  = 'grm',
          },
        },
      })
    end,
  },
}
