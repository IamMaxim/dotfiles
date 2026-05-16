return {
  {
    'loctvl842/monokai-pro.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('monokai-pro').setup({
        transparent_background = false,
        terminal_colors = true,
        filter = 'pro',
      })

      vim.cmd.colorscheme('monokai-pro')
      vim.api.nvim_set_hl(0, 'ColorColumn', {
        bg = '#2a2f2f',
      })
    end,
  },
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = {
      preset = 'modern',
      icons = {
        mappings = false,
      },
      spec = {
        { '<leader>b', group = 'buffers' },
        { '<leader>c', group = 'code' },
        { '<leader>f', group = 'find' },
        { '<leader>g', group = 'git' },
        { '<leader>l', group = 'lsp' },
        { '<leader>m', group = 'markdown' },
        { '<leader>r', group = 'rust' },
        { '<leader>u', group = 'ui' },
        { '<leader>x', group = 'diagnostics' },
      },
    },
  },
  {
    'nvim-tree/nvim-tree.lua',
    version = '*',
    dependencies = {
      'nvim-tree/nvim-web-devicons',
    },
    keys = {
      { '<leader>e', '<cmd>NvimTreeToggle<CR>', desc = 'File tree' },
      { '<leader>E', '<cmd>NvimTreeFindFile<CR>', desc = 'Reveal file tree' },
    },
    config = function()
      require('nvim-tree').setup({
        hijack_cursor = true,
        sync_root_with_cwd = true,
        update_focused_file = {
          enable = true,
          update_root = false,
        },
        view = {
          width = 32,
        },
        renderer = {
          group_empty = true,
        },
        filters = {
          dotfiles = false,
        },
      })
    end,
  },
  {
    'akinsho/bufferline.nvim',
    lazy = false,
    version = '*',
    dependencies = {
      'nvim-tree/nvim-web-devicons',
    },
    keys = {
      { '<leader>bn', '<cmd>BufferLineCycleNext<CR>', desc = 'Next buffer' },
      { '<leader>bp', '<cmd>BufferLineCyclePrev<CR>', desc = 'Previous buffer' },
      { '<leader>bc', '<cmd>BufferLinePickClose<CR>', desc = 'Close buffer' },
      { '<leader>bb', '<cmd>BufferLinePick<CR>', desc = 'Pick buffer' },
    },
    opts = {
      options = {
        mode = 'buffers',
        always_show_bufferline = true,
        diagnostics = 'nvim_lsp',
        separator_style = 'slant',
        show_buffer_close_icons = false,
        show_close_icon = false,
        offsets = {
          {
            filetype = 'NvimTree',
            text = 'File Explorer',
            highlight = 'Directory',
            separator = true,
          },
        },
      },
    },
  },
  {
    'nvim-lualine/lualine.nvim',
    lazy = false,
    dependencies = {
      'nvim-tree/nvim-web-devicons',
    },
    opts = {
      options = {
        theme = 'molokai',
        globalstatus = false,
        section_separators = { left = '', right = '' },
        component_separators = { left = '', right = '' },
        disabled_filetypes = {
          winbar = {},
        },
      },
      sections = {
        lualine_a = { 'mode' },
        lualine_b = { 'branch', 'diff', 'diagnostics' },
        lualine_c = {
          {
            'filename',
            path = 1,
          },
        },
        lualine_x = { 'encoding', 'fileformat', 'filetype' },
        lualine_y = { 'progress' },
        lualine_z = { 'location' },
      },
      inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = {
          {
            'filename',
            path = 1,
          },
        },
        lualine_x = { 'location' },
        lualine_y = {},
        lualine_z = {},
      },
      extensions = { 'nvim-tree', 'quickfix' },
    },
  },
  {
    'godlygeek/tabular',
    ft = { 'markdown' },
  },
  {
    'preservim/vim-markdown',
    ft = { 'markdown' },
    dependencies = {
      'godlygeek/tabular',
    },
    init = function()
      vim.g.vim_markdown_folding_disabled = 1
      vim.g.vim_markdown_no_default_key_mappings = 1
      vim.g.vim_markdown_conceal = 0
      vim.g.vim_markdown_conceal_code_blocks = 0
    end,
  },
  {
    'nvim-telescope/telescope.nvim',
    cmd = 'Telescope',
    keys = {
      { '<leader>ff', desc = 'Find files' },
      { '<leader>fg', desc = 'Live grep' },
      { '<leader>fb', desc = 'Buffers' },
      { '<leader>fh', desc = 'Help tags' },
      { '<leader>fk', desc = 'Keymaps' },
      { '<leader>fd', desc = 'Diagnostics' },
      { '<leader>fs', desc = 'Grep word under cursor' },
      { '<leader>fr', desc = 'Resume picker' },
    },
    dependencies = {
      'nvim-lua/plenary.nvim',
    },
    config = function()
      local telescope = require('telescope')
      telescope.setup({
        defaults = {
          path_display = { 'smart' },
          vimgrep_arguments = {
            'rg',
            '--color=never',
            '--no-heading',
            '--with-filename',
            '--line-number',
            '--column',
            '--smart-case',
          },
          mappings = {
            i = {
              ['<C-j>'] = 'move_selection_next',
              ['<C-k>'] = 'move_selection_previous',
            },
          },
        },
      })

      local builtin = require('telescope.builtin')
      local pickers = require('telescope.pickers')
      local finders = require('telescope.finders')
      local conf = require('telescope.config').values
      local make_entry = require('telescope.make_entry')

      -- Live fuzzy grep with real-time matching
      local live_fuzzy_grep = function(opts)
        opts = opts or {}

        local function to_fuzzy_regex(str)
          if str == '' then
            return nil
          end
          -- Convert "abc" -> "a.*b.*c" for fuzzy matching
          local result = ''
          for i = 1, #str do
            result = result .. str:sub(i, i)
            if i < #str then
              result = result .. '.*'
            end
          end
          return result
        end

        pickers
          .new(opts, {
            prompt_title = 'Live Fuzzy Grep',
            finder = finders.new_job(function(prompt)
              local pattern = to_fuzzy_regex(prompt)
              if not pattern then
                return nil
              end
              local args = vim.deepcopy(conf.vimgrep_arguments)
              table.insert(args, pattern)
              return args
            end, make_entry.gen_from_vimgrep(opts), opts.max_results),
            previewer = conf.grep_previewer(opts),
            sorter = conf.generic_sorter(opts),
          })
          :find()
      end

      vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find files' })
      vim.keymap.set('n', '<leader>fg', live_fuzzy_grep, { desc = 'Live grep (fuzzy)' })
      vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Buffers' })
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Help tags' })
      vim.keymap.set('n', '<leader>fk', builtin.keymaps, { desc = 'Keymaps' })
      vim.keymap.set('n', '<leader>fd', builtin.diagnostics, { desc = 'Diagnostics' })
      vim.keymap.set('n', '<leader>fs', builtin.grep_string, { desc = 'Grep word under cursor' })
      vim.keymap.set('n', '<leader>fr', builtin.resume, { desc = 'Resume picker' })
    end,
  },
  {
    'folke/trouble.nvim',
    cmd = 'Trouble',
    keys = {
      { '<leader>xx', '<cmd>Trouble diagnostics toggle<CR>', desc = 'Diagnostics tree' },
      { '<leader>xX', '<cmd>Trouble diagnostics toggle filter.buf=0<CR>', desc = 'Buffer diagnostics tree' },
      { '<leader>xq', '<cmd>Trouble qflist toggle<CR>', desc = 'Quickfix tree' },
      { '<leader>xl', '<cmd>Trouble loclist toggle<CR>', desc = 'Location list tree' },
    },
    opts = {},
  },
  {
    'sindrets/diffview.nvim',
    cmd = {
      'DiffviewOpen',
      'DiffviewClose',
      'DiffviewToggleFiles',
      'DiffviewFocusFiles',
      'DiffviewRefresh',
    },
    keys = {
      {
        '<leader>gs',
        function()
          require('config.git_panel').toggle()
        end,
        desc = 'Git panel',
      },
      {
        '<leader>gS',
        function()
          require('config.git_panel').refresh()
        end,
        desc = 'Refresh git panel',
      },
    },
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons',
    },
    config = function()
      require('diffview').setup({
        file_panel = {
          listing_style = 'tree',
          win_config = {
            position = 'right',
            width = 42,
          },
        },
      })
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    event = { 'BufReadPost', 'BufNewFile' },
    opts = {
      ensure_installed = { 'lua', 'vim', 'vimdoc', 'rust', 'toml', 'query', 'markdown', 'markdown_inline' },
      highlight = {
        enable = true,
      },
      indent = {
        enable = true,
      },
    },
  },
  {
    'mrcjkb/rustaceanvim',
    version = '^6',
    lazy = false,
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
    },
  },
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',
      'hrsh7th/cmp-nvim-lsp',
    },
    config = function()
      local capabilities = require('cmp_nvim_lsp').default_capabilities()
      vim.lsp.config('lua_ls', {
        capabilities = capabilities,
        settings = {
          Lua = {
            diagnostics = {
              globals = { 'vim' },
            },
            workspace = {
              checkThirdParty = false,
            },
            telemetry = {
              enable = false,
            },
          },
        },
      })

      vim.lsp.config('marksman', {
        capabilities = capabilities,
      })

      vim.lsp.enable('lua_ls')
      vim.lsp.enable('marksman')

      require('mason').setup()
      require('mason-lspconfig').setup({
        ensure_installed = { 'lua_ls', 'marksman' },
      })

      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(args)
          local buf = args.buf
          local buffer_map = function(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
          end

          buffer_map('n', 'gd', vim.lsp.buf.definition, 'Go to definition')
          buffer_map('n', 'gr', vim.lsp.buf.references, 'References')
          buffer_map('n', 'K', vim.lsp.buf.hover, 'Hover docs')
          buffer_map('n', '<leader>rn', vim.lsp.buf.rename, 'Rename symbol')
          buffer_map('n', '<leader>ca', vim.lsp.buf.code_action, 'Code action')
          buffer_map('n', '<leader>lf', function()
            vim.lsp.buf.format({ async = true })
          end, 'Format buffer')
        end,
      })
    end,
  },
  {
    'hrsh7th/nvim-cmp',
    event = 'InsertEnter',
    dependencies = {
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-nvim-lsp',
    },
    config = function()
      local cmp = require('cmp')
      cmp.setup({
        mapping = cmp.mapping.preset.insert({
          ['<C-n>'] = cmp.mapping.select_next_item(),
          ['<C-p>'] = cmp.mapping.select_prev_item(),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'path' },
        }, {
          { name = 'buffer' },
        }),
      })
    end,
  },
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    opts = {
      formatters_by_ft = {
        lua = { 'stylua' },
        rust = { 'rustfmt' },
      },
      format_on_save = function(bufnr)
        local ft = vim.bo[bufnr].filetype
        if ft == 'c' or ft == 'cpp' then
          return nil
        end

        return {
          timeout_ms = 1000,
          lsp_format = 'fallback',
        }
      end,
    },
    config = function(_, opts)
      require('conform').setup(opts)
      vim.keymap.set('n', '<leader>lf', function()
        require('conform').format({ async = true, lsp_format = 'fallback' })
      end, { desc = 'Format buffer' })
    end,
  },
  {
    'mfussenegger/nvim-lint',
    event = { 'BufReadPost', 'BufNewFile', 'InsertLeave', 'TextChanged' },
    config = function()
      local lint = require('lint')
      local markdown_linter = function()
        if vim.fn.executable('markdownlint-cli2') == 1 then
          return 'markdownlint-cli2'
        end

        if vim.fn.executable('markdownlint') == 1 then
          return 'markdownlint'
        end

        return nil
      end

      local lint_markdown = function()
        if vim.bo.filetype ~= 'markdown' then
          return
        end

        local linter = markdown_linter()
        if linter then
          lint.try_lint(linter)
        end
      end

      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave', 'TextChanged' }, {
        group = vim.api.nvim_create_augroup('markdown-lint', { clear = true }),
        pattern = { '*.md', '*.markdown', '*.mdown', '*.mkdn' },
        callback = lint_markdown,
      })
    end,
  },
  {
    'numToStr/Comment.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
    opts = {},
  },
  {
    'kylechui/nvim-surround',
    event = 'VeryLazy',
    opts = {},
  },
}
