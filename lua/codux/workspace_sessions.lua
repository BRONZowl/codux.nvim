local M = {}
local providers = require("codux.providers")

function M.apply_meta(runtime, workspace, meta)
  return runtime.store.apply_codex_session_meta(workspace, meta)
end

function M.resolve_resume(runtime, workspace)
  return runtime.store:resolve_workspace_resume_session(workspace)
end

function M.codex_home(runtime)
  return runtime.store:codex_home()
end

function M.session_files(runtime)
  return runtime.store:codex_session_files()
end

function M.read_meta(runtime, path)
  return runtime.store:read_codex_session_meta(path)
end

function M.session_for_id(runtime, session_id)
  return runtime.store:codex_session_for_id(session_id)
end

function M.latest_for_cwd(runtime, cwd, min_mtime)
  return runtime.store:latest_codex_session_for_cwd(cwd, min_mtime)
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

  record.codex_session_id = session_id
  record.codex_session_path = meta.path
  record.codex_session_captured_at = runtime:timestamp()
  record.agent_provider = "codex"
  record.agent_session_id = session_id
  record.agent_session_path = meta.path
  record.agent_session_captured_at = record.codex_session_captured_at
  project.updated_at = record.codex_session_captured_at

  local write_ok = runtime:write_state(state_data)
  if not write_ok then
    return false
  end

  workspace.codex_session_id = record.codex_session_id
  workspace.codex_session_path = record.codex_session_path
  workspace.codex_session_captured_at = record.codex_session_captured_at
  workspace.agent_provider = "codex"
  workspace.agent_session_id = record.agent_session_id
  workspace.agent_session_path = record.agent_session_path
  workspace.agent_session_captured_at = record.agent_session_captured_at
  if
    runtime.state.workspace == workspace
    or (runtime.state.workspace and runtime.state.workspace.safe_name == safe_name and runtime.state.workspace.project_root == root)
  then
    runtime.state.workspace.codex_session_id = record.codex_session_id
    runtime.state.workspace.codex_session_path = record.codex_session_path
    runtime.state.workspace.codex_session_captured_at = record.codex_session_captured_at
    runtime.state.workspace.agent_provider = "codex"
    runtime.state.workspace.agent_session_id = record.agent_session_id
    runtime.state.workspace.agent_session_path = record.agent_session_path
    runtime.state.workspace.agent_session_captured_at = record.agent_session_captured_at
  end
  if runtime.state.workspace_manager_project_root == root then
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
    workspace.agent_session_id = type(workspace.agent_session_id) == "string" and workspace.agent_session_id ~= ""
        and workspace.agent_session_id
      or providers.generate_session_id()
    workspace.agent_session_captured_at = runtime:timestamp()
    local root = workspace.project_root
    local safe_name = workspace.safe_name
    local state_data = runtime:read_state()
    local project = type(state_data) == "table" and type(state_data.projects) == "table" and state_data.projects[root] or nil
    local record = type(project) == "table" and type(project.workspaces) == "table" and project.workspaces[safe_name] or nil
    if type(record) == "table" then
      record.agent_provider = "grok"
      record.agent_session_id = workspace.agent_session_id
      record.agent_session_path = workspace.agent_session_path
      record.agent_session_captured_at = workspace.agent_session_captured_at
      project.updated_at = workspace.agent_session_captured_at
      runtime:write_state(state_data)
    end
    return
  end

  min_mtime = tonumber(min_mtime) or 0
  local attempts = 0

  local function capture()
    attempts = attempts + 1
    local meta = nil
    local session_id = runtime.store.normalize_session_id(workspace.codex_session_id)
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
