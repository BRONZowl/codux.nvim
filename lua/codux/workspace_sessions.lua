local M = {}
local providers = require("codux.providers")

function M.apply_meta(runtime, workspace, meta)
  return runtime.store.apply_codex_session_meta(workspace, meta)
end

function M.resolve_resume(runtime, workspace)
  return runtime.store:resolve_workspace_resume_session(workspace)
end

function M.persist_meta(runtime, workspace, meta)
  if type(workspace) ~= "table" or type(meta) ~= "table" then
    return false
  end

  local root = workspace.project_root
  local safe_name = workspace.safe_name
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

  local session_id = runtime.store.normalize_session_id(meta.session_id)
  if not session_id then
    return false
  end
  if meta.cwd ~= root then
    return false
  end

  local captured_at = runtime:timestamp()
  record.agent_provider = record.agent_provider or "codex"
  record.agent_session_id = session_id
  record.agent_session_path = meta.path
  record.agent_session_captured_at = captured_at
  project.updated_at = captured_at

  local write_ok = runtime:write_state(state_data)
  if not write_ok then
    return false
  end

  workspace.agent_provider = record.agent_provider
  workspace.agent_session_id = record.agent_session_id
  workspace.agent_session_path = record.agent_session_path
  workspace.agent_session_captured_at = record.agent_session_captured_at
  if
    runtime.state.workspace == workspace
    or (runtime.state.workspace and runtime.state.workspace.safe_name == safe_name and runtime.state.workspace.project_root == root)
  then
    runtime.state.workspace.agent_provider = record.agent_provider
    runtime.state.workspace.agent_session_id = record.agent_session_id
    runtime.state.workspace.agent_session_path = record.agent_session_path
    runtime.state.workspace.agent_session_captured_at = record.agent_session_captured_at
  end
  if runtime.state.workspace_manager.project_root == root then
    runtime.render_workspace_manager()
  end

  return true
end

function M.schedule_capture(runtime, workspace, min_mtime)
  if type(workspace) ~= "table" then
    return
  end

  local agent_provider = providers.normalize_provider(workspace.agent_provider) or "codex"
  if agent_provider == "grok" then
    return
  end

  min_mtime = tonumber(min_mtime) or 0
  local attempts = 0

  local function capture()
    attempts = attempts + 1
    local meta = nil
    local session_id = runtime.store.normalize_session_id(workspace.agent_session_id)
      or runtime.store.normalize_session_id(workspace.codex_session_id)
    if session_id then
      meta = runtime:codex_session_for_id(session_id)
    end
    if not meta then
      meta = runtime:latest_codex_session_for_cwd(workspace.project_root, min_mtime)
    end
    if meta and runtime:persist_workspace_session_meta(workspace, meta) then
      return
    end
    if attempts < 12 then
      vim.defer_fn(capture, 500)
    end
  end

  vim.defer_fn(capture, 500)
end

return M
