-- monokai-pro "pro" filter palette, used for the fg-only bars below.
local mono = {
  text = '#fcfcfa',
  dim = '#939293',   -- dimmed2: secondary text
  faint = '#727072', -- dimmed3: inactive text
  line = '#5b595c',  -- dimmed4: separators / hairlines
  code = '#221f22',  -- dark1: recessed code-block tint
  red = '#ff6188',
  orange = '#fc9867',
  yellow = '#ffd866',
  green = '#a9dc76',
  blue = '#78dce8',
  purple = '#ab9df2',
}

-- fg-only lualine theme: every section background is transparent so the blur
-- shows through. Only the mode (section a) carries an accent; everything else
-- is dim and gets its color from per-component overrides below, echoing the
-- shell statusline (yellow path, cyan branch, magenta accent, grey metadata).
local function lualine_mode(fg)
  return {
    a = { fg = fg, bg = 'NONE', gui = 'bold' },
    b = { fg = mono.dim, bg = 'NONE' },
    c = { fg = mono.dim, bg = 'NONE' },
  }
end

local transparent_lualine = {
  normal = lualine_mode(mono.blue),
  insert = lualine_mode(mono.green),
  visual = lualine_mode(mono.purple),
  replace = lualine_mode(mono.red),
  command = lualine_mode(mono.yellow),
  inactive = {
    a = { fg = mono.faint, bg = 'NONE' },
    b = { fg = mono.faint, bg = 'NONE' },
    c = { fg = mono.faint, bg = 'NONE' },
  },
}

-- fg-only bufferline ("tabline"): no fills, the active buffer is marked by a
-- bright yellow + underline (like "you are here"), others recede to grey.
-- monokai's own bufferline styling lightens the tab backgrounds, so we override
-- every group here to keep the bar transparent.
local function bufferline_highlights()
  local none = 'NONE'
  local sel = { fg = mono.yellow, bg = none, bold = true, italic = false, sp = mono.yellow, underline = false }
  local vis = { fg = mono.text, bg = none }
  local off = { fg = mono.faint, bg = none }
  local function diag(fg, selected)
    return {
      fg = fg,
      bg = none,
      bold = selected or false,
      sp = selected and mono.yellow or nil,
      underline = false,
      -- underline = selected or
      --     false
    }
  end
  return {
    fill = { bg = none },
    background = off,
    buffer_visible = vis,
    buffer_selected = sel,

    separator = { fg = mono.line, bg = none },
    separator_visible = { fg = mono.line, bg = none },
    separator_selected = { fg = mono.line, bg = none },

    indicator_selected = { fg = mono.yellow, bg = none },
    indicator_visible = { fg = none, bg = none },

    modified = { fg = mono.green, bg = none },
    modified_visible = { fg = mono.green, bg = none },
    modified_selected = { fg = mono.green, bg = none },

    duplicate = { fg = mono.faint, bg = none, italic = true },
    duplicate_visible = { fg = mono.faint, bg = none, italic = true },
    duplicate_selected = { fg = mono.yellow, bg = none, italic = true },

    close_button = off,
    close_button_visible = vis,
    close_button_selected = sel,

    pick = { fg = mono.red, bg = none, bold = true },
    pick_visible = { fg = mono.red, bg = none, bold = true },
    pick_selected = { fg = mono.red, bg = none, bold = true },

    error = diag(mono.red),
    error_visible = diag(mono.red),
    error_selected = diag(mono.red, true),
    error_diagnostic = diag(mono.red),
    error_diagnostic_visible = diag(mono.red),
    error_diagnostic_selected = diag(mono.red, true),
    warning = diag(mono.orange),
    warning_visible = diag(mono.orange),
    warning_selected = diag(mono.orange, true),
    warning_diagnostic = diag(mono.orange),
    warning_diagnostic_visible = diag(mono.orange),
    warning_diagnostic_selected = diag(mono.orange, true),
    info = diag(mono.blue),
    info_visible = diag(mono.blue),
    info_selected = diag(mono.blue, true),
    info_diagnostic = diag(mono.blue),
    info_diagnostic_visible = diag(mono.blue),
    info_diagnostic_selected = diag(mono.blue, true),
    hint = diag(mono.purple),
    hint_visible = diag(mono.purple),
    hint_selected = diag(mono.purple, true),
    hint_diagnostic = diag(mono.purple),
    hint_diagnostic_visible = diag(mono.purple),
    hint_diagnostic_selected = diag(mono.purple, true),

    offset_separator = { fg = mono.line, bg = none },
  }
end

return {
  {
    'loctvl842/monokai-pro.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('monokai-pro').setup({
        transparent_background = true,
        terminal_colors = true,
        filter = 'pro',
        -- Surfaces that should let the blur through. Telescope, floats, and the
        -- completion menu are deliberately omitted so they stay solid/legible.
        -- bufferline is styled fully fg-only below, so it is not listed here.
        background_clear = { 'nvim-tree', 'which-key' },
        -- Let bufferline's own opts.highlights be authoritative; otherwise
        -- monokai re-applies tab backgrounds on module load and clobbers them.
        disabled_plugins = { 'akinsho/bufferline.nvim' },
        override = function()
          return {
            -- Drop the cursorline fill, but keep the current line number bright
            -- for orientation.
            CursorLine = { bg = 'NONE' },
            CursorLineNr = { fg = mono.yellow, bold = true },
            -- Subtle but visible split borders against the blur.
            WinSeparator = { fg = mono.line, bg = 'NONE' },
            -- monokai keeps the statusline bars filled even in transparent
            -- mode; clear the base groups so fg-only lualine sits on the blur.
            -- (The tabline base groups are cleared after load, see below.)
            StatusLine = { bg = 'NONE' },
            StatusLineNC = { bg = 'NONE' },
            WinBar = { bg = 'NONE' },
            WinBarNC = { bg = 'NONE' },
            -- Recessed, low-contrast tint for markdown code blocks so they read
            -- as code without becoming a bright slab over the blur.
            -- RenderMarkdownCode links to ColorColumn by default, so retint that
            -- too as a belt-and-suspenders fallback.
            ColorColumn = { bg = mono.code },
            RenderMarkdownCode = { bg = mono.code },
            RenderMarkdownCodeInline = { bg = mono.code, fg = mono.text },
          }
        end,
      })

      vim.cmd.colorscheme('monokai-pro')

      -- monokai defines the core tabline groups as part of its registry, so a
      -- value passed via `override` is deep-merged (and a leftover link/bg
      -- wins). Replace them outright after the colorscheme is applied, and
      -- re-apply on any future colorscheme change, to keep the tabline on the
      -- blur. The fg is preserved; only the background is dropped.
      local function clear_tabline_backgrounds()
        for _, group in ipairs({ 'TabLine', 'TabLineFill', 'TabLineSel' }) do
          local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
          hl.bg = nil
          hl.ctermbg = nil
          hl.link = nil
          vim.api.nvim_set_hl(0, group, hl)
        end
      end

      clear_tabline_backgrounds()
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('transparent-tabline', { clear = true }),
        callback = clear_tabline_backgrounds,
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
      { '<leader>e', '<cmd>NvimTreeToggle<CR>',   desc = 'File tree' },
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
      { '<leader>bb', '<cmd>BufferLinePick<CR>',      desc = 'Pick buffer' },
    },
    opts = {
      options = {
        mode = 'buffers',
        numbers = 'none',
        always_show_bufferline = true,

        diagnostics = 'nvim_lsp',
        diagnostics_indicator = function(count, level, diagnostics_dict, context)
          return "(" .. count .. ")"
        end,

        separator_style = 'thin',
        indicator = {
          icon = '▎',
          style = 'icon',
        },
        color_icons = true,

        hover = {
          enabled = true,
          delay = 200,
          reveal = { 'close' }
        },

        show_buffer_close_icons = false,
        show_close_icon = false,
        offsets = {
          {
            filetype = 'NvimTree',
            text = 'File Explorer',
            text_align = 'center',
            highlight = 'Directory',
            separator = true,
          },
        },
      },
      highlights = bufferline_highlights(),
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
        theme = transparent_lualine,
        globalstatus = false,
        -- No powerline arrows: they float oddly over a transparent bar.
        section_separators = '',
        component_separators = ' · ',
        disabled_filetypes = {
          winbar = {},
        },
      },
      sections = {
        -- mode wrapped in brackets, magenta-bold accent, echoing the shell line.
        lualine_a = {
          {
            'mode',
            fmt = function(str)
              return '[' .. str .. ']'
            end,
            padding = 0,
          },
        },
        lualine_b = {
          {
            'branch',
            icon = '',
            color = { fg = mono.blue },
            fmt = function(str)
              return '(' .. str .. ')'
            end,
            padding = 0,
          },
          {
            'diagnostics',
            padding = 0,
          },
        },
        lualine_c = {
          {
            'filename',
            path = 1,
            color = { fg = mono.yellow },
            padding = 1,
          },
        },
        lualine_x = {
        },
        lualine_y = {},
        lualine_z = {
          {
            'filetype',
            color = { fg = mono.dim },
            padding = 0,
          },
          {
            'location',
            color = { fg = mono.dim },
            padding = 0,
          },
        },
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
        lualine_x = {},
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
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'nvim-tree/nvim-web-devicons',
    },
    opts = {
      code = {
        width = 'block',
        right_pad = 2,
        sign = false,
      },
    },
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
      { '<leader>xx', '<cmd>Trouble diagnostics toggle<CR>',              desc = 'Diagnostics tree' },
      { '<leader>xX', '<cmd>Trouble diagnostics toggle filter.buf=0<CR>', desc = 'Buffer diagnostics tree' },
      { '<leader>xq', '<cmd>Trouble qflist toggle<CR>',                   desc = 'Quickfix tree' },
      { '<leader>xl', '<cmd>Trouble loclist toggle<CR>',                  desc = 'Location list tree' },
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
