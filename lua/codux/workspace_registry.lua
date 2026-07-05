local mission_mod = require("codux.mission")
local text_util = require("codux.text")
local workspace_git = require("codux.workspace_git")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

local inactive_like_status = workspace_git.inactive_like_status

function M.entries_for_project(runtime, root)
  local state_data, state_error = runtime:read_state()
  if state_error then
    return {}, state_error
  end

  local current_common_dir = runtime:git_common_dir(root)
  local session = runtime:current_tmux_session()
  local entries = {}
  local seen = {}

  if type(state_data.projects) == "table" then
    for project_root, project in pairs(state_data.projects) do
      local workspaces = type(project) == "table" and project.workspaces or nil
      if type(workspaces) == "table" then
        for safe_name, record in pairs(workspaces) do
          if type(record) == "table" then
            local explicit_record_root = type(record.project_root) == "string" and record.project_root ~= ""
            local record_root = explicit_record_root and record.project_root or project_root
            local include = record_root == root
              or (
                not explicit_record_root
                and current_common_dir ~= nil
                and record.workspace_kind == "worktree"
                and record.git_common_dir == current_common_dir
              )
            if include then
              local entry_safe_name = record.safe_name or safe_name
              local window_name = record.tmux_window or record.window_name or entry_safe_name
              local window_id = session and runtime:tmux_window_id(session, window_name) or nil
              local status = runtime:dashboard_workspace_status(record, window_id)
              local codex_mode = not inactive_like_status(status) and runtime:normalize_codex_mode(record.codex_mode) or nil
              seen[tostring(record_root) .. "\0" .. tostring(entry_safe_name)] = true
              table.insert(entries, {
                name = record.name or entry_safe_name,
                safe_name = entry_safe_name,
                project_root = record_root,
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
                custom_instruction = record.custom_instruction,
                resolved_instruction = record.resolved_instruction,
                window_name = window_name,
                tmux_target = runtime.tmux_target(session, window_name) or record.tmux_target,
                nvim_server = record.nvim_server or runtime:workspace_server_path(record_root, entry_safe_name),
                initial_mode = record.initial_mode,
                codex_status = record.codex_status or "idle",
                codex_mode = codex_mode,
                permission_profile = record.permission_profile or "default",
                codex_session_captured_at = record.codex_session_captured_at,
                created_at = record.created_at,
                last_opened_at = record.last_opened_at,
                last_activity_at = record.last_activity_at,
                last_target_at = record.last_target_at,
                last_reconciled_at = record.last_reconciled_at,
                window_id = window_id,
                status = status,
              })
            end
          end
        end
      end
    end
  end

  for safe_name, record in pairs(runtime:instruction_file_records(root)) do
    if type(record) == "table" then
      local entry_safe_name = record.safe_name or safe_name
      if not seen[tostring(root) .. "\0" .. tostring(entry_safe_name)] then
        local window_name = runtime.workspace_window_name(entry_safe_name)
        local window_id = session and runtime:tmux_window_id(session, window_name) or nil
        local status = runtime:dashboard_workspace_status({ status = "inactive", codex_status = "idle" }, window_id)
        table.insert(entries, {
          name = record.name or entry_safe_name,
          safe_name = entry_safe_name,
          project_root = record.project_root or root,
          git_branch = "",
          window_name = window_name,
          tmux_target = runtime.tmux_target(session, window_name),
          nvim_server = runtime:workspace_server_path(record.project_root or root, entry_safe_name),
          initial_mode = record.initial_mode,
          codex_status = "idle",
          permission_profile = record.permission_profile or "default",
          codex_session_captured_at = record.codex_session_captured_at,
          created_at = record.created_at,
          last_opened_at = record.last_opened_at,
          last_activity_at = record.last_activity_at,
          last_target_at = record.last_target_at,
          window_id = window_id,
          status = status,
          instruction_file = record.instruction_file,
          instruction_file_only = true,
        })
      end
    end
  end

  table.sort(entries, function(left, right)
    return tostring(left.name):lower() < tostring(right.name):lower()
  end)

  return entries, nil
end

function M.missions_for_project(runtime, root)
  local entries, error_message = runtime:entries_for_project(root)
  if error_message then
    return {}, error_message
  end

  return mission_mod.group_entries(entries), nil
end

function M.mission_for_name(runtime, root, name)
  local missions, error_message = runtime:missions_for_project(root)
  if error_message then
    return nil, error_message
  end

  return mission_mod.find_mission(missions, name)
end

function M.mission_names_for_project(runtime, root)
  local missions, error_message = runtime:missions_for_project(root)
  if error_message then
    return {}
  end

  return mission_mod.names(missions)
end

function M.update_mission_objective(runtime, name, objective, opts)
  opts = type(opts) == "table" and opts or {}
  objective = type(objective) == "string" and trim(objective) or ""
  if objective == "" then
    return false, "Mission objective is required"
  end

  local root = opts.project_root or runtime:project_root()
  local mission, mission_error = runtime:mission_for_name(root, name)
  if not mission then
    return false, mission_error or "mission not found"
  end

  local state_data, state_error = runtime:read_state()
  if state_error then
    return false, state_error
  end

  local updated = 0
  for _, entry in ipairs(mission.roles) do
    local entry_root = entry.project_root or root
    local safe_name = entry.safe_name
    if type(entry_root) == "string" and entry_root ~= "" and type(safe_name) == "string" and safe_name ~= "" then
      local role = mission_mod.role_from_entry(entry)
      local instruction = mission_mod.role_instruction(mission.name, objective, role)
      local instruction_ok, instruction_error = runtime:write_instruction_file(entry_root, safe_name, instruction)
      if not instruction_ok then
        return false, instruction_error
      end

      local project = runtime:project_state(state_data, entry_root)
      local record = project.workspaces[safe_name]
      if type(record) == "table" then
        record.mission_objective = objective
        record.custom_instruction = instruction
        record.resolved_instruction = instruction
        project.updated_at = runtime:timestamp()
        updated = updated + 1
      end

      if runtime.state.workspace and runtime.state.workspace.project_root == entry_root and runtime.state.workspace.safe_name == safe_name then
        runtime.state.workspace.mission_objective = objective
        runtime.state.workspace.custom_instruction = instruction
        runtime.state.workspace.resolved_instruction = instruction
      end
    end
  end

  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    return false, write_error
  end

  if runtime.state.workspace_manager_project_root then
    runtime.render_workspace_manager()
  end

  runtime.notify(
    "Updated Codux mission "
      .. tostring(mission.name or name)
      .. " objective for "
      .. tostring(updated)
      .. " roles"
  )
  return true, nil
end

function M.entry_for_name(runtime, root, name)
  local display_name, safe_name_or_error = runtime.sanitize_workspace_name(name)
  if not display_name then
    return nil, safe_name_or_error
  end

  local entries, error_message = runtime:entries_for_project(root)
  if error_message then
    return nil, error_message
  end

  for _, entry in ipairs(entries) do
    if entry.safe_name == safe_name_or_error or entry.name == name then
      return entry, nil
    end
  end

  return nil, "workspace not found"
end

function M.names_for_project(runtime, root)
  local entries, error_message = runtime:entries_for_project(root)
  if error_message then
    return {}
  end

  local names = {}
  for _, entry in ipairs(entries) do
    table.insert(names, entry.name or entry.safe_name)
  end
  table.sort(names, function(left, right)
    return tostring(left):lower() < tostring(right):lower()
  end)
  return names
end

function M.reconcile_project(runtime, root)
  local summary = {
    total = 0,
    active = 0,
    question = 0,
    idle = 0,
    inactive = 0,
    changed = 0,
  }

  local state_data, state_error = runtime:read_state()
  if state_error then
    return summary, state_error
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  if type(workspaces) ~= "table" then
    return summary, nil
  end

  local session = nil
  if vim.fn.executable(runtime:tmux_cmd()) == 1 then
    session = runtime:current_tmux_session()
  end

  local reconciled_at = runtime:timestamp()
  for safe_name, record in pairs(workspaces) do
    if type(record) == "table" then
      summary.total = summary.total + 1
      local window_name = record.tmux_window or record.window_name or safe_name
      local window_id = session and runtime:tmux_window_id(session, window_name) or nil
      local status = runtime:dashboard_workspace_status(record, window_id)
      if status == "active" then
        summary.active = summary.active + 1
      elseif status == "question" then
        summary.question = summary.question + 1
      elseif status == "idle" then
        summary.idle = summary.idle + 1
      else
        summary.inactive = summary.inactive + 1
      end

      local stale_activity = inactive_like_status(status)
        and (record.codex_status == "working" or record.codex_status == "question" or record.codex_mode ~= nil)
      if record.status ~= status or stale_activity then
        summary.changed = summary.changed + 1
      end
      record.status = status
      if inactive_like_status(status) then
        record.codex_status = "idle"
        record.codex_mode = nil
      end
      record.tmux_window = window_name
      record.tmux_target = runtime.tmux_target(session, window_name) or record.tmux_target
      record.last_reconciled_at = reconciled_at
    end
  end

  project.updated_at = reconciled_at
  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    return summary, write_error
  end

  return summary, nil
end

return M
