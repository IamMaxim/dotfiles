local opt = vim.opt

opt.signcolumn = 'yes'
opt.termguicolors = true
opt.showtabline = 2
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.wrap = false
opt.colorcolumn = { '81', '121' }
opt.splitbelow = true
opt.splitright = true
opt.mouse = 'a'
opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true
opt.inccommand = 'split'
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.updatetime = 100
opt.timeoutlen = 300
opt.grepprg = 'rg --vimgrep --smart-case --hidden'
opt.grepformat = '%f:%l:%c:%m'
opt.clipboard = 'unnamedplus'
opt.swapfile = false
opt.backup = false
opt.writebackup = false
opt.undofile = true
opt.expandtab = true
opt.smartindent = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.completeopt = { 'menu', 'menuone', 'noselect' }
opt.pumheight = 12
opt.spelllang = { 'en', 'ru' }

-- Hide command bar by default.
-- Instead, it's shown only in command mode in place of status line.
vim.o.cmdheight = 0

local shadafile = vim.fn.stdpath('state') .. '/shada/main.shada'
vim.fn.mkdir(vim.fs.dirname(shadafile), 'p')
vim.o.shadafile = shadafile
