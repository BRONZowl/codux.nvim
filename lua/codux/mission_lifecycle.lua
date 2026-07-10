local text_util = require("codux.text")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.dirty_roles(runtime, name, opts)
  opts = type(opts) == "table" and opts or {}
  local root = opts.project_root or runtime:project_root()
  local mission, mission_error = runtime:mission_for_name(root, name)
  if not mission then
    return nil, mission_error or "mission not found"
  end

  local dirty = {}
  for _, entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    local path = entry.worktree_path or entry.project_root
    local label = entry.name or entry.safe_name or entry.mission_role or "unknown"
    if type(path) ~= "string" or path == "" then
      table.insert(dirty, { name = label, reason = "unknown" })
    else
      local output, code = runtime.system({ "git", "-C", path, "status", "--porcelain" })
      if code ~= 0 then
        table.insert(dirty, { name = label, reason = "unknown" })
      elseif trim(output) ~= "" then
        table.insert(dirty, { name = label, reason = "dirty" })
      end
    end
  end

  return dirty, nil
end

function M.close(runtime, name, opts)
  opts = type(opts) == "table" and opts or {}
  local root = opts.project_root or runtime:project_root()
  local mission, mission_error = runtime:mission_for_name(root, name)
  if not mission then
    runtime.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  local state_data, state_error = runtime:read_state()
  if state_error then
    runtime.notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local session = runtime:current_tmux_session()
  local now = runtime:timestamp()
  local closed = 0
  local failed = 0
  local close_results = {}

  for _, entry in ipairs(vim.deepcopy(mission.roles)) do
    local entry_root = entry.project_root or root
    local safe_name = entry.safe_name
    local project = type(state_data.projects) == "table" and state_data.projects[entry_root] or nil
    local workspaces = type(project) == "table" and project.workspaces or nil
    local record = type(workspaces) == "table" and type(safe_name) == "string" and workspaces[safe_name] or nil
    if type(record) ~= "table" then
      failed = failed + 1
    else
      local window_name = record.tmux_window or record.window_name or entry.window_name or safe_name
      local window_id = entry.window_id or (session and runtime:tmux_window_id(session, window_name)) or nil
      local close_failed = false
      if window_id and not runtime:kill_tmux_window(window_id) then
        failed = failed + 1
        close_failed = true
      end

      if not close_failed then
        record.status = "inactive"
        record.agent_status = "idle"
        record.agent_mode = nil
        record.tmux_target = nil
        closed = closed + 1
        close_results[tostring(entry_root) .. "\0" .. tostring(safe_name)] = true
      end
      record.tmux_window = window_name
      record.last_reconciled_at = now
      project.updated_at = now
    end
  end

  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    runtime.notify(write_error, vim.log.levels.ERROR)
    return false
  end

  if runtime.state.workspace then
    local key = tostring(runtime.state.workspace.project_root or "") .. "\0" .. tostring(runtime.state.workspace.safe_name or "")
    if close_results[key] then
      runtime.state.workspace.status = "inactive"
      runtime.state.workspace.agent_status = "idle"
      runtime.state.workspace.agent_mode = nil
      runtime.state.workspace.tmux_target = nil
    end
  end

  if failed > 0 then
    runtime.notify(
      "Closed "
        .. tostring(closed)
        .. " roles in Codux mission "
        .. tostring(mission.name or name)
        .. "; "
        .. tostring(failed)
        .. " failed",
      vim.log.levels.WARN
    )
  else
    runtime.notify("Closed Codux mission " .. tostring(mission.name or name) .. " with " .. tostring(closed) .. " roles")
  end

  if runtime.state.workspace_manager_project_root then
    runtime.render_workspace_manager()
  end

  return failed == 0
end

function M.start(runtime, name, opts)
  opts = type(opts) == "table" and opts or {}
  local root = opts.project_root or runtime:project_root()
  local mission, mission_error = runtime:mission_for_name(root, name)
  if not mission then
    runtime.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  local started = 0
  local failed = 0
  local started_workspaces = {}
  for _, entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    local workspace_name = entry.name or entry.safe_name
    if type(workspace_name) ~= "string" or workspace_name == "" then
      failed = failed + 1
    else
      local workspace, workspace_error = runtime:prepare_workspace(workspace_name, {
        allow_existing = true,
        initial_mode = "plan",
        agent_provider = entry.agent_provider,
        permission_profile = entry.permission_profile or "auto",
        require_existing = true,
        project_root = entry.project_root or root,
        restart_inactive = opts.restart_inactive == true,
      })
      if workspace then
        started = started + 1
        table.insert(started_workspaces, workspace)
        workspace.initial_mode = "plan"
        runtime:ensure_workspace_plan_mode(workspace)
      else
        failed = failed + 1
        local label = entry.mission_role or entry.name or entry.safe_name or "workspace"
        runtime.notify(
          "Failed to start Codux mission role " .. tostring(label) .. ": " .. tostring(workspace_error or "unknown error"),
          vim.log.levels.WARN
        )
      end
    end
  end

  if failed > 0 then
    runtime.notify(
      "Started "
        .. tostring(started)
        .. " roles in Codux mission "
        .. tostring(mission.name or name)
        .. "; "
        .. tostring(failed)
        .. " failed",
      vim.log.levels.WARN
    )
  else
    runtime.notify("Started Codux mission " .. tostring(mission.name or name) .. " with " .. tostring(started) .. " roles")
  end

  if runtime.state.workspace_manager_project_root then
    runtime.render_workspace_manager()
  end

  if opts.focus_first == true and failed == 0 and started_workspaces[1] then
    local workspace = started_workspaces[1]
    if not runtime:switch_tmux_window(workspace.window_id) then
      runtime.notify("Failed to switch to Codux mission role " .. tostring(workspace.mission_role or workspace.name), vim.log.levels.ERROR)
      return false
    end
  end

  return failed == 0
end

function M.delete(runtime, name, opts)
  opts = type(opts) == "table" and opts or {}
  local root = opts.project_root or runtime:project_root()
  local mission, mission_error = runtime:mission_for_name(root, name)
  if not mission then
    runtime.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  local deleted = 0
  for _, entry in ipairs(vim.deepcopy(mission.roles)) do
    if runtime:delete_saved_workspace(entry) then
      deleted = deleted + 1
    else
      runtime.notify(
        "Stopped deleting Codux mission "
          .. tostring(mission.name or name)
          .. " after "
          .. tostring(deleted)
          .. " roles",
        vim.log.levels.ERROR
      )
      return false
    end
  end

  if type(runtime.cleanup_mission_residue) == "function" then
    local cleanup_ok, cleanup_result = runtime:cleanup_mission_residue(root)
    if not cleanup_ok then
      runtime.notify(
        "Deleted Codux mission "
          .. tostring(mission.name or name)
          .. " with "
          .. tostring(deleted)
          .. " roles; residue cleanup failed: "
          .. tostring(cleanup_result),
        vim.log.levels.ERROR
      )
      return false
    end
  end

  runtime.notify("Deleted Codux mission " .. tostring(mission.name or name) .. " with " .. tostring(deleted) .. " roles")
  return true
end

return M
