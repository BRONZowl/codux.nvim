local workspace_status = require("codux.workspace_status")

local M = {}

local inactive_like_status = workspace_status.inactive_like_status

function M.sync_activity(runtime, agent_status)
  if agent_status ~= "working" and agent_status ~= "question" and agent_status ~= "idle" then
    return false
  end
  if type(runtime.state.workspace) ~= "table" then
    return false
  end

  local root = runtime.state.workspace.project_root
  local safe_name = runtime.state.workspace.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false
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

  local session = runtime:current_tmux_session()
  local window_name = record.tmux_window or record.window_name or runtime.state.workspace.window_name or safe_name
  local window_id = session and runtime:tmux_window_id(session, window_name) or nil
  local dashboard_status = runtime:dashboard_workspace_status(record, window_id)
  if inactive_like_status(dashboard_status) then
    if
      record.agent_status == "idle"
      and record.status == dashboard_status
      and record.agent_mode == nil
      and record.tmux_window == window_name
    then
      runtime.state.workspace.agent_status = "idle"
      runtime.state.workspace.status = dashboard_status
      runtime.state.workspace.agent_mode = nil
      return true
    end

    record.agent_status = "idle"
    record.status = dashboard_status
    record.agent_mode = nil
    record.tmux_window = window_name
    record.tmux_target = runtime.tmux_target(session, window_name) or record.tmux_target
    record.last_activity_at = runtime:timestamp()
    project.updated_at = record.last_activity_at

    local write_ok = runtime:write_state(state_data)
    if not write_ok then
      return false
    end

    runtime.state.workspace.agent_status = "idle"
    runtime.state.workspace.status = dashboard_status
    runtime.state.workspace.agent_mode = nil
    if runtime.state.workspace_manager_project_root == root then
      runtime.render_workspace_manager()
    end

    return true
  end

  local workspace_status = agent_status == "working" and "active"
    or agent_status == "question" and "question"
    or "idle"
  if record.agent_status == agent_status and record.status == workspace_status then
    runtime.state.workspace.agent_status = agent_status
    runtime.state.workspace.status = workspace_status
    return true
  end

  record.agent_status = agent_status
  record.status = workspace_status
  record.last_activity_at = runtime:timestamp()
  project.updated_at = record.last_activity_at

  local write_ok = runtime:write_state(state_data)
  if not write_ok then
    return false
  end

  runtime.state.workspace.agent_status = agent_status
  runtime.state.workspace.status = record.status
  if runtime.state.workspace_manager_project_root == root then
    runtime.render_workspace_manager()
  end

  return true
end

function M.sync_mode(runtime, mode)
  mode = runtime:normalize_agent_mode(mode)
  if type(runtime.state.workspace) ~= "table" then
    return false
  end

  local root = runtime.state.workspace.project_root
  local safe_name = runtime.state.workspace.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false
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

  if record.agent_mode == mode then
    runtime.state.workspace.agent_mode = mode
    return true
  end

  record.agent_mode = mode
  project.updated_at = runtime:timestamp()

  local write_ok = runtime:write_state(state_data)
  if not write_ok then
    return false
  end

  runtime.state.workspace.agent_mode = mode
  if runtime.state.workspace_manager_project_root == root then
    runtime.render_workspace_manager()
  end

  return true
end

return M
