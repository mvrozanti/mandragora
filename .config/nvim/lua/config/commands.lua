-- lua/config/commands.lua
-- Translated from commands.vim + post-init.vim lines 1-3.
-- Bugs fixed:
--   - :OR deleted (called CocAction; coc not installed)
--   - :RemoveDiacritics fixed (s:RemoveDiacritics → RemoveDiacritics)
--   - :Jsonify fixed (python → python3)
--   - jsonify alias fixed (python → python3)
--   - pi/pc aliases updated (PlugInstall/PlugClean → Lazy sync/clean)

local cmd = vim.api.nvim_create_user_command

-- Reverse line order in range
cmd('Reverse', function(opts)
  vim.cmd(opts.line1 .. ',' .. opts.line2 .. 'global/^/m' .. (opts.line1 - 1))
end, { bar = true, range = '%' })

-- Jump to a random line
cmd('RandomLine', function()
  local n = math.floor(
    tonumber(vim.fn.system('bash -c "echo -n $RANDOM"')) % vim.fn.line('$')
  )
  vim.cmd('normal! ' .. n .. 'G')
end, {})

-- Pretty-print JSON in buffer (fix: python3, not python)
cmd('Jsonify', function()
  vim.cmd(':%!python3 -m json.tool')
end, {})

-- JS beautify
cmd('JsBeautify', function()
  vim.cmd(':%!slimit')
end, {})

-- RemoveDiacritics on range (fix: was calling s:RemoveDiacritics — wrong script-local prefix)
cmd('RemoveDiacritics', function(opts)
  RemoveDiacritics(opts.line1, opts.line2)
end, { range = '%' })

-- Show whitespace
cmd('ShowWhitespace', function()
  vim.cmd('set list')
end, {})

-- Copy absolute file path to X clipboard via xsel
cmd('Rpc', function()
  local path = vim.fn.shellescape(vim.fn.expand('%:p'), 1)
  vim.fn.system('echo -n ' .. path .. '| xsel -i -b')
end, {})

-- Command aliases (from post-init.vim lines 1-3)
-- fix: python → python3; plug aliases → lazy aliases
SetupCommandAlias('jsonify', '%!python3 -m json.tool')
SetupCommandAlias('pi', 'Lazy sync')
SetupCommandAlias('pc', 'Lazy clean')
