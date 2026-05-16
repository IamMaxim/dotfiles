local root = vim.fn.getcwd()
package.path = root .. '/config/nvim/lua/?.lua;' .. root .. '/config/nvim/lua/?/init.lua;' .. package.path

require('lazy').load({ plugins = { 'diffview.nvim' } })

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')

local function run(args)
  local result = vim.system(args, { cwd = tmp, text = true }):wait()
  assert(result.code == 0, table.concat(args, ' ') .. '\n' .. (result.stderr or ''))
end

run({ 'git', 'init' })
vim.fn.writefile({ 'one' }, vim.fs.joinpath(tmp, 'one.txt'))
vim.fn.writefile({ 'two' }, vim.fs.joinpath(tmp, 'two.txt'))
run({ 'git', 'add', 'one.txt', 'two.txt' })
run({
  'git',
  '-c',
  'commit.gpgsign=false',
  '-c',
  'user.email=test@example.invalid',
  '-c',
  'user.name=Test',
  'commit',
  '-m',
  'initial',
})
vim.fn.writefile({ 'one changed' }, vim.fs.joinpath(tmp, 'one.txt'))
vim.fn.writefile({ 'two changed' }, vim.fs.joinpath(tmp, 'two.txt'))

vim.cmd.cd(vim.fn.fnameescape(tmp))
local panel = require('config.git_panel')
panel.refresh()
local panel_tab = vim.api.nvim_get_current_tabpage()

vim.api.nvim_win_set_cursor(0, { 3, 0 })
panel.open_diff()
assert(#vim.api.nvim_list_tabpages() == 2, #vim.api.nvim_list_tabpages())

vim.api.nvim_set_current_tabpage(panel_tab)
vim.api.nvim_win_set_cursor(0, { 4, 0 })
panel.open_diff()
assert(#vim.api.nvim_list_tabpages() == 2, #vim.api.nvim_list_tabpages())
