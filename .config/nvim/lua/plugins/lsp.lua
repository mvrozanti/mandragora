-- lua/plugins/lsp.lua
-- mason: LSP installer
-- mason-lspconfig: auto-installs pyright + clangd
-- nvim-lspconfig: provides default server definitions (cmd, filetypes, root_markers)
-- nvim-cmp: completion engine
-- nvim-jdtls: Java LSP (special — never use lspconfig.jdtls.setup())
--
-- Uses the Neovim 0.11 native API (vim.lsp.config + vim.lsp.enable) instead of
-- the deprecated require('lspconfig').server.setup() pattern.

return {

  -- ── Mason: LSP server installer ────────────────────────────────────────────
  {
    'williamboman/mason.nvim',
    build  = ':MasonUpdate',
    config = function()
      require('mason').setup({
        ui = { border = 'rounded' },
      })
    end,
  },

  -- ── Mason-lspconfig: auto-install bridge ───────────────────────────────────
  {
    'williamboman/mason-lspconfig.nvim',
    dependencies = { 'williamboman/mason.nvim' },
    config = function()
      require('mason-lspconfig').setup({
        ensure_installed = {
          'pyright',  -- Python
          'clangd',   -- C/C++
          -- jdtls intentionally omitted: managed by nvim-jdtls, not lspconfig
        },
        automatic_installation = true,
      })
    end,
  },

  -- ── nvim-lspconfig: provides default server definitions ────────────────────
  -- We keep this for its default cmd/filetypes/root_markers per server.
  -- Configuration is done via the Neovim 0.11 native API below, NOT via
  -- require('lspconfig').server.setup() (that pattern is deprecated).
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      'williamboman/mason-lspconfig.nvim',
      'hrsh7th/cmp-nvim-lsp',
    },
    config = function()

      -- ── Diagnostic display ───────────────────────────────────────────────
      vim.diagnostic.config({
        virtual_text     = { prefix = '●' },
        signs            = true,
        underline        = true,
        update_in_insert = false,
        severity_sort    = true,
        float            = {
          focusable = true,
          style     = 'minimal',
          border    = 'rounded',
          source    = 'always',
          header    = '',
          prefix    = '',
        },
      })

      -- Sign column icons
      local signs = { Error = ' ', Warn = ' ', Hint = ' ', Info = ' ' }
      for type, icon in pairs(signs) do
        local hl = 'DiagnosticSign' .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = '' })
      end

      -- ── Global LSP defaults (applies to ALL servers) ─────────────────────
      -- Sets capabilities once instead of per-server
      vim.lsp.config('*', {
        capabilities = require('cmp_nvim_lsp').default_capabilities(),
        debounce_text_changes = 150,
      })

      -- ── LspAttach: keymaps wired once, apply to every LSP buffer ─────────
      vim.api.nvim_create_autocmd('LspAttach', {
        group    = vim.api.nvim_create_augroup('LspKeymaps', { clear = true }),
        callback = function(args)
          local bufnr = args.buf
          local opts  = { buffer = bufnr, silent = true }
          vim.keymap.set('n', 'gd',         vim.lsp.buf.definition,                              vim.tbl_extend('force', opts, { desc = 'Go to definition' }))
          vim.keymap.set('n', 'gD',         vim.lsp.buf.declaration,                             vim.tbl_extend('force', opts, { desc = 'Go to declaration' }))
          vim.keymap.set('n', 'gr',         vim.lsp.buf.references,                              vim.tbl_extend('force', opts, { desc = 'References' }))
          vim.keymap.set('n', 'gi',         vim.lsp.buf.implementation,                          vim.tbl_extend('force', opts, { desc = 'Implementation' }))
          vim.keymap.set('n', 'K',          vim.lsp.buf.hover,                                   vim.tbl_extend('force', opts, { desc = 'Hover docs' }))
          vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename,                                  vim.tbl_extend('force', opts, { desc = 'Rename' }))
          vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action,                             vim.tbl_extend('force', opts, { desc = 'Code action' }))
          vim.keymap.set('n', '<leader>f',  function() vim.lsp.buf.format({ async = true }) end, vim.tbl_extend('force', opts, { desc = 'Format' }))
          vim.keymap.set('n', '[d',         vim.diagnostic.goto_prev,                            vim.tbl_extend('force', opts, { desc = 'Prev diagnostic' }))
          vim.keymap.set('n', ']d',         vim.diagnostic.goto_next,                            vim.tbl_extend('force', opts, { desc = 'Next diagnostic' }))
          vim.keymap.set('n', '<leader>e',  vim.diagnostic.open_float,                           vim.tbl_extend('force', opts, { desc = 'Open diagnostic float' }))
          vim.keymap.set('n', '<leader>q',  vim.diagnostic.setloclist,                           vim.tbl_extend('force', opts, { desc = 'Diagnostics to loclist' }))
        end,
      })

      -- ── pyright: Python ──────────────────────────────────────────────────
      -- lspconfig provides default cmd/filetypes/root_markers; we add settings.
      vim.lsp.config('pyright', {
        settings = {
          python = {
            analysis = {
              autoSearchPaths        = true,
              useLibraryCodeForTypes = true,
              diagnosticMode         = 'openFilesOnly',
              typeCheckingMode       = 'basic',
            },
          },
        },
      })
      vim.lsp.enable('pyright')

      -- ── clangd: C/C++ ────────────────────────────────────────────────────
      -- Override cmd to add our flags; lspconfig provides filetypes/root_markers.
      -- Coexists with vim-clang-refactor (clangd: diagnostics/completion/hover;
      -- clang-refactor: refactoring commands).
      vim.lsp.config('clangd', {
        cmd = {
          'clangd',
          '--background-index',
          '--clang-tidy',
          '--completion-style=detailed',
          '--header-insertion=iwyu',
        },
      })
      vim.lsp.enable('clangd')

    end,
  },

  -- ── nvim-cmp: completion engine ────────────────────────────────────────────
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-nvim-lsp-signature-help',
    },
    event = 'InsertEnter',
    config = function()
      local cmp = require('cmp')

      -- Override completeopt for nvim-cmp (was 'longest,menuone' in options.lua)
      vim.opt.completeopt = { 'menu', 'menuone', 'noselect' }

      cmp.setup({
        snippet = {
          -- Neovim 0.10+ built-in snippet engine; no extra plugin needed
          expand = function(args)
            vim.snippet.expand(args.body)
          end,
        },

        mapping = cmp.mapping.preset.insert({
          -- Tab/S-Tab: replicate map.vim pumvisible behavior through cmp
          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item()
            else fallback() end
          end, { 'i', 's' }),

          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item()
            else fallback() end
          end, { 'i', 's' }),

          ['<C-b>']     = cmp.mapping.scroll_docs(-4),
          ['<C-f>']     = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>']     = cmp.mapping.abort(),
          -- CR confirms only when an item is explicitly selected
          ['<CR>']      = cmp.mapping.confirm({ select = false }),
        }),

        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'nvim_lsp_signature_help' },
          { name = 'path' },
        }, {
          { name = 'buffer', keyword_length = 3 },
        }),

        formatting = {
          format = function(entry, item)
            local source_labels = {
              nvim_lsp                = '[LSP]',
              nvim_lsp_signature_help = '[Sig]',
              buffer                  = '[Buf]',
              path                    = '[Path]',
            }
            item.menu = source_labels[entry.source.name] or ''
            return item
          end,
        },
      })
    end,
  },

  -- ── nvim-jdtls: Java LSP ───────────────────────────────────────────────────
  -- IMPORTANT: Never call lspconfig.jdtls.setup() — nvim-jdtls manages the
  -- client lifecycle via start_or_attach().
  -- Post-install: run :MasonInstall jdtls
  {
    'mfussenegger/nvim-jdtls',
    ft = { 'java' },
    config = function()
      local jdtls_path = vim.fn.stdpath('data') .. '/mason/packages/jdtls'
      local launcher   = vim.fn.glob(jdtls_path .. '/plugins/org.eclipse.equinox.launcher_*.jar')
      local config_dir = jdtls_path .. '/config_linux'

      -- Per-project workspace directory
      local workspace = vim.fn.stdpath('data') .. '/jdtls-workspace/'
        .. vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')

      if launcher == '' then
        vim.notify(
          'jdtls not installed. Run :MasonInstall jdtls',
          vim.log.levels.WARN,
          { title = 'nvim-jdtls' }
        )
        return
      end

      local config = {
        cmd = {
          'java',
          '-Declipse.application=org.eclipse.jdt.ls.core.id1',
          '-Dosgi.bundles.defaultStartLevel=4',
          '-Declipse.product=org.eclipse.jdt.ls.core.product',
          '-Dlog.protocol=true',
          '-Dlog.level=ALL',
          '-Xmx1g',
          '--add-modules=ALL-SYSTEM',
          '--add-opens', 'java.base/java.util=ALL-UNNAMED',
          '--add-opens', 'java.base/java.lang=ALL-UNNAMED',
          '-jar', launcher,
          '-configuration', config_dir,
          '-data', workspace,
        },

        root_dir = require('jdtls.setup').find_root({ 'pom.xml', 'build.gradle', '.git' }),

        settings = {
          java = {
            configuration      = { updateBuildConfiguration = 'interactive' },
            eclipse            = { downloadSources = true },
            maven              = { downloadSources = true },
            implementationsCodeLens = { enabled = true },
            referencesCodeLens      = { enabled = true },
          },
        },

        on_attach = function(_, bufnr)
          require('jdtls').setup_dap({ hotcodereplace = 'auto' })
          require('jdtls.setup').add_commands()

          local opts = { buffer = bufnr, silent = true }
          vim.keymap.set('n', 'gd',         vim.lsp.buf.definition,  vim.tbl_extend('force', opts, { desc = 'Go to definition' }))
          vim.keymap.set('n', 'K',          vim.lsp.buf.hover,       vim.tbl_extend('force', opts, { desc = 'Hover docs' }))
          vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename,      vim.tbl_extend('force', opts, { desc = 'Rename' }))
          vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, vim.tbl_extend('force', opts, { desc = 'Code action' }))
          -- Java-specific refactoring
          vim.keymap.set('n', '<leader>oi', function() require('jdtls').organize_imports() end,   vim.tbl_extend('force', opts, { desc = 'Organize imports' }))
          vim.keymap.set('n', '<leader>ev', function() require('jdtls').extract_variable() end,  vim.tbl_extend('force', opts, { desc = 'Extract variable' }))
          vim.keymap.set('v', '<leader>em', function() require('jdtls').extract_method(true) end, vim.tbl_extend('force', opts, { desc = 'Extract method' }))
        end,

        capabilities = require('cmp_nvim_lsp').default_capabilities(),
      }

      -- Attach jdtls to every Java buffer that opens
      local ag = vim.api.nvim_create_augroup('JdtlsAttach', { clear = true })
      vim.api.nvim_create_autocmd('FileType', {
        group    = ag,
        pattern  = 'java',
        callback = function()
          require('jdtls').start_or_attach(config)
        end,
      })
    end,
  },

}
