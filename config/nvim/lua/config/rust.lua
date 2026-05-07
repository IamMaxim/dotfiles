local launch_cwd = vim.uv.cwd()

local function repo_root(filename)
  return vim.fs.root(filename, { '.git' }) or vim.uv.cwd()
end

local function split_env_list(value)
  local items = {}
  if not value or value == '' then
    return items
  end

  for item in string.gmatch(value, '([^:]+)') do
    table.insert(items, item)
  end

  return items
end

local function to_linked_project(item)
  local path = item
  if not vim.startswith(path, '/') then
    path = vim.fs.joinpath(launch_cwd, path)
  end

  if not vim.endswith(path, 'Cargo.toml') then
    path = vim.fs.joinpath(path, 'Cargo.toml')
  end

  return vim.fs.normalize(path)
end

local function env_number(name)
  local value = tonumber(vim.env[name])
  if value and value > 0 then
    return value
  end

  return nil
end

vim.g.rustaceanvim = function()
  local root = repo_root(vim.api.nvim_buf_get_name(0))
  local linked_projects = {}
  for _, item in ipairs(split_env_list(vim.env.RA_LINKED_PROJECTS)) do
    table.insert(linked_projects, to_linked_project(item))
  end

  local ok, cmp_nvim_lsp = pcall(require, 'cmp_nvim_lsp')
  local capabilities = ok and cmp_nvim_lsp.default_capabilities() or nil

  local rust_analyzer = {
    checkOnSave = false,
    check = {
      workspace = false,
      allTargets = false,
    },
    cargo = {
      allTargets = false,
      targetDir = true,
      features = {},
    },
    procMacro = {
      enable = true,
    },
    cachePriming = {
      enable = true,
      numThreads = env_number('RA_CACHE_PRIMING_THREADS'),
    },
    numThreads = env_number('RA_NUM_THREADS'),
    files = {
      exclude = {
        'target',
        'target-ra',
        '.git',
        'node_modules',
        'tmp',
        'generated',
      },
    },
    diagnostics = {
      experimental = { enable = false },
      styleLints = { enable = false },
    },
  }

  if #linked_projects > 0 then
    rust_analyzer.linkedProjects = linked_projects
  end

  return {
    server = {
      capabilities = capabilities,
      root_dir = function(filename)
        return repo_root(filename)
      end,
      standalone = false,
      default_settings = {
        ['rust-analyzer'] = rust_analyzer,
      },
    },
  }
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('rust-large-workspace', { clear = true }),
  pattern = 'rust',
  desc = 'Rust large workspace keymaps',
  callback = function()
    vim.keymap.set('n', '<leader>rc', function()
      vim.cmd.RustLsp({ 'flyCheck', 'run' })
    end, { buffer = true, desc = 'Run rust-analyzer flyCheck' })

    vim.keymap.set('n', '<leader>rx', function()
      vim.cmd.RustLsp({ 'flyCheck', 'cancel' })
    end, { buffer = true, desc = 'Cancel rust-analyzer flyCheck' })
  end,
})
