-- lua/plugins/editing.lua
-- Lua-native replacements for heavy VimL plugins:
--   flash.nvim      → replaces vim-easymotion
--   indent-blankline → replaces indentLine
--   telescope.nvim  → replaces fzf + fzf.vim
--   alpha.nvim      → replaces vim-startify
--   nvim-dap        → replaces nvim-gdb + vim-vebugger

return {

  -- ── flash.nvim: replaces vim-easymotion (10x faster, Lua-native) ──────────
  {
    'folke/flash.nvim',
    event = 'VimEnter',
    keys = {
      {
        '<A-f>',
        mode = { 'n', 'x', 'o' },
        function() require('flash').jump() end,
        desc = 'Flash jump',
      },
      {
        's',
        mode = 'o',
        function() require('flash').treesitter() end,
        desc = 'Flash treesitter',
      },
    },
    config = function()
      require('flash').setup({
        labels = 'asdfghjklqwertyuiopzxcvbnm',
        search = {
          mode = 'search',
        },
        label = {
          uppercase = false,
        },
      })
    end,
  },

  -- ── indent-blankline.nvim: replaces indentLine (Lua-native, no per-line redraw)
  {
    'lukas-reineke/indent-blankline.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
      require('ibl').setup({
        indent = {
          char = '│',
          highlight = { 'LineNr' },
        },
        scope = {
          enabled = false,
        },
        exclude = {
          filetypes = {
            'startify', 'help', 'git', 'markdown', 'netrw', 'oil',
            'lspinfo', 'checkhealth', 'man', 'gitcommit', 'terminal',
          },
        },
      })
    end,
  },

  -- ── telescope.nvim: replaces fzf + fzf.vim (Lua-native, LSP-integrated) ──
  {
    'nvim-telescope/telescope.nvim',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
      },
    },
    cmd = 'Telescope',
    config = function()
      local telescope = require('telescope')
      local actions = require('telescope.actions')

      telescope.setup({
        defaults = {
          mappings = {
            i = {
              ['<C-j>'] = actions.move_selection_next,
              ['<C-k>'] = actions.move_selection_previous,
              ['<Esc>'] = actions.close,
            },
          },
          file_ignore_patterns = { 'node_modules', '.git/', 'build/', 'dist/' },
          path_display = { 'smart' },
        },
        pickers = {
          find_files = {
            hidden = true,
          },
          live_grep = {
            additional_args = function()
              return { '--hidden' }
            end,
          },
          buffers = {
            sort_lastused = true,
          },
        },
        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = 'smart_case',
          },
        },
      })

      telescope.load_extension('fzf')

      -- Shim legacy fzf.vim commands
      vim.api.nvim_create_user_command('Files', function()
        telescope.builtin.find_files()
      end, {})
      vim.api.nvim_create_user_command('History', function()
        telescope.builtin.oldfiles()
      end, {})
      vim.api.nvim_create_user_command('BLines', function()
        telescope.builtin.current_buffer_fuzzy_find()
      end, {})
      vim.api.nvim_create_user_command('Lines', function()
        telescope.builtin.grep_string()
      end, {})
    end,
  },

  -- ── alpha.nvim: replaces vim-startify (Lua-native, instant startup) ────────
  {
    'goolord/alpha-nvim',
    event = 'VimEnter',
    dependencies = {
      'nvim-tree/nvim-web-devicons',
      'ozthemagician/alpha-cowsays-nvim',
    },
    config = function()
      local alpha = require('alpha')
      local startify = require('alpha.themes.startify')
      local cow = require('alpha-cowsays-nvim')

      startify.section.header.val = cow.cowsays()

      startify.section.top_buttons.val = {
        startify.button('e', '󰝒  New file', '<cmd>ene<CR>'),
        startify.button('r', '󱪉  Recent files', '<cmd>Telescope oldfiles<CR>'),
        startify.button('f', '󰈞  Find files', '<cmd>Telescope find_files<CR>'),
        startify.button('g', '󰺪  Live grep', '<cmd>Telescope live_grep<CR>'),
        startify.button('q', '󰈆  Quit', '<cmd>qa<CR>'),
      }

      startify.section.footer = { type = 'padding', val = 1 }

      startify.config.opts.autostart = true

      alpha.setup(startify.config)

      vim.api.nvim_create_autocmd('VimEnter', {
        callback = function()
          local has_stdin = vim.api.nvim_get_vvar('stdin') ~= ''
          if vim.fn.argc() == 0 and not has_stdin then
            require('alpha').start(false)
          end
        end,
      })

      vim.api.nvim_create_autocmd('User', {
        pattern = 'AlphaReady',
        callback = function()
          vim.opt_local.showtabline = 0
          vim.opt.laststatus = 0
        end,
      })
    end,
  },

  -- ── nvim-dap: modern debugger (replaces nvim-gdb + vim-vebugger) ──────────
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'rcarriga/nvim-dap-ui',
      'theHamsta/nvim-dap-virtual-text',
    },
    keys = {
      { '<F5>',     function() require('dap').continue() end,           desc = 'Continue debugging' },
      { '<F6>',     function() require('dap').toggle_breakpoint() end,  desc = 'Toggle breakpoint' },
      { '<F7>',     function() require('dap').step_into() end,          desc = 'Step into' },
      { '<F8>',     function() require('dap').step_over() end,          desc = 'Step over' },
      { '<C-F8>',   function() require('dap').toggle_breakpoint() end,  desc = 'Toggle breakpoint' },
      { '<F10>',    function() require('dap').step_out() end,           desc = 'Step out' },
    },
    config = function()
      local dap = require('dap')
      local dapui = require('dapui')

      -- C/C++ via GDB
      dap.adapters.cpp = {
        type = 'executable',
        command = 'gdb',
        args = { '-i', 'dap' },
      }
      dap.configurations.cpp = {
        {
          name = 'Launch',
          type = 'cpp',
          request = 'launch',
          program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
          end,
          cwd = '${workspaceFolder}',
          stopAtEntry = true,
        },
      }
      dap.configurations.c = dap.configurations.cpp

      -- Python via debugpy
      dap.adapters.python = {
        type = 'executable',
        command = vim.fn.stdpath('data') .. '/mason/packages/debugpy/venv/bin/python',
        args = { '-m', 'debugpy.adapter' },
      }
      dap.configurations.python = {
        {
          type = 'python',
          request = 'launch',
          name = 'Launch file',
          program = '${file}',
          pythonPath = function()
            return vim.fn.exepath('python3')
          end,
        },
      }

      -- DAP UI setup
      dapui.setup()
      dap.listeners.after.event_initialized['dapui_config'] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated['dapui_config'] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited['dapui_config'] = function()
        dapui.close()
      end

      require('nvim-dap-virtual-text').setup()
    end,
  },

}
