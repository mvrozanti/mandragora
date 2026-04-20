-- lua/plugins/git.lua
-- gitsigns (replaces vim-gitgutter)
-- vim-fugitive (kept)
-- diffview.nvim (kept)

return {

  -- ── gitsigns: replaces vim-gitgutter ───────────────────────────────────────
  {
    'lewis6991/gitsigns.nvim',
    event  = { 'BufReadPost', 'BufNewFile' },
    config = function()
      require('gitsigns').setup({
        signs = {
          add          = { text = '│' },
          change       = { text = '│' },
          delete       = { text = '_' },
          topdelete    = { text = '‾' },
          changedelete = { text = '~' },
          untracked    = { text = '┆' },
        },
        signcolumn = true,
        numhl      = false,
        linehl     = false,
        word_diff  = false,

        on_attach = function(bufnr)
          local gs   = package.loaded.gitsigns
          local opts = { buffer = bufnr, silent = true }

          -- Navigate between hunks
          vim.keymap.set('n', ']c', function()
            if vim.wo.diff then return ']c' end
            vim.schedule(function() gs.next_hunk() end)
            return '<Ignore>'
          end, { expr = true, buffer = bufnr, desc = 'Next hunk' })

          vim.keymap.set('n', '[c', function()
            if vim.wo.diff then return '[c' end
            vim.schedule(function() gs.prev_hunk() end)
            return '<Ignore>'
          end, { expr = true, buffer = bufnr, desc = 'Prev hunk' })

          -- Hunk operations
          vim.keymap.set({ 'n', 'v' }, '<leader>hs', gs.stage_hunk,        vim.tbl_extend('force', opts, { desc = 'Stage hunk' }))
          vim.keymap.set({ 'n', 'v' }, '<leader>hr', gs.reset_hunk,        vim.tbl_extend('force', opts, { desc = 'Reset hunk' }))
          vim.keymap.set('n',          '<leader>hS', gs.stage_buffer,       vim.tbl_extend('force', opts, { desc = 'Stage buffer' }))
          vim.keymap.set('n',          '<leader>hu', gs.undo_stage_hunk,    vim.tbl_extend('force', opts, { desc = 'Undo stage hunk' }))
          vim.keymap.set('n',          '<leader>hR', gs.reset_buffer,       vim.tbl_extend('force', opts, { desc = 'Reset buffer' }))
          vim.keymap.set('n',          '<leader>hp', gs.preview_hunk,       vim.tbl_extend('force', opts, { desc = 'Preview hunk' }))
          vim.keymap.set('n',          '<leader>hb', function() gs.blame_line({ full = true }) end, vim.tbl_extend('force', opts, { desc = 'Blame line' }))
          vim.keymap.set('n',          '<leader>hd', gs.diffthis,           vim.tbl_extend('force', opts, { desc = 'Diff this' }))

          -- Sign colors matching post-init.vim AirlineGitDiff* ctermbg colors
          vim.api.nvim_set_hl(0, 'GitSignsAdd',    { ctermfg = 22  })  -- AirlineGitDiffAdded   ctermbg=22
          vim.api.nvim_set_hl(0, 'GitSignsChange', { ctermfg = 136 })  -- AirlineGitDiffChanged ctermbg=136
          vim.api.nvim_set_hl(0, 'GitSignsDelete', { ctermfg = 160 })  -- AirlineGitDiffRemoved ctermbg=160
        end,
      })
    end,
  },

  -- ── vim-fugitive: Git commands ──────────────────────────────────────────────
  {
    'tpope/vim-fugitive',
    cmd = { 'G', 'Git', 'Gdiffsplit', 'Gread', 'Gwrite', 'Ggrep', 'GMove', 'GDelete', 'GBrowse' },
  },

  -- ── diffview.nvim: side-by-side diff / file history ────────────────────────
  {
    'sindrets/diffview.nvim',
    cmd          = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewToggleFiles', 'DiffviewFocusFiles' },
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config       = function()
      require('diffview').setup()
    end,
  },

}
