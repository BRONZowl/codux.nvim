local mission_mod = require("codux.mission")
local text_util = require("codux.text")
local workspace_git = require("codux.workspace_git")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

local inactive_like_status = workspace_git.inactive_like_status

local function entry_key(record_root, safe_name)
  return tostring(record_root) .. "\0" .. tostring(safe_name)
end

local function record_root(project_root, record)
  local explicit_record_root = type(record.project_root) == "string" and record.project_root ~= ""
  return explicit_record_root and record.project_root or project_root, explicit_record_root
end

local function sort_entries(entries)
  table.sort(entries, function(left, right)
    return tostring(left.name):lower() < tostring(right.name):lower()
  end)
end

local function workspace_entry(runtime, session, record, safe_name, record_root)
  local entry_safe_name = record.safe_name or safe_name
  local window_name = record.tmux_window or record.window_name or entry_safe_name
  local window_id = session and runtime:tmux_window_id(session, window_name) or nil
  local status = runtime:dashboard_workspace_status(record, window_id)
  local codex_mode = not inactive_like_status(status) and runtime:normalize_codex_mode(record.codex_mode) or nil

  return {
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
    mission_focus_packet = record.mission_focus_packet,
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
  }
end

local function collect_state_entries(runtime, root, include_record, opts)
  opts = type(opts) == "table" and opts or {}
  local state_data, state_error = runtime:read_state()
  if state_error then
    return {}, {}, nil, state_error
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
            local resolved_root, explicit_record_root = record_root(project_root, record)
            local entry_safe_name = record.safe_name or safe_name
            local key = entry_key(resolved_root, entry_safe_name)
            local include = include_record(record, {
              root = root,
              record_root = resolved_root,
              explicit_record_root = explicit_record_root,
              current_common_dir = current_common_dir,
            })
            if include and (not opts.dedupe or not seen[key]) then
              seen[key] = true
              table.insert(entries, workspace_entry(runtime, session, record, safe_name, resolved_root))
            end
          end
        end
      end
    end
  end

  return entries, seen, session, nil
end

local function include_workspace_entry(record, context)
  return context.record_root == context.root
    or (
      not context.explicit_record_root
      and context.current_common_dir ~= nil
      and record.workspace_kind == "worktree"
      and record.git_common_dir == context.current_common_dir
    )
end

local function include_mission_entry(record, context)
  return type(record.mission_id) == "string"
    and record.mission_id ~= ""
    and (
      context.record_root == context.root
      or (
        context.current_common_dir ~= nil
        and record.workspace_kind == "worktree"
        and record.git_common_dir == context.current_common_dir
      )
    )
end

function M.entries_for_project(runtime, root)
  local entries, seen, session, state_error = collect_state_entries(runtime, root, include_workspace_entry)
  if state_error then
    return {}, state_error
  end

  for safe_name, record in pairs(runtime:instruction_file_records(root)) do
    if type(record) == "table" then
      local entry_safe_name = record.safe_name or safe_name
      if not seen[entry_key(root, entry_safe_name)] then
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

  sort_entries(entries)

  return entries, nil
end

function M.mission_entries_for_project(runtime, root)
  local entries, _, _, state_error = collect_state_entries(runtime, root, include_mission_entry, { dedupe = true })
  if state_error then
    return {}, state_error
  end

  sort_entries(entries)

  return entries, nil
end

function M.missions_for_project(runtime, root)
  local entries, error_message = M.mission_entries_for_project(runtime, root)
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

local function update_mission_role_records(runtime, name, opts)
  opts = type(opts) == "table" and opts or {}
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
  for _, entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    local entry_root = entry.project_root or root
    local safe_name = entry.safe_name
    if type(entry_root) == "string" and entry_root ~= "" and type(safe_name) == "string" and safe_name ~= "" then
      if type(opts.before_record) == "function" then
        local ok, err = opts.before_record(entry, mission, entry_root, safe_name)
        if ok == false then
          return false, err
        end
      end

      local project = runtime:project_state(state_data, entry_root)
      local record = project.workspaces[safe_name]
      if type(record) == "table" then
        local ok, err = opts.update_record(record, entry, mission, entry_root, safe_name)
        if ok == false then
          return false, err
        end
        project.updated_at = runtime:timestamp()
        updated = updated + 1
      end

      if
        type(opts.update_active_workspace) == "function"
        and runtime.state.workspace
        and runtime.state.workspace.project_root == entry_root
        and runtime.state.workspace.safe_name == safe_name
      then
        opts.update_active_workspace(runtime.state.workspace, entry, mission, entry_root, safe_name)
      end
    end
  end

  if updated == 0 and opts.require_updated ~= false then
    return false, "mission roles not found"
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
      .. " "
      .. tostring(opts.label or "records")
      .. " for "
      .. tostring(updated)
      .. " roles"
  )
  return true, nil
end

function M.update_mission_objective(runtime, name, objective, opts)
  opts = type(opts) == "table" and opts or {}
  objective = type(objective) == "string" and trim(objective) or ""
  if objective == "" then
    return false, "Mission objective is required"
  end

  local instructions = {}
  return update_mission_role_records(runtime, name, {
    project_root = opts.project_root,
    label = "objective",
    require_updated = false,
    before_record = function(entry, mission, entry_root, safe_name)
      local role = mission_mod.role_from_entry(entry)
      local instruction = mission_mod.role_instruction(mission.name, objective, role)
      local instruction_ok, instruction_error = runtime:write_instruction_file(entry_root, safe_name, instruction)
      if not instruction_ok then
        return false, instruction_error
      end
      instructions[entry_key(entry_root, safe_name)] = instruction
      return true, nil
    end,
    update_record = function(record, _, _, entry_root, safe_name)
      local instruction = instructions[entry_key(entry_root, safe_name)] or ""
      record.mission_objective = objective
      record.custom_instruction = instruction
      record.resolved_instruction = instruction
      return true, nil
    end,
    update_active_workspace = function(workspace, _, _, entry_root, safe_name)
      local instruction = instructions[entry_key(entry_root, safe_name)] or ""
      workspace.mission_objective = objective
      workspace.custom_instruction = instruction
      workspace.resolved_instruction = instruction
    end,
  })
end

function M.update_mission_focus_packet(runtime, name, focus_packet, opts)
  opts = type(opts) == "table" and opts or {}
  focus_packet = type(focus_packet) == "string" and trim(focus_packet) or ""
  if focus_packet == "" then
    return false, "Mission focus packet is required"
  end

  return update_mission_role_records(runtime, name, {
    project_root = opts.project_root,
    label = "focus",
    update_record = function(record)
      record.mission_focus_packet = focus_packet
      return true, nil
    end,
    update_active_workspace = function(workspace)
      workspace.mission_focus_packet = focus_packet
    end,
  })
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
