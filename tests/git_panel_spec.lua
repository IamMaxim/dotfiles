package.path = vim.fn.getcwd() .. '/config/nvim/lua/?.lua;' .. vim.fn.getcwd() .. '/config/nvim/lua/?/init.lua;' .. package.path

local git_panel = require('config.git_panel')

local repos = git_panel._parse_status('example', '/tmp/example', {
  'M  staged.lua',
  ' M unstaged.lua',
  'A  added.lua',
  ' D deleted.lua',
  '?? new file.lua',
  'MM both.lua',
  'R  old.lua -> renamed.lua',
})

assert(#repos.staged == 4, vim.inspect(repos.staged))
assert(#repos.unstaged == 4, vim.inspect(repos.unstaged))
assert(repos.staged[1].path == 'staged.lua', vim.inspect(repos.staged[1]))
assert(repos.unstaged[2].path == 'deleted.lua', vim.inspect(repos.unstaged[2]))
assert(repos.unstaged[3].path == 'new file.lua', vim.inspect(repos.unstaged[3]))
assert(repos.staged[4].path == 'renamed.lua', vim.inspect(repos.staged[4]))

local lines, nodes = git_panel._render({
  repos,
  { name = 'clean', path = '/tmp/clean', staged = {}, unstaged = {} },
})

assert(lines[1] == 'example', vim.inspect(lines))
assert(lines[2] == '  Staged', vim.inspect(lines))
assert(lines[3] == '    M staged.lua', vim.inspect(lines))
assert(lines[7] == '  Unstaged', vim.inspect(lines))
assert(lines[#lines] == 'clean (clean)', vim.inspect(lines))
assert(nodes[3].kind == 'file' and nodes[3].section == 'staged', vim.inspect(nodes[3]))
assert(nodes[8].kind == 'file' and nodes[8].section == 'unstaged', vim.inspect(nodes[8]))

assert(
  git_panel._diff_command({ repo = repos, section = 'staged', path = 'staged.lua' })
    == 'DiffviewOpen -C/tmp/example --cached -- staged.lua'
)
assert(
  git_panel._diff_command({ repo = repos, section = 'unstaged', path = 'unstaged.lua' })
    == 'DiffviewOpen -C/tmp/example -- unstaged.lua'
)
