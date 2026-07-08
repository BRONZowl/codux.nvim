local workspace_git = require("codux.workspace_git")
local workspace_worktree = require("codux.workspace_worktree")

local M = {}

local function empty_dict()
  return vim.empty_dict and vim.empty_dict() or {}
end

local function worktree_directory(runtime, root)
  if not runtime or type(runtime.worktree_config) ~= "function" then
    return nil
  end
  return workspace_worktree.worktree_directory(runtime, root)
end

local function child_path(parent, name)
  return workspace_git.normalize_absolute_path(parent, name)
end

local function directory_entries(path)
  if not vim.fn or type(vim.fn.readdir) ~= "function" then
    return nil
  end
  local ok, entries = pcall(vim.fn.readdir, path)
  if not ok or type(entries) ~= "table" then
    return nil
  end
  table.sort(entries)
  return entries
end

local function is_directory(path)
  if not vim.fn or type(vim.fn.isdirectory) ~= "function" then
    return false
  end
  local ok, result = pcall(vim.fn.isdirectory, path)
  return ok and result == 1
end

local function safe_empty_shell(path)
  if not is_directory(path) then
    return false
  end
  local entries = directory_entries(path)
  if not entries then
    return false
  end
  for _, name in ipairs(entries) do
    local next_path = child_path(path, name)
    if not is_directory(next_path) or not safe_empty_shell(next_path) then
      return false
    end
  end
  return true
end

local function remove_empty_shell(path)
  local entries = directory_entries(path)
  if not entries then
    return false, "failed to read " .. tostring(path)
  end
  for _, name in ipairs(entries) do
    local next_path = child_path(path, name)
    if is_directory(next_path) then
      local ok, err = remove_empty_shell(next_path)
      if not ok then
        return false, err
      end
    else
      return false, "refusing to remove non-empty residue " .. tostring(path)
    end
  end
  if not vim.fn or type(vim.fn.delete) ~= "function" then
    return false, "failed to remove empty residue " .. tostring(path)
  end
  local ok, result = pcall(vim.fn.delete, path, "d")
  if not ok or result ~= 0 then
    return false, "failed to remove empty residue " .. tostring(path)
  end
  return true, nil
end

local function project_empty(project)
  local workspaces = type(project) == "table" and project.workspaces or nil
  return type(workspaces) ~= "table" or next(workspaces) == nil
end

local function inside_worktree_directory(path, directory)
  return type(path) == "string"
    and type(directory) == "string"
    and directory ~= ""
    and workspace_git.starts_with_path(path, directory)
end

local function git_worktree(runtime, path)
  local _, code = runtime.system({ "git", "-C", path, "rev-parse", "--is-inside-work-tree" })
  return code == 0
end

local function child_directories(path)
  local result = {}
  for _, name in ipairs(directory_entries(path) or {}) do
    local next_path = child_path(path, name)
    if is_directory(next_path) then
      table.insert(result, next_path)
    end
  end
  return result
end

local function append_leftover(result, kind, path, cleanable)
  table.insert(result.leftover_directories, {
    kind = kind,
    path = path,
    cleanable = cleanable,
  })
end

local function inspect_leftover_directory(runtime, projects, result, path, depth)
  if git_worktree(runtime, path) then
    local project = projects[path]
    if project_empty(project) then
      append_leftover(result, "orphaned_worktree", path, false)
    end
    return
  end

  local children = depth < 1 and child_directories(path) or {}
  if depth < 1 then
    local has_worktree_child = false
    for _, next_path in ipairs(children) do
      if git_worktree(runtime, next_path) then
        has_worktree_child = true
        break
      end
    end

    if has_worktree_child then
      local before = #result.leftover_directories
      for _, next_path in ipairs(children) do
        inspect_leftover_directory(runtime, projects, result, next_path, depth + 1)
      end
      if #result.leftover_directories > before then
        return
      end
    end
  end

  local cleanable = safe_empty_shell(path)
  if cleanable then
    append_leftover(result, "leftover_directory", path, true)
    return
  end

  if depth < 1 then
    local before = #result.leftover_directories
    for _, next_path in ipairs(children) do
      inspect_leftover_directory(runtime, projects, result, next_path, depth + 1)
    end
    if #result.leftover_directories > before then
      return
    end
  end

  append_leftover(result, "leftover_directory", path, false)
end

function M.inspect(runtime, root)
  local state_data, state_error = runtime:read_state()
  if state_error then
    return nil, state_error
  end

  local directory = worktree_directory(runtime, root)
  local result = {
    worktree_directory = directory,
    empty_project_buckets = {},
    leftover_directories = {},
    count = 0,
  }

  local projects = type(state_data.projects) == "table" and state_data.projects or {}
  for project_root, project in pairs(projects) do
    if project_empty(project) and inside_worktree_directory(project_root, directory) then
      table.insert(result.empty_project_buckets, {
        kind = "empty_project_bucket",
        path = project_root,
        cleanable = true,
      })
    end
  end

  if directory and is_directory(directory) then
    local entries = directory_entries(directory) or {}
    for _, name in ipairs(entries) do
      local path = child_path(directory, name)
      if is_directory(path) then
        inspect_leftover_directory(runtime, projects, result, path, 0)
      end
    end
  end

  result.count = #result.empty_project_buckets + #result.leftover_directories
  return result, nil
end

function M.cleanup(runtime, root)
  local residue, residue_error = M.inspect(runtime, root)
  if residue_error then
    return false, residue_error
  end

  local state_data, state_error = runtime:read_state()
  if state_error then
    return false, state_error
  end

  local removed_buckets = 0
  state_data.projects = type(state_data.projects) == "table" and state_data.projects or empty_dict()
  for _, item in ipairs(residue.empty_project_buckets) do
    state_data.projects[item.path] = nil
    removed_buckets = removed_buckets + 1
  end

  local removed_directories = 0
  local skipped_directories = 0
  for _, item in ipairs(residue.leftover_directories) do
    if item.cleanable then
      local ok, err = remove_empty_shell(item.path)
      if not ok then
        return false, err
      end
      removed_directories = removed_directories + 1
    else
      skipped_directories = skipped_directories + 1
    end
  end

  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    return false, write_error
  end

  return true, {
    removed_buckets = removed_buckets,
    removed_directories = removed_directories,
    skipped_directories = skipped_directories,
  }
end

function M.prune_empty_project_buckets(runtime, state_data, directory)
  if type(state_data) ~= "table" or type(state_data.projects) ~= "table" then
    return 0
  end
  local removed = 0
  for project_root, project in pairs(state_data.projects) do
    if project_empty(project) and (not directory or inside_worktree_directory(project_root, directory)) then
      state_data.projects[project_root] = nil
      removed = removed + 1
    end
  end
  return removed
end

return M
