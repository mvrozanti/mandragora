-- lua/config/autocmds.lua
-- Only essential autocmds that can't be handled by ftplugin.
-- FileType-specific settings have been moved to ftplugin/ files.

local augroup = vim.api.nvim_create_augroup
local au      = vim.api.nvim_create_autocmd

-- Shim for removed vim-startify plugin (prevents E492 errors)
vim.api.nvim_create_user_command('Startify', function() end, {})

-- ─────────────────────────────────────────────────────────────────────────────
-- LaTeX: async compilation via command (opt-in, NOT automatic on save)
-- ─────────────────────────────────────────────────────────────────────────────
augroup('LatexCompile', { clear = true })

vim.api.nvim_create_user_command('LatexCompile', function()
  local file = vim.fn.expand('%:p')
  vim.fn.jobstart({ 'pdflatex', file }, {
    on_exit = function(_, code)
      if code == 0 then
        vim.fn.jobstart({ 'pdflatex', '-synctex=1', file }, {
          on_exit = function(_, c2)
            if c2 ~= 0 then
              vim.notify('pdflatex (synctex pass) failed', vim.log.levels.WARN)
            end
          end,
        })
      else
        vim.notify('pdflatex failed (exit ' .. code .. ')', vim.log.levels.ERROR)
      end
    end,
  })
end, { desc = 'Compile current LaTeX file' })

vim.api.nvim_create_user_command('LatexBibCompile', function()
  local base = vim.fn.expand('%:p:r')
  local tex  = base .. '.tex'
  vim.fn.jobstart({ 'bibtex', base }, {
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify('bibtex failed', vim.log.levels.WARN)
        return
      end
      vim.fn.jobstart({ 'pdflatex', tex }, {
        on_exit = function()
          vim.fn.jobstart({ 'pdflatex', '-synctex=1', tex }, {})
        end,
      })
    end,
  })
end, { desc = 'Compile bibliography and LaTeX' })

-- ─────────────────────────────────────────────────────────────────────────────
-- Filetype detection for non-standard extensions
-- ─────────────────────────────────────────────────────────────────────────────
augroup('FileTypeDetect', { clear = true })

au({ 'BufEnter', 'BufRead' }, { group = 'FileTypeDetect', pattern = '*.pro',
  callback = function() vim.opt_local.filetype = 'prolog' end })
au({ 'BufEnter', 'BufRead' }, { group = 'FileTypeDetect', pattern = '*.p5',
  callback = function() vim.opt_local.filetype = 'javascript' end })
au({ 'BufEnter', 'BufRead' }, { group = 'FileTypeDetect', pattern = '*.kt',
  callback = function() vim.opt_local.filetype = 'kotlin' end })
au({ 'BufEnter', 'BufRead' }, { group = 'FileTypeDetect', pattern = '*.wl',
  callback = function() vim.opt_local.filetype = 'wolframlanguage' end })
au({ 'BufEnter', 'BufRead' }, { group = 'FileTypeDetect', pattern = '*polybar/config',
  callback = function() vim.opt_local.filetype = 'polybar' end })

-- Force redraw on resize (fixes cmdheight=0 artifacts in tmux)
au("VimResized", {
  group = augroup("ResizeFix", { clear = true }),
  callback = function()
    vim.cmd("redraw!")
  end,
})
