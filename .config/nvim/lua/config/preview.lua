local M = {}

local jobs = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Preview' })
end

local function browser()
  local b = vim.g.mkdp_browser
  if type(b) == 'string' and b ~= '' then
    return b
  end
  return 'xdg-open'
end

local function detach(cmd)
  vim.fn.jobstart(cmd, { detach = true })
end

local function stop_job(buf)
  local id = jobs[buf]
  if not id then
    return false
  end
  jobs[buf] = nil
  pcall(vim.fn.jobstop, id)
  return true
end

local function watch(buf, cmd)
  stop_job(buf)
  jobs[buf] = vim.fn.jobstart(cmd, {
    on_stderr = function(_, data)
      local msg = table.concat(data or {}, '\n')
      if msg:lower():match('error') then
        vim.schedule(function() notify(msg, vim.log.levels.ERROR) end)
      end
    end,
    on_exit = function()
      jobs[buf] = nil
    end,
  })
end

local function already_viewing(path)
  vim.fn.system({ 'pgrep', '-f', 'zathura.*' .. vim.fn.fnamemodify(path, ':t') })
  return vim.v.shell_error == 0
end

local function open_pdf(pdf)
  if vim.fn.filereadable(pdf) == 0 then
    notify('no output at ' .. pdf, vim.log.levels.ERROR)
    return
  end
  if already_viewing(pdf) then
    notify('zathura already viewing ' .. vim.fn.fnamemodify(pdf, ':t'))
    return
  end
  detach({ 'zathura', pdf })
end

local function lazy_load(plugin)
  local ok, lazy = pcall(require, 'lazy')
  if ok then
    pcall(lazy.load, { plugins = { plugin } })
  end
end

local function has_command(name)
  return vim.fn.exists(':' .. name) == 2
end

local handlers = {}

handlers.markdown = {
  start = function()
    lazy_load('markdown-preview.nvim')
    if not has_command('MarkdownPreview') then
      return false, 'markdown-preview.nvim unavailable'
    end
    vim.cmd('MarkdownPreview')
    return true, 'markdown-preview → ' .. browser()
  end,
  stop = function()
    if not has_command('MarkdownPreviewStop') then
      return false
    end
    vim.cmd('MarkdownPreviewStop')
    return true
  end,
}

handlers.typst = {
  start = function(ctx)
    local cmd = { 'typst', 'watch' }
    local fonts = ctx.dir .. '/fonts'
    if vim.fn.isdirectory(fonts) == 1 then
      table.insert(cmd, '--font-path=' .. fonts)
    end
    table.insert(cmd, '--open=zathura')
    table.insert(cmd, ctx.file)
    watch(ctx.buf, cmd)
    return true, 'typst watch → zathura'
  end,
}

handlers.tex = {
  start = function(ctx)
    local pdf = ctx.dir .. '/' .. vim.fn.fnamemodify(ctx.file, ':t:r') .. '.pdf'
    notify('pdflatex ' .. vim.fn.fnamemodify(ctx.file, ':t'))
    vim.fn.jobstart({ 'pdflatex', '-interaction=nonstopmode', '-synctex=1', ctx.file }, {
      cwd = ctx.dir,
      on_exit = function(_, code)
        vim.schedule(function()
          if code ~= 0 and vim.fn.filereadable(pdf) == 0 then
            notify('pdflatex failed (exit ' .. code .. ')', vim.log.levels.ERROR)
            return
          end
          open_pdf(pdf)
        end)
      end,
    })
    return true
  end,
}

handlers.dot = {
  start = function(ctx)
    local out = vim.fn.tempname() .. '.svg'
    vim.fn.jobstart({ 'dot', '-Tsvg', '-o', out, ctx.file }, {
      cwd = ctx.dir,
      on_exit = function(_, code)
        vim.schedule(function()
          if code ~= 0 then
            notify('dot failed (exit ' .. code .. ')', vim.log.levels.ERROR)
            return
          end
          detach({ browser(), out })
        end)
      end,
    })
    return true, 'graphviz → ' .. browser()
  end,
}

handlers.html = {
  start = function(ctx)
    detach({ browser(), ctx.file })
    return true, browser() .. ' ' .. vim.fn.fnamemodify(ctx.file, ':t')
  end,
}

handlers.pdf = {
  start = function(ctx)
    open_pdf(ctx.file)
    return true
  end,
}

local aliases = {
  latex = 'tex',
  plaintex = 'tex',
  context = 'tex',
  xhtml = 'html',
  svg = 'html',
  xml = 'html',
  graphviz = 'dot',
  typ = 'typst',
  ['markdown.pandoc'] = 'markdown',
  rmd = 'markdown',
  vimwiki = 'markdown',
}

local function handler_for(ft)
  return handlers[aliases[ft] or ft]
end

local function context(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  if file == '' then
    return nil, 'buffer has no file on disk'
  end
  if vim.bo[buf].modified and vim.bo[buf].modifiable then
    local ok, err = pcall(vim.cmd, 'silent keepalt write')
    if not ok then
      return nil, 'could not write buffer: ' .. tostring(err)
    end
  end
  return {
    buf = buf,
    file = file,
    dir = vim.fn.fnamemodify(file, ':h'),
    ft = vim.bo[buf].filetype,
  }
end

function M.active(buf)
  return jobs[buf or vim.api.nvim_get_current_buf()] ~= nil
end

function M.start(bang)
  local buf = vim.api.nvim_get_current_buf()
  local ctx, err = context(buf)
  if not ctx then
    notify(err, vim.log.levels.ERROR)
    return
  end

  local handler = not bang and handler_for(ctx.ft)
  if not handler then
    local ok, ui_err = pcall(vim.ui.open, ctx.file)
    if ok then
      notify('no previewer for ' .. (ctx.ft ~= '' and ctx.ft or 'this buffer') .. ', opened externally')
    else
      notify('no previewer for ' .. ctx.ft .. ': ' .. tostring(ui_err), vim.log.levels.ERROR)
    end
    return
  end

  local started, msg = handler.start(ctx)
  if not started then
    notify(msg or ('previewer for ' .. ctx.ft .. ' failed'), vim.log.levels.ERROR)
  elseif msg then
    notify(msg)
  end
end

function M.stop()
  local buf = vim.api.nvim_get_current_buf()
  local handler = handler_for(vim.bo[buf].filetype)
  local stopped = stop_job(buf)
  if handler and handler.stop and handler.stop() then
    stopped = true
  end
  notify(stopped and 'stopped' or 'nothing to stop')
end

vim.api.nvim_create_user_command('Preview', function(opts)
  M.start(opts.bang)
end, { bang = true, desc = 'Preview current buffer with the previewer for its filetype' })

vim.api.nvim_create_user_command('PreviewStop', function()
  M.stop()
end, { desc = 'Stop the preview started by :Preview' })

vim.api.nvim_create_autocmd('BufUnload', {
  group = vim.api.nvim_create_augroup('PreviewCleanup', { clear = true }),
  callback = function(ev)
    stop_job(ev.buf)
  end,
})

return M
