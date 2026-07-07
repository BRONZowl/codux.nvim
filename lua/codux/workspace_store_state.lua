local text_util = require("codux.text")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

local function empty_dict()
  return vim.empty_dict and vim.empty_dict() or {}
end

local function inactive_like_status(status)
  return status == "inactive" or status == "missing"
end

function M.empty_state()
  return {
    version = 2,
    projects = empty_dict(),
  }
end

function M.normalize_session_id(value)
  if type(value) ~= "string" then
    return nil
  end

  value = trim(value)
  if value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
    return value
  end

  return nil
end

function M.normalize_codex_mode(value)
  if value == "execute" or value == "plan" then
    return value
  end

  return nil
end

function M.normalize_record(store, record, safe_name, root)
  if type(record) ~= "table" then
    return nil
  end

  safe_name = type(record.safe_name) == "string" and record.safe_name ~= "" and record.safe_name or safe_name
  local name = type(record.name) == "string" and record.name ~= "" and record.name or safe_name
  local project_root = type(record.project_root) == "string" and record.project_root ~= "" and record.project_root or root
  local window_name = store.workspace_window_name(safe_name)
  local status = record.status
  if status ~= "active" and status ~= "question" and status ~= "idle" and status ~= "inactive" and status ~= "missing" then
    status = "inactive"
  end
  local codex_status = record.codex_status == "working" and "working"
    or record.codex_status == "question" and "question"
    or "idle"
  local codex_mode = not inactive_like_status(status) and M.normalize_codex_mode(record.codex_mode) or nil

  return {
    name = name,
    safe_name = safe_name,
    project_root = project_root,
    target_path = record.target_path,
    target_type = record.target_type,
    git_branch = record.git_branch or "",
    workspace_kind = record.workspace_kind,
    git_common_dir = record.git_common_dir,
    worktree_path = record.worktree_path,
    worktree_branch = record.worktree_branch,
    worktree_base = record.worktree_base,
    worktree_base_commit = record.worktree_base_commit,
    mission_id = record.mission_id,
    mission_name = record.mission_name,
    mission_role = record.mission_role,
    mission_objective = record.mission_objective,
    mission_focus_packet = record.mission_focus_packet,
    tmux_window = window_name,
    tmux_target = record.tmux_target,
    nvim_server = record.nvim_server,
    custom_instruction = record.custom_instruction,
    resolved_instruction = record.resolved_instruction,
    permission_profile = record.permission_profile or "default",
    codex_session_id = M.normalize_session_id(record.codex_session_id),
    codex_session_path = record.codex_session_path,
    codex_session_captured_at = record.codex_session_captured_at,
    status = status,
    codex_status = codex_status,
    codex_mode = codex_mode,
    created_at = record.created_at,
    last_opened_at = record.last_opened_at,
    last_activity_at = record.last_activity_at,
    last_target_at = record.last_target_at,
    last_reconciled_at = record.last_reconciled_at,
  }
end

function M.normalize_state(store, state_data)
  if type(state_data) ~= "table" then
    return store:empty_state()
  end

  if type(state_data.projects) ~= "table" and type(state_data.workspaces) == "table" then
    local migrated = store:empty_state()
    for safe_name, record in pairs(state_data.workspaces) do
      if type(record) == "table" and type(record.project_root) == "string" and record.project_root ~= "" then
        local project = migrated.projects[record.project_root]
        if type(project) ~= "table" then
          project = {
            project_root = record.project_root,
            workspaces = empty_dict(),
          }
          migrated.projects[record.project_root] = project
        end
        project.workspaces[safe_name] = store:normalize_record(record, safe_name, record.project_root)
      end
    end
    return migrated
  end

  state_data.version = 2
  state_data.templates = nil
  state_data.hidden_templates = nil

  if type(state_data.projects) ~= "table" then
    state_data.projects = empty_dict()
  end

  for root, project in pairs(state_data.projects) do
    if type(project) == "table" then
      project.project_root = type(project.project_root) == "string" and project.project_root ~= "" and project.project_root or root
      if type(project.workspaces) ~= "table" then
        project.workspaces = empty_dict()
      else
        for safe_name, record in pairs(project.workspaces) do
          project.workspaces[safe_name] = store:normalize_record(record, safe_name, project.project_root)
        end
      end
    else
      state_data.projects[root] = {
        project_root = root,
        workspaces = empty_dict(),
      }
    end
  end

  return state_data
end

function M.project_state(_, state_data, root)
  state_data.projects[root] = type(state_data.projects[root]) == "table" and state_data.projects[root] or empty_dict()
  local project = state_data.projects[root]
  project.project_root = root
  project.workspaces = type(project.workspaces) == "table" and project.workspaces or empty_dict()
  return project
end

function M.workspace_from_state(record, fallback)
  record = type(record) == "table" and record or {}
  fallback = type(fallback) == "table" and fallback or {}
  local status = record.status or fallback.status or "inactive"
  local codex_mode = not inactive_like_status(status)
      and (M.normalize_codex_mode(record.codex_mode) or M.normalize_codex_mode(fallback.codex_mode))
    or nil

  return {
    name = record.name or fallback.name,
    safe_name = record.safe_name or fallback.safe_name,
    project_root = record.project_root or fallback.project_root,
    target_path = record.target_path or fallback.target_path,
    target_type = record.target_type or fallback.target_type,
    git_branch = record.git_branch or fallback.git_branch or "",
    workspace_kind = record.workspace_kind or fallback.workspace_kind,
    git_common_dir = record.git_common_dir or fallback.git_common_dir,
    worktree_path = record.worktree_path or fallback.worktree_path,
    worktree_branch = record.worktree_branch or fallback.worktree_branch,
    worktree_base = record.worktree_base or fallback.worktree_base,
    worktree_base_commit = record.worktree_base_commit or fallback.worktree_base_commit,
    mission_id = record.mission_id or fallback.mission_id,
    mission_name = record.mission_name or fallback.mission_name,
    mission_role = record.mission_role or fallback.mission_role,
    mission_objective = record.mission_objective or fallback.mission_objective,
    mission_focus_packet = record.mission_focus_packet or fallback.mission_focus_packet,
    window_name = record.tmux_window or record.window_name or fallback.window_name,
    tmux_target = record.tmux_target or fallback.tmux_target,
    nvim_server = record.nvim_server or fallback.nvim_server,
    custom_instruction = record.custom_instruction or fallback.custom_instruction,
    resolved_instruction = record.resolved_instruction or fallback.resolved_instruction,
    initial_mode = record.initial_mode or fallback.initial_mode,
    permission_profile = record.permission_profile or fallback.permission_profile or "default",
    codex_session_id = M.normalize_session_id(record.codex_session_id) or M.normalize_session_id(fallback.codex_session_id),
    codex_session_path = record.codex_session_path or fallback.codex_session_path,
    codex_session_captured_at = record.codex_session_captured_at or fallback.codex_session_captured_at,
    codex_status = record.codex_status or fallback.codex_status or "idle",
    status = status,
    codex_mode = codex_mode,
    created_at = record.created_at or fallback.created_at,
    last_activity_at = record.last_activity_at or fallback.last_activity_at,
    last_target_at = record.last_target_at or fallback.last_target_at,
  }
end

function M.timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function M.state_record(_, workspace, existing)
  existing = type(existing) == "table" and existing or {}
  local now = M.timestamp()
  local status = workspace.status or existing.status or "idle"
  local codex_mode = nil
  if not inactive_like_status(status) then
    codex_mode = M.normalize_codex_mode(workspace.codex_mode) or M.normalize_codex_mode(existing.codex_mode)
  end

  return {
    name = workspace.name,
    safe_name = workspace.safe_name,
    project_root = workspace.project_root,
    target_path = workspace.target_path,
    target_type = workspace.target_type,
    git_branch = workspace.git_branch or "",
    workspace_kind = workspace.workspace_kind,
    git_common_dir = workspace.git_common_dir,
    worktree_path = workspace.worktree_path,
    worktree_branch = workspace.worktree_branch,
    worktree_base = workspace.worktree_base,
    worktree_base_commit = workspace.worktree_base_commit,
    mission_id = workspace.mission_id,
    mission_name = workspace.mission_name,
    mission_role = workspace.mission_role,
    mission_objective = workspace.mission_objective,
    mission_focus_packet = workspace.mission_focus_packet,
    tmux_window = workspace.window_name,
    tmux_target = workspace.tmux_target,
    nvim_server = workspace.nvim_server or existing.nvim_server,
    custom_instruction = workspace.custom_instruction,
    resolved_instruction = workspace.resolved_instruction,
    initial_mode = workspace.initial_mode or existing.initial_mode,
    permission_profile = workspace.permission_profile or "default",
    codex_session_id = M.normalize_session_id(workspace.codex_session_id),
    codex_session_path = workspace.codex_session_path,
    codex_session_captured_at = workspace.codex_session_captured_at,
    status = status,
    codex_status = workspace.codex_status or existing.codex_status or "idle",
    codex_mode = codex_mode,
    created_at = existing.created_at or workspace.created_at or now,
    last_opened_at = now,
    last_activity_at = workspace.last_activity_at or existing.last_activity_at,
    last_target_at = workspace.last_target_at or existing.last_target_at,
    last_reconciled_at = existing.last_reconciled_at,
  }
end

return M
