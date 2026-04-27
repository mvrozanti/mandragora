-- lua/config/options.lua
-- Translated from settings.vim + general.vim
-- Dropped: nocompatible (no-op), filetype off/on (defaults), syntax enable (default),
--          encoding (default), fillchars+=vert:\$ (immediately overwritten),
--          vimDir/runtimepath manipulation (replaced by lazy.nvim + undodir fix)

local opt = vim.opt

opt.scrolloff    = 0
opt.cmdheight    = 0
opt.listchars    = { eol = '¬', tab = '»»', trail = '~', extends = '>', precedes = '<', space = '·' }
opt.visualbell   = true
opt.hlsearch     = true
opt.exrc         = true
opt.conceallevel = 0
opt.grepprg      = 'ag'
opt.hidden       = true
opt.clipboard    = { 'unnamed', 'unnamedplus' }
opt.completeopt  = { 'longest', 'menuone' }  -- overridden by nvim-cmp later
opt.fillchars    = { vert = '│' }
opt.linebreak    = true
opt.ruler        = true
opt.smartindent  = true
opt.tabstop      = 4
opt.softtabstop  = 4
opt.shiftwidth   = 4
opt.expandtab    = true
opt.mouse        = 'c'
opt.timeoutlen   = 300
opt.ttimeoutlen  = 0
opt.updatetime   = 300   -- faster git signs and cursor hold
opt.lazyredraw   = false  -- skip redraw during macros/scrolling
opt.redrawtime   = 500   -- cap expensive regex operations
opt.guicursor    = 'i:100-bCursor'
opt.showmode     = false  -- lualine handles mode display

-- 256-color terminal (user explicitly keeps notermguicolors)
-- t_Co is a Vim terminal option not available in Neovim's Lua API;
-- Neovim detects 256-color support automatically from $TERM.
vim.o.termguicolors = false
vim.o.background    = 'dark'

-- Persistent undo — fix: was using $HOME/.vim (Vim path), now uses Neovim stdpath
opt.undofile = true
opt.undodir  = vim.fn.stdpath('data') .. '/undodir'
vim.fn.mkdir(vim.fn.stdpath('data') .. '/undodir', 'p')
