local map = vim.keymap.set

local function markdown_lint()
  if vim.bo.filetype ~= 'markdown' then
    return
  end

  local lint = require('lint')
  if vim.fn.executable('markdownlint-cli2') == 1 then
    lint.try_lint('markdownlint-cli2')
    return
  end

  if vim.fn.executable('markdownlint') == 1 then
    lint.try_lint('markdownlint')
  end
end

local function open_action_menu()
  local buf = vim.api.nvim_get_current_buf()
  local has_lsp = #vim.lsp.get_clients({ bufnr = buf }) > 0
  local is_markdown = vim.bo[buf].filetype == 'markdown'

  local actions = {}
  if has_lsp then
    table.insert(actions, {
      label = 'LSP: code action',
      run = function()
        vim.lsp.buf.code_action()
      end,
    })
    table.insert(actions, {
      label = 'LSP: format buffer',
      run = function()
        vim.lsp.buf.format({ async = true })
      end,
    })
    table.insert(actions, {
      label = 'LSP: rename symbol',
      run = function()
        vim.lsp.buf.rename()
      end,
    })
  end

  table.insert(actions, {
    label = 'UI: file tree',
    run = function()
      vim.cmd.NvimTreeToggle()
    end,
  })
  table.insert(actions, {
    label = 'UI: reveal file tree',
    run = function()
      vim.cmd.NvimTreeFindFile()
    end,
  })
  table.insert(actions, {
    label = 'Config: reload',
    run = function()
      vim.cmd.source(vim.env.MYVIMRC)
    end,
  })

  if is_markdown then
    table.insert(actions, {
      label = 'Markdown: format table',
      run = function()
        vim.cmd.TableFormat()
      end,
    })
    table.insert(actions, {
      label = 'Markdown: lint',
      run = markdown_lint,
    })
  end

  vim.ui.select(actions, {
    prompt = 'Actions',
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      choice.run()
    end
  end)
end

map('n', '<Esc>', '<cmd>nohlsearch<CR>')
map('n', '<leader>q', '<cmd>q<CR>', { desc = 'Quit window' })
map('n', '<leader>w', '<cmd>w<CR>', { desc = 'Write buffer' })
map('n', '<leader>h', function()
  require('which-key').show({ global = true })
end, { desc = 'Which-key help' })
map('n', '<leader>?', function()
  require('which-key').show({ global = true })
end, { desc = 'Which-key help' })
map('n', '<leader>ud', function()
  vim.cmd.edit(vim.fn.stdpath('config') .. '/NVIM_SETUP.md')
end, { desc = 'Setup documentation' })
map('n', '<leader>sv', '<cmd>source $MYVIMRC<CR>', { desc = 'Reload config' })
map('n', '<leader>mf', '<cmd>TableFormat<CR>', { desc = 'Format table' })
map('n', '<leader>ml', markdown_lint, { desc = 'Lint markdown' })
map({ 'n', 'v' }, '<M-CR>', open_action_menu, { desc = 'Action menu' })
map({ 'n', 'v' }, '<M-Enter>', open_action_menu, { desc = 'Action menu' })
