local path_util = require("codux.path_util")
local workspace_status = require("codux.workspace_status")
local workspace_lifecycle = require("codux.workspace_lifecycle")

local M = {}

local inactive_like_status = workspace_status.inactive_like_status

local function record_matches_entry(record, entry, safe_name, root)
  entry = type(entry) == "table" and entry or {}
  record = type(record) == "table" and record or {}
  if record.workspace_kind ~= "worktree" then
    return false
  end

  local entry_safe_name = entry.safe_name or entry.name
  if type(entry_safe_name) == "string" and entry_safe_name ~= "" then
    local record_safe_name = record.safe_name or safe_name
    if record_safe_name ~= entry_safe_name then
      return false
    end
  end

  local entry_branch = entry.worktree_branch
  if type(entry_branch) == "string" and entry_branch ~= "" then
    return record.worktree_branch == entry_branch
  end

  local entry_root = entry.project_root or entry.worktree_path
  return type(entry_root) == "string" and entry_root ~= "" and (root == entry_root or record.project_root == entry_root)
end

local function find_worktree_record(state_data, entry)
  local projects = type(state_data.projects) == "table" and state_data.projects or {}
  local preferred_root = type(entry) == "table" and (entry.project_root or entry.worktree_path) or nil
  local preferred_safe_name = type(entry) == "table" and entry.safe_name or nil

  if type(preferred_root) == "string" and preferred_root ~= "" and type(preferred_safe_name) == "string" then
    local project = type(projects[preferred_root]) == "table" and projects[preferred_root] or nil
    local workspaces = type(project) == "table" and type(project.workspaces) == "table" and project.workspaces or nil
    local record = type(workspaces) == "table" and workspaces[preferred_safe_name] or nil
    if record_matches_entry(record, entry, preferred_safe_name, preferred_root) then
      return project, record, preferred_root, preferred_safe_name
    end
  end

  local found = nil
  for root, project in pairs(projects) do
    local workspaces = type(project) == "table" and project.workspaces or nil
    if type(workspaces) == "table" then
      for safe_name, record in pairs(workspaces) do
        if record_matches_entry(record, entry, safe_name, root) then
          if found then
            return nil, nil, nil, nil, "workspace record is ambiguous"
          end
          found = {
            project = project,
            record = record,
            root = root,
            safe_name = safe_name,
          }
        end
      end
    end
  end

  if found then
    return found.project, found.record, found.root, found.safe_name, nil
  end
  return nil, nil, nil, nil, "workspace not found"
end

local function entry_from_record(record, safe_name, root, fallback)
  fallback = type(fallback) == "table" and fallback or {}
  local updated = vim.deepcopy(fallback)
  updated.name = record.name or fallback.name or safe_name
  updated.safe_name = record.safe_name or safe_name
  updated.project_root = record.project_root or root
  updated.target_path = record.target_path
  updated.target_type = record.target_type
  updated.git_branch = record.git_branch
  updated.workspace_kind = record.workspace_kind
  updated.git_common_dir = record.git_common_dir
  updated.worktree_path = record.worktree_path
  updated.worktree_branch = record.worktree_branch
  updated.worktree_base = record.worktree_base
  updated.worktree_base_commit = record.worktree_base_commit
  updated.nvim_server = record.nvim_server or fallback.nvim_server
  updated.window_name = record.tmux_window or record.window_name or fallback.window_name
  updated.tmux_window = record.tmux_window or record.window_name or fallback.tmux_window
  updated.tmux_target = record.tmux_target or fallback.tmux_target
  updated.status = fallback.status or record.status
  updated.agent_status = record.agent_status or fallback.agent_status
  updated.agent_mode = record.agent_mode or fallback.agent_mode
  updated.last_reconciled_at = record.last_reconciled_at
  return updated
end

local function update_active_workspace(runtime, old_root, safe_name, record)
  local workspace = runtime.state.workspace
  if
    type(workspace) ~= "table"
    or workspace.safe_name ~= safe_name
    or not (workspace.project_root == old_root or workspace.worktree_branch == record.worktree_branch)
  then
    return
  end

  workspace.project_root = record.project_root
  workspace.worktree_path = record.worktree_path
  workspace.target_path = record.target_path
  workspace.git_branch = record.git_branch
  workspace.worktree_branch = record.worktree_branch
  workspace.nvim_server = record.nvim_server or workspace.nvim_server
  workspace.last_reconciled_at = record.last_reconciled_at
end

local function reconcile_record(runtime, state_data, project, record, root, safe_name, entry, opts)
  opts = type(opts) == "table" and opts or {}
  local current_entry = entry_from_record(record, safe_name, root, entry)
  local current_path = runtime:current_worktree_path(current_entry, {
    worktree_lists = opts.worktree_lists,
  })
  if type(current_path) ~= "string" or current_path == "" then
    return current_entry, false, nil
  end

  current_path = path_util.strip_trailing_slashes(current_path)
  local old_worktree_path = path_util.strip_trailing_slashes(record.worktree_path or record.project_root or root)
  local old_root = root
  if current_path == old_worktree_path and record.project_root == current_path and record.worktree_path == current_path then
    return current_entry, false, nil
  end

  project.workspaces[safe_name] = nil
  if next(project.workspaces) == nil and vim.empty_dict then
    project.workspaces = vim.empty_dict()
  end

  record.project_root = current_path
  record.worktree_path = current_path
  record.target_path = workspace_lifecycle.retarget_path_after_worktree_move(record.target_path, old_worktree_path, current_path)
  record.last_reconciled_at = runtime:timestamp()
  if inactive_like_status(record.status) then
    record.nvim_server = nil
  end

  local next_project = runtime:project_state(state_data, current_path)
  next_project.workspaces[safe_name] = record
  project.updated_at = record.last_reconciled_at
  next_project.updated_at = record.last_reconciled_at

  return entry_from_record(record, safe_name, current_path, entry), true, nil, {
    old_root = old_root,
    safe_name = safe_name,
    record = record,
  }
end

function M.reconcile_moved_worktree(runtime, entry, opts)
  opts = type(opts) == "table" and opts or {}
  entry = type(entry) == "table" and entry or {}
  if entry.workspace_kind ~= "worktree" then
    return entry, false, nil
  end

  local state_data, state_error = runtime:read_state()
  if state_error then
    return entry, false, state_error
  end

  local project, record, root, safe_name, find_error = find_worktree_record(state_data, entry)
  if type(record) ~= "table" then
    return entry, false, opts.ignore_missing == true and nil or find_error
  end

  local updated, changed, reconcile_error, active_update = reconcile_record(runtime, state_data, project, record, root, safe_name, entry, {
    worktree_lists = {},
  })
  if reconcile_error then
    return entry, false, reconcile_error
  end
  if not changed then
    return updated, false, nil
  end

  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    return entry, false, write_error
  end
  update_active_workspace(runtime, active_update.old_root, active_update.safe_name, active_update.record)
  return updated, true, nil
end

local function project_reconcile_entries(runtime, state_data, root)
  local current_common_dir = runtime:git_common_dir(root)
  local entries = {}
  local projects = type(state_data.projects) == "table" and state_data.projects or {}
  for project_root, project in pairs(projects) do
    local workspaces = type(project) == "table" and project.workspaces or nil
    if type(workspaces) == "table" then
      for safe_name, record in pairs(workspaces) do
        if
          type(record) == "table"
          and record.workspace_kind == "worktree"
          and type(record.mission_id) == "string"
          and record.mission_id ~= ""
          and (
            record.project_root == root
            or project_root == root
            or (current_common_dir ~= nil and record.git_common_dir == current_common_dir)
          )
        then
          table.insert(entries, {
            project = project,
            record = record,
            root = project_root,
            safe_name = safe_name,
            entry = entry_from_record(record, safe_name, project_root, {}),
          })
        end
      end
    end
  end
  return entries
end

function M.reconcile_moved_worktrees_for_project(runtime, root, opts)
  opts = type(opts) == "table" and opts or {}
  root = root or runtime:project_root()
  local state_data, state_error = runtime:read_state()
  if state_error then
    return 0, state_error
  end

  local changed = 0
  local active_updates = {}
  local worktree_lists = {}
  for _, item in ipairs(project_reconcile_entries(runtime, state_data, root)) do
    local _, did_change, error_message, active_update = reconcile_record(
      runtime,
      state_data,
      item.project,
      item.record,
      item.root,
      item.safe_name,
      item.entry,
      { worktree_lists = worktree_lists }
    )
    if error_message and opts.ignore_missing == false then
      return changed, error_message
    end
    if did_change then
      changed = changed + 1
      table.insert(active_updates, active_update)
    end
  end

  if changed == 0 then
    return 0, nil
  end

  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    return changed, write_error
  end
  for _, active_update in ipairs(active_updates) do
    update_active_workspace(runtime, active_update.old_root, active_update.safe_name, active_update.record)
  end
  return changed, nil
end

return M
