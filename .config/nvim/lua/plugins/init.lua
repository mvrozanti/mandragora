-- lua/plugins/init.lua
-- lazy.nvim bootstrap + all plugin specs.
-- All non-critical plugins are lazy-loaded by event, cmd, or ft.

-- ─────────────────────────────────────────────────────────────────────────────
-- Bootstrap lazy.nvim (auto-installs on first run)
-- ─────────────────────────────────────────────────────────────────────────────
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable',
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ─────────────────────────────────────────────────────────────────────────────
-- Plugin specs
-- ─────────────────────────────────────────────────────────────────────────────
require('lazy').setup({

  -- ── Sub-module configs ──────────────────────────────────────────────────
  { import = 'plugins.treesitter' },
  { import = 'plugins.ui' },
  { import = 'plugins.git' },
  { import = 'plugins.lsp' },
  { import = 'plugins.editing' },

  -- ── Niche / specialized plugins (ALL lazy-loaded) ───────────────────────

  -- tig-explorer: open tig in a terminal buffer
  { 'iberianpig/tig-explorer.vim',   cmd = { 'TigExplorer', 'TigExplorerFile' } },

  -- ansible-vim: syntax for Ansible playbooks/roles
  { 'pearofducks/ansible-vim',       ft  = { 'yaml.ansible', 'ansible' } },

  -- tcomment_vim: comment operator
  { 'tomtom/tcomment_vim',           cmd = { 'TComment', 'TCommentBlock', 'TCommentInline' } },

  -- vim-tmux-navigator: pane navigation between vim and tmux
  {
    'christoomey/vim-tmux-navigator',
    lazy = false,
    init = function()
      vim.g.tmux_navigator_no_mappings = 1
    end,
  },

  -- vim-surround: surround motion
  { 'tpope/vim-surround' },

  -- vim-latex: full LaTeX suite
  {
    'lervag/vim-latex',
    ft   = { 'tex', 'latex' },
    init = function()
      vim.g.tex_flavor = 'latex'
    end,
  },

  -- vim-commentary: gc comment operator
  { 'tpope/vim-commentary' },

  -- vim-multiple-cursors: multiple cursor editing
  { 'terryma/vim-multiple-cursors',  cmd = { 'MultipleCursors' } },

  -- vim-closetag: auto-close HTML/XML tags
  { 'alvan/vim-closetag',            ft  = { 'html', 'xml', 'xhtml' } },

  -- vim-jsonpath: JSON path navigation
  { 'mogelbrod/vim-jsonpath',        ft  = { 'json' } },

  -- vim-cmake-completion: CMake file completions
  { 'richq/vim-cmake-completion',    ft  = { 'cmake' } },

  -- greplace.vim: project-wide search and replace
  { 'skwp/greplace.vim',             cmd = { 'GReplace' } },

  -- vim-exchange: exchange two motion targets
  { 'tommcdo/vim-exchange' },

  -- nvim-autopairs: auto-close pairs, treesitter-aware
  {
    'windwp/nvim-autopairs',
    event  = 'InsertEnter',
    config = function()
      require('nvim-autopairs').setup({
        check_ts = true,
        fast_wrap = {},
      })
      local ok, cmp = pcall(require, 'cmp')
      if ok then
        cmp.event:on('confirm_done',
          require('nvim-autopairs.completion.cmp').on_confirm_done())
      end
    end,
  },

  -- tabular: text alignment
  { 'godlygeek/tabular',             cmd = { 'Tabularize' } },

  -- goyo.vim: distraction-free writing mode
  {
    'junegunn/goyo.vim',
    cmd  = { 'Goyo' },
    init = function()
      vim.g.goyo_width  = '85%'
      vim.g.goyo_height = '90%'

      local saved = {}
      vim.api.nvim_create_autocmd('User', {
        pattern = 'GoyoEnter',
        callback = function()
          saved.laststatus  = vim.o.laststatus
          saved.showtabline = vim.o.showtabline
          saved.cmdheight   = vim.o.cmdheight
          pcall(require('lualine').hide, { place = { 'statusline', 'tabline', 'winbar' } })
          vim.o.laststatus  = 0
          vim.o.showtabline = 0
          vim.o.cmdheight   = 0
        end,
      })
      vim.api.nvim_create_autocmd('User', {
        pattern = 'GoyoLeave',
        callback = function()
          vim.o.laststatus  = saved.laststatus  or 3
          vim.o.showtabline = saved.showtabline or 1
          vim.o.cmdheight   = saved.cmdheight   or 1
          pcall(require('lualine').hide, { place = { 'statusline', 'tabline', 'winbar' }, unhide = true })
        end,
      })
    end,
  },

  -- nvim-web-devicons: icon support
  { 'nvim-tree/nvim-web-devicons',   lazy = true },

  -- a.vim: switch between C header and source file
  { 'mvrozanti/a.vim',               ft  = { 'c', 'cpp' } },

  -- webapi-vim: HTTP client (dependency)
  { 'mattn/webapi-vim',              lazy = true },

  -- unicode.vim: Unicode character search
  { 'chrisbra/unicode.vim',          cmd = { 'UnicodeSearch', 'UnicodeName', 'UnicodeTable' } },

  -- yajs.vim: richer JavaScript syntax
  { 'othree/yajs.vim',               ft  = { 'javascript' } },

  -- JavaScript-Indent: JS indentation
  { 'vim-scripts/JavaScript-Indent', ft  = { 'javascript' } },

  -- rename.vim: rename file in-place
  { 'danro/rename.vim',              cmd = { 'Rename' } },

  -- markdown-preview.nvm: browser preview for Markdown
  {
    'iamcco/markdown-preview.nvim',
    ft    = { 'markdown' },
    build = 'cd app && yarn install',
    init  = function()
      vim.g.mkdp_browser       = 'firefox'
      vim.g.mkdp_highlight_css = vim.fn.expand('$HOME/css/darkdown.css')
    end,
  },

  -- argtextobj.vim: argument text object (ia, aa)
  { 'vim-scripts/argtextobj.vim' },

  -- tagbar: code structure sidebar
  { 'majutsushi/tagbar',             cmd = { 'TagbarToggle' } },

  -- vim-processing: Processing IDE filetype support
  { 'sophacles/vim-processing',      ft  = { 'pde' } },

}, {
  ui = {
    border = 'rounded',
  },
  performance = {
    cache = {
      enabled = true,
    },
    rtp = {
      disabled_plugins = {
        'gzip', 'matchit', 'matchparen', 'netrwPlugin',
        'tarPlugin', 'tohtml', 'tutor', 'zipPlugin',
      },
    },
  },
})
