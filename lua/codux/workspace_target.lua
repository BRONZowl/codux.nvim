local filetypes = require("codux.filetypes")

local M = {}

function M.sync_allowed(runtime, event, current_filetype)
  if type(runtime.state.workspace) ~= "table" or type(runtime.state.workspace.safe_name) ~= "string" then
    return false
  end

  local filetype = current_filetype()
  if filetypes.is_internal(filetype) then
    return false
  end

  if event == "CursorMoved" and not runtime.is_explorer_filetype(filetype) then
    return false
  end

  return true
end

function M.sync(runtime, event, current_filetype)
  if not runtime:target_sync_allowed(event, current_filetype) then
    return false
  end

  local workspace = runtime.state.workspace
  local root = workspace.project_root
  local safe_name = workspace.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false
  end

  local context = runtime:target_context()
  local path = context.path
  if type(path) ~= "string" or path == "" or runtime.virtual_path(path) then
    return false
  end

  local target_type = context.target and context.target.type or (vim.fn.isdirectory(path) == 1 and "directory" or "file")
  local branch = context.branch or ""
  path, target_type = runtime.normalize_workspace_target(path, target_type, root)
  local signature = runtime.workspace_target_signature(path, target_type, branch)
  if signature == runtime.state.workspace_target_signature then
    return true
  end

  local state_data, state_error = runtime:read_state()
  if state_error then
    return false
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  local record = type(workspaces) == "table" and workspaces[safe_name] or nil
  if type(record) ~= "table" then
    return false
  end

  record.target_path = path
  record.target_type = target_type
  record.git_branch = branch
  record.last_target_at = runtime:timestamp()
  project.updated_at = record.last_target_at

  local write_ok = runtime:write_state(state_data)
  if not write_ok then
    return false
  end

  workspace.target_path = path
  workspace.target_type = target_type
  workspace.git_branch = branch
  runtime.state.workspace_target_signature = signature

  if runtime.state.workspace_manager_project_root == root then
    runtime.render_workspace_manager()
  end

  return true
end

function M.schedule(runtime, event, sync_fn)
  if runtime.state.workspace_target_update_pending then
    return
  end

  runtime.state.workspace_target_update_pending = true
  vim.defer_fn(function()
    runtime.state.workspace_target_update_pending = false
    sync_fn(event)
  end, 150)
end

function M.attach(runtime, workspace, schedule_sync)
  if type(workspace) ~= "table" then
    return false
  end

  local attached = runtime:workspace_from_state(workspace, workspace)
  if type(attached.safe_name) ~= "string" or attached.safe_name == "" then
    return false
  end
  if type(attached.project_root) ~= "string" or attached.project_root == "" then
    return false
  end

  runtime.state.workspace = attached
  runtime.state.workspace_target_signature =
    runtime.workspace_target_signature(attached.target_path, attached.target_type, attached.git_branch)
  schedule_sync("attach")
  return true
end

return M
