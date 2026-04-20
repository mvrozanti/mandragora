-- init.lua — Neovim entry point
-- Full Lua migration from init.vim.
-- Load order is mandatory: functions must be before commands/autocmds/map.vim
-- since they all call SetupCommandAlias(), Killit(), etc.

-- 1. Options (replaces settings.vim + general.vim)
require('config.options')

-- 2. Utility functions + VimL shims for map.vim compatibility
--    MUST load before commands, autocmds, and map.vim
require('config.functions')

-- 3. Custom user commands (replaces commands.vim; bugs fixed)
require('config.commands')

-- 4. Autocommands (replaces autocommands.vim; async LaTeX, pymode removed)
require('config.autocmds')

-- 5. Plugin manager bootstrap + all plugin specs (replaces plug.vim + let.vim)
require('plugins')

-- 6. Keybindings — source map.vim completely unchanged
--    By this point all functions, commands, and plugins are available
vim.cmd('source ' .. vim.fn.stdpath('config') .. '/map.vim')

-- 7. Colorscheme — applied last so plugin highlights don't overwrite it
local pywal = vim.fn.stdpath('config') .. '/colors/pywal.vim'
if vim.fn.filereadable(pywal) == 1 then
  vim.cmd('colorscheme pywal')
end
