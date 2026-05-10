vim.api.nvim_create_autocmd("BufWritePost", {
  buffer = 0,
  callback = function()
    local file = vim.fn.expand('%:p')
    local dir = vim.fn.expand('%:p:h')
    local fonts = dir .. '/fonts'
    local cmd = { 'typst', 'compile' }
    if vim.fn.isdirectory(fonts) == 1 then
      table.insert(cmd, '--font-path')
      table.insert(cmd, fonts)
    end
    table.insert(cmd, file)
    vim.fn.jobstart(cmd)
  end,
})
