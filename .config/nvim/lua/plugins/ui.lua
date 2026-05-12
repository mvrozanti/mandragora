-- lua/plugins/ui.lua
-- lualine (statusline)
-- oil.nvim (file explorer, replaces NERDTree)

return {

  -- ── lualine: replaces vim-airline ──────────────────────────────────────────
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()

      -- Material You palette slots from kitty/matugen (cterm 0-15).
      -- In dark mode: *_container slots (4,5,6) are dark; *_fixed slots
      -- (9,10,11) are light. Pair container-bg with fixed-fg for readable
      -- contrast across every matugen palette. Mixing *_fixed as a bg
      -- with cube 231 as fg was the prior bright-on-bright bug.
      local c = {
        surface          = 0,
        surface_variant  = 8,
        primary_ctr      = 4,
        secondary_ctr    = 5,
        tertiary_ctr     = 6,
        primary_fix      = 9,
        secondary_fix    = 10,
        tertiary_fix     = 11,
        on_surface       = 7,
        on_surface_var   = 15,
        cube_replace_bg  = 52,
        cube_white       = 231,
      }

      local theme = {
        normal = {
          a = { fg = c.primary_fix,    bg = c.primary_ctr,     bold = true },
          b = { fg = c.on_surface,     bg = c.surface_variant },
          c = { fg = c.on_surface_var, bg = c.surface },
        },
        insert = {
          a = { fg = c.secondary_fix,  bg = c.secondary_ctr,   bold = true },
          b = { fg = c.on_surface,     bg = c.surface_variant },
          c = { fg = c.on_surface_var, bg = c.surface },
        },
        visual = {
          a = { fg = c.tertiary_fix,   bg = c.tertiary_ctr,    bold = true },
          b = { fg = c.on_surface,     bg = c.surface_variant },
          c = { fg = c.on_surface_var, bg = c.surface },
        },
        replace = {
          a = { fg = c.cube_white,     bg = c.cube_replace_bg, bold = true },
          b = { fg = c.on_surface,     bg = c.surface_variant },
          c = { fg = c.on_surface_var, bg = c.surface },
        },
        command = {
          a = { fg = c.on_surface,     bg = c.surface_variant, bold = true },
          b = { fg = c.on_surface,     bg = c.surface_variant },
          c = { fg = c.on_surface_var, bg = c.surface },
        },
        inactive = {
          a = { fg = c.on_surface_var, bg = c.surface_variant },
          b = { fg = c.on_surface_var, bg = c.surface },
          c = { fg = c.on_surface_var, bg = c.surface },
        },
      }

      -- ── File icon (translated from MyAirline_GetFileIcon) ────────────────
      local ext_icons = {
        c = '', h = '', cpp = '', rs = '', go = '',
        py = '', js = '', ts = '', sh = '', lua = '',
        java = '', kt = '', html = '', xhtml = '',
        json = '', yaml = '', yml = '', toml = '',
        ini = '', conf = '', md = '', txt = '',
        pdf = '', epub = '', zip = '', tar = '',
        gz = '', jpg = '', jpeg = '', png = '',
        mp3 = '', flac = '', wav = '',
        mp4 = '', mkv = '', avi = '',
        iso = '', img = '',
      }
      local function get_file_icon()
        if vim.bo.buftype == 'nofile' or vim.bo.filetype == 'netrw' then
          return ''
        end
        local ext = vim.fn.expand('%:e'):lower()
        return ext_icons[ext] or ''
      end

      -- ── Git branch (uses fugitive when loaded, otherwise raw git) ────────
      local function get_git_branch()
        if vim.fn.exists('*fugitive#head') == 1 then
          local branch = vim.fn.call('fugitive#head', {})
          if branch == '' then return '' end
          return branch .. (vim.bo.modified and '⚡' or '')
        end
        return ''
      end

      -- ── LSP diagnostics summary ──────────────────────────────────────────
      local function get_lsp_status()
        local errors = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
        local warns  = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })
        if errors == 0 and warns == 0 then return '' end
        return string.format('E:%d W:%d', errors, warns)
      end

      require('lualine').setup({
        options = {
          theme                = theme,
          -- Powerline separators (requires Nerd Font / powerline-patched font)
          -- airline_powerline_fonts=1 was set in the old config
          -- Use nr2char since Lua 5.1 has no \uXXXX escape sequences
          section_separators   = { left = vim.fn.nr2char(0xe0b0), right = vim.fn.nr2char(0xe0b2) },
          component_separators = { left = vim.fn.nr2char(0xe0b1), right = vim.fn.nr2char(0xe0b3) },
          globalstatus         = true,  -- keep per-window; notermguicolors
          disabled_filetypes   = { statusline = { 'alpha', 'NvimTree' } },
        },
        sections = {
          lualine_a = { { 'mode', fmt = function(s) return s:sub(1, 1) end } },
          lualine_b = {
            { get_file_icon, padding = { left = 1, right = 0 } },
            { 'filename',    padding = { left = 1, right = 1 }, on_click = function() end },
            { get_git_branch },
          },
          lualine_c = { { get_lsp_status } },
          lualine_x = { 'filetype' },
          lualine_y = { 'progress' },
          lualine_z = { '%p%% %l:%c' },  -- matches g:airline_section_z
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = { 'filename' },
          lualine_c = {},
          lualine_x = {},
          lualine_y = {},
          lualine_z = { 'location' },
        },
      })

      -- ── Color overrides (replaces ApplyAirlineLook highlight block) ──────
      -- Runs on VimEnter + ColorScheme to survive colorscheme reloads
      local function apply_colors()
        local hi = vim.api.nvim_set_hl
        hi(0, 'Normal',       { ctermfg = 231 })
        hi(0, 'Comment',      { ctermfg = 244, italic = true })
        hi(0, 'Constant',     { ctermfg = 5 })
        hi(0, 'Identifier',   { ctermfg = 219 })
        hi(0, 'Statement',    { ctermfg = 218 })
        hi(0, 'PreProc',      { ctermfg = 214 })
        hi(0, 'Type',         { ctermfg = 217 })
        hi(0, 'Special',      { ctermfg = 216 })
        hi(0, 'Underlined',   { ctermfg = 215 })
        hi(0, 'Visual',       { ctermbg = 237 })
        hi(0, 'LineNr',       { ctermfg = 250, ctermbg = 234 })
        hi(0, 'CursorLineNr', { ctermfg = 220, ctermbg = 234, bold = true })
        hi(0, 'Pmenu',        { ctermfg = 231, ctermbg = 236 })
        hi(0, 'PmenuSel',     { ctermfg = 234, ctermbg = 250 })
        hi(0, 'Search',       { ctermfg = 234, ctermbg = 220 })
        hi(0, 'StatusLine',   { ctermfg = 250, ctermbg = 234, bold = true })
        hi(0, 'StatusLineNC', { ctermfg = 250, ctermbg = 234 })
        hi(0, 'TabLineFill',  { ctermfg = 250, ctermbg = 234 })
        hi(0, 'TabLineSel',   { ctermfg = 231, ctermbg = 237 })
      end

      local hg = vim.api.nvim_create_augroup('LualineColorOverrides', { clear = true })
      vim.api.nvim_create_autocmd({ 'VimEnter', 'ColorScheme' }, {
        group    = hg,
        callback = apply_colors,
      })
      apply_colors()
    end,
  },

  -- ── oil.nvim: file explorer ────────────────────────────────────────────────
  {
    'stevearc/oil.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    event = 'VimEnter',
    config = function()
      require('oil').setup({
        default_file_explorer = true,
        columns = { 'icon', 'permissions', 'size', 'mtime' },
        view_options = {
          show_hidden = true,
        },
        win_options = {
          signcolumn = 'yes:2',
        },
        skip_confirm_for_simple_edits = true,
        constrain_cursor = 'editable',
      })

      vim.api.nvim_create_user_command('NERDTreeToggle', function()
        require('oil').toggle_float()
      end, { desc = 'Open oil.nvim (replaces NERDTreeToggle)' })

      vim.keymap.set('n', '-', '<CMD>Oil<CR>', { desc = 'Open parent directory in oil' })
    end,
  },

}
