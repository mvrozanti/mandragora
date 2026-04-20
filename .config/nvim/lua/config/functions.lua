-- lua/config/functions.lua
-- Translated from functions.vim.
-- All four functions are defined as Lua globals so VimL shims at the bottom can call them.
-- map.vim calls these via :call Killit(), :call Synctex() etc. — the shims bridge that.

-- SetupCommandAlias: create a cmdline abbreviation that only expands as a full command
function SetupCommandAlias(from, to)
  vim.cmd(string.format(
    'cnoreabbrev <expr> %s ((getcmdtype() is# ":" && getcmdline() is# "%s") ? ("%s") : ("%s"))',
    from, from, to, from
  ))
end

-- UTF-8 codepoint iterator (Lua string.gsub is byte-based; need this for diacritics)
local function utf8_chars(s)
  return s:gmatch('[%z\1-\127\194-\244][\128-\191]*')
end

-- RemoveDiacritics: replace accented characters in a line range
function RemoveDiacritics(line1, line2)
  local diacs_lower = 'áâãàçéêíóôõüú'
  local repls_lower = 'aaaaceeiooouu'

  local map = {}
  local function build_pairs(d, r)
    local di, ri = {}, {}
    for c in utf8_chars(d) do di[#di + 1] = c end
    for c in utf8_chars(r) do ri[#ri + 1] = c end
    for i = 1, #di do map[di[i]] = ri[i] end
  end
  build_pairs(diacs_lower, repls_lower)

  -- Build uppercase variants
  local diacs_upper = {}
  local repls_upper = {}
  for c in utf8_chars(diacs_lower) do diacs_upper[#diacs_upper + 1] = c:upper() end
  for c in utf8_chars(repls_lower) do repls_upper[#repls_upper + 1] = c:upper() end
  for i = 1, #diacs_upper do map[diacs_upper[i]] = repls_upper[i] end

  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  for i, line in ipairs(lines) do
    for src, dst in pairs(map) do
      line = line:gsub(src, dst)
    end
    lines[i] = line
  end
  vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, lines)
end

-- Killit: close buffer or quit intelligently
function Killit()
  local listed = vim.fn.getbufinfo({ buflisted = 1 })
  if #listed == 1 then
    local ok = pcall(vim.cmd, 'silent q')
    if not ok then
      pcall(vim.cmd, 'wq')
    end
  else
    local ok = pcall(vim.cmd, 'bd')
    if not ok then
      if vim.bo.buftype == 'nofile' then
        pcall(vim.cmd, 'q')
      end
    end
  end
end

-- Synctex: forward sync to Zathura for LaTeX
function Synctex()
  local line = vim.fn.line('.')
  local col  = vim.fn.col('.')
  local file = vim.fn.bufname('%')
  local pdf  = file:sub(1, -5) .. '.pdf'
  vim.fn.system(string.format(
    'zathura --synctex-forward %d:%d:%s %s &',
    line, col, vim.fn.shellescape(file), vim.fn.shellescape(pdf)
  ))
  vim.cmd('redraw!')
end

-- VimL shim wrappers — map.vim calls these as :call Killit() etc.
-- These must be defined so that sourcing map.vim after this module works.
vim.cmd([[
  function! Killit() abort
    lua Killit()
  endfunction

  function! Synctex() abort
    lua Synctex()
  endfunction

  function! SetupCommandAlias(from, to) abort
    lua SetupCommandAlias(vim.fn.eval('a:from'), vim.fn.eval('a:to'))
  endfunction

  function! RemoveDiacritics(l1, l2) abort
    lua RemoveDiacritics(vim.fn.eval('a:l1'), vim.fn.eval('a:l2'))
  endfunction
]])
