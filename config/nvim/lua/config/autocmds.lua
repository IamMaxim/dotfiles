local group = vim.api.nvim_create_augroup('maxim-nvim-config', { clear = true })

vim.api.nvim_create_autocmd('TextYankPost', {
  group = group,
  desc = 'Highlight yanked text',
  callback = function()
    vim.highlight.on_yank()
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = { 'markdown' },
  desc = 'Markdown writing tweaks',
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
    -- Honor treesitter @nospell captures so code blocks/inline code aren't spellchecked
    vim.opt_local.spelloptions = 'noplainbuffer'
  end,
})
