local M = {}

local state = {
  buf = nil,
  win = nil,
  nodes = {},
  diff_tab = nil,
}

local function basename(path)
  return vim.fs.basename(path:gsub('/$', ''))
end

local function shell_error(result)
  return type(result) == 'table' and result.code or vim.v.shell_error
end

local function git_lines(repo, args)
  local cmd = { 'git', '-C', repo }
  vim.list_extend(cmd, args)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return {}
  end

  return vim.split(vim.trim(result.stdout or ''), '\n', { plain = true, trimempty = true })
end

local function is_git_repo(path)
  local result = vim.system({ 'git', '-C', path, 'rev-parse', '--is-inside-work-tree' }, { text = true }):wait()
  return shell_error(result) == 0 and vim.trim(result.stdout or '') == 'true'
end

local function repo_root(path)
  local result = vim.system({ 'git', '-C', path, 'rev-parse', '--show-toplevel' }, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  return vim.fs.normalize(vim.trim(result.stdout or ''))
end

local function parse_path(raw)
  local path = raw
  local renamed = raw:match('^.- %-> (.+)$')
  if renamed then
    path = renamed
  end

  return path
end

function M._parse_status(name, path, lines)
  local repo = {
    name = name,
    path = path,
    staged = {},
    unstaged = {},
  }

  for _, line in ipairs(lines) do
    if #line >= 4 then
      local index_status = line:sub(1, 1)
      local worktree_status = line:sub(2, 2)
      local file_path = parse_path(line:sub(4))

      if index_status ~= ' ' and index_status ~= '?' and index_status ~= '!' then
        table.insert(repo.staged, {
          kind = 'file',
          repo = repo,
          section = 'staged',
          status = index_status,
          path = file_path,
        })
      end

      if worktree_status ~= ' ' and worktree_status ~= '!' then
        table.insert(repo.unstaged, {
          kind = 'file',
          repo = repo,
          section = 'unstaged',
          status = index_status == '?' and '??' or worktree_status,
          path = file_path,
        })
      end
    end
  end

  return repo
end

local function repo_status(path)
  return M._parse_status(basename(path), path, git_lines(path, { 'status', '--porcelain=v1' }))
end

local function discover_repos(cwd)
  local found = {}
  local seen = {}
  local root = repo_root(cwd)

  if root then
    table.insert(found, root)
    seen[root] = true
  end

  for name, type_ in vim.fs.dir(cwd) do
    if type_ == 'directory' then
      local candidate = vim.fs.joinpath(cwd, name)
      if is_git_repo(candidate) then
        local child_root = repo_root(candidate)
        if child_root and not seen[child_root] then
          table.insert(found, child_root)
          seen[child_root] = true
        end
      end
    end
  end

  table.sort(found)
  return found
end

local function has_changes(repo)
  return #repo.staged > 0 or #repo.unstaged > 0
end

function M._render(repos)
  local lines = {}
  local nodes = {}

  for _, repo in ipairs(repos) do
    local repo_label = repo.name
    if not has_changes(repo) then
      repo_label = repo_label .. ' (clean)'
    end

    table.insert(lines, repo_label)
    table.insert(nodes, { kind = 'repo', repo = repo })

    if #repo.staged > 0 then
      table.insert(lines, '  Staged')
      table.insert(nodes, { kind = 'section', repo = repo, section = 'staged' })
      for _, item in ipairs(repo.staged) do
        table.insert(lines, ('    %s %s'):format(item.status, item.path))
        table.insert(nodes, item)
      end
    end

    if #repo.unstaged > 0 then
      table.insert(lines, '  Unstaged')
      table.insert(nodes, { kind = 'section', repo = repo, section = 'unstaged' })
      for _, item in ipairs(repo.unstaged) do
        table.insert(lines, ('    %s %s'):format(item.status, item.path))
        table.insert(nodes, item)
      end
    end
  end

  if #lines == 0 then
    lines = { 'No git repositories under cwd' }
    nodes = { { kind = 'message' } }
  end

  return lines, nodes
end

local function collect()
  local repos = {}
  for _, path in ipairs(discover_repos(vim.uv.cwd())) do
    table.insert(repos, repo_status(path))
  end
  return repos
end

local function ensure_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end

  vim.cmd('botright vertical 42new')
  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_get_current_buf()
  vim.bo[state.buf].buftype = 'nofile'
  vim.bo[state.buf].bufhidden = 'wipe'
  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].filetype = 'gitpanel'
  vim.bo[state.buf].swapfile = false
  vim.wo[state.win].winfixwidth = true
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.api.nvim_buf_set_name(state.buf, 'Git Panel ' .. state.buf)

  vim.keymap.set('n', 'q', M.close, { buffer = state.buf, desc = 'Close git panel' })
  vim.keymap.set('n', 'r', M.refresh, { buffer = state.buf, desc = 'Refresh git panel' })
  vim.keymap.set('n', '<CR>', M.open_diff, { buffer = state.buf, desc = 'Open git diff' })
  vim.keymap.set('n', '<2-LeftMouse>', M.open_diff, { buffer = state.buf, desc = 'Open git diff' })
end

function M.refresh()
  ensure_window()
  local lines, nodes = M._render(collect())
  state.nodes = nodes

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

function M.close()
  local buf = state.buf
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.nodes = {}
end

local function close_diffview()
  if not state.diff_tab or not vim.api.nvim_tabpage_is_valid(state.diff_tab) then
    state.diff_tab = nil
    return
  end

  local current = vim.api.nvim_get_current_tabpage()
  vim.api.nvim_set_current_tabpage(state.diff_tab)
  pcall(vim.cmd.DiffviewClose)
  if vim.api.nvim_tabpage_is_valid(current) then
    vim.api.nvim_set_current_tabpage(current)
  end
  state.diff_tab = nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
    return
  end

  M.refresh()
end

function M._diff_command(node)
  local escaped_repo = vim.fn.fnameescape(node.repo.path)
  local escaped_path = vim.fn.fnameescape(node.path)
  if node.section == 'staged' then
    return ('DiffviewOpen -C%s --cached -- %s'):format(escaped_repo, escaped_path)
  end

  return ('DiffviewOpen -C%s -- %s'):format(escaped_repo, escaped_path)
end

function M.open_diff()
  local node = state.nodes[vim.api.nvim_win_get_cursor(0)[1]]
  if not node or node.kind ~= 'file' then
    return
  end

  close_diffview()
  vim.cmd(M._diff_command(node))
  state.diff_tab = vim.api.nvim_get_current_tabpage()
end

return M
