local mission_mod = require("codux.mission")
local workspace_instruction_actions = require("codux.workspace_instruction_actions")
local workspace_lifecycle = require("codux.workspace_lifecycle")
local workspace_git = require("codux.workspace_git")

local M = {}

local inactive_like_status = workspace_git.inactive_like_status

function M.saved_workspace_instruction_request(runtime, entry)
  return workspace_instruction_actions.saved_workspace_instruction_request(runtime, entry)
end

function M.update_saved_workspace_instruction(runtime, entry, instruction)
  return workspace_instruction_actions.update_saved_workspace_instruction(runtime, entry, instruction)
end

local function rename_saved_workspace_impl(runtime, entry, new_name, opts)
  opts = type(opts) == "table" and opts or {}
  local function fail(message, level)
    if opts.return_errors == true then
      return false, message
    end
    runtime.notify(message, level or vim.log.levels.ERROR)
    return false
  end

  local display_name, safe_name_or_error = runtime.sanitize_workspace_name(new_name)
  if not display_name then
    return fail(safe_name_or_error)
  end

  local root = entry.project_root or runtime.state.workspace_manager_project_root
  local state_data, state_error = runtime:read_state()
  if state_error then
    return fail(state_error)
  end

  local project = runtime:project_state(state_data, root)
  local existing = project.workspaces[entry.safe_name]
  if type(existing) ~= "table" then
    return fail("workspace not found")
  end
  if safe_name_or_error ~= entry.safe_name and project.workspaces[safe_name_or_error] ~= nil then
    return fail("workspace already exists")
  end

  local new_window_name = runtime.workspace_window_name(safe_name_or_error)
  local old_window_name = existing.tmux_window or existing.window_name or entry.window_name or entry.safe_name
  local previous_project = vim.deepcopy(project)
  local previous_next_project = nil
  local worktree_renamed = false
  local branch_renamed = false
  local old_worktree_path = existing.worktree_path or existing.project_root or root
  local new_worktree_path = nil
  local old_branch = existing.worktree_branch
  local new_branch = nil
  if existing.workspace_kind == "worktree" then
    new_worktree_path = workspace_lifecycle.renamed_worktree_path(old_worktree_path, safe_name_or_error)
    new_branch = runtime:renamed_worktree_branch(existing, safe_name_or_error)
    if runtime.target_path_exists(new_worktree_path) then
      return fail("worktree path already exists")
    end
    if old_branch ~= new_branch and runtime:git_branch_exists(root, new_branch) then
      return fail("branch already exists: " .. new_branch)
    end
    previous_next_project = state_data.projects[new_worktree_path] and vim.deepcopy(state_data.projects[new_worktree_path]) or nil
    if not runtime:move_git_worktree(root, old_worktree_path, new_worktree_path) then
      return fail("Failed to move Git worktree " .. tostring(old_worktree_path))
    end
    worktree_renamed = true
    if old_branch ~= new_branch then
      if not runtime:rename_git_branch(new_worktree_path, old_branch, new_branch) then
        runtime:move_git_worktree(new_worktree_path, new_worktree_path, old_worktree_path)
        return fail("Failed to rename Git branch " .. tostring(old_branch))
      end
      branch_renamed = true
    end
  end
  if not runtime:rename_tmux_window(entry.window_id, new_window_name) then
    if existing.workspace_kind == "worktree" then
      if branch_renamed then
        runtime:rename_git_branch(new_worktree_path, new_branch, old_branch)
      end
      if worktree_renamed then
        runtime:move_git_worktree(new_worktree_path or root, new_worktree_path, old_worktree_path)
      end
    end
    return fail("Failed to rename tmux window " .. tostring(entry.window_name))
  end

  local old_root = root
  local old_safe_name = entry.safe_name
  project.workspaces[entry.safe_name] = nil
  existing.name = display_name
  existing.safe_name = safe_name_or_error
  if existing.workspace_kind == "worktree" then
    existing.project_root = new_worktree_path
    existing.worktree_path = new_worktree_path
    existing.worktree_branch = new_branch
    existing.git_branch = new_branch
    existing.target_path =
      workspace_lifecycle.retarget_path_after_worktree_move(existing.target_path, old_worktree_path, new_worktree_path)
  end
  existing.tmux_window = new_window_name
  existing.tmux_target = entry.window_id and runtime.tmux_target(runtime:current_tmux_session(), new_window_name) or nil
  existing.status = runtime:dashboard_workspace_status(existing, entry.window_id)
  existing.last_opened_at = runtime:timestamp()

  local context = {
    old_root = old_root,
    old_safe_name = old_safe_name,
    old_worktree_path = old_worktree_path,
    new_worktree_path = new_worktree_path,
    old_branch = old_branch,
    new_branch = new_branch,
    display_name = display_name,
    safe_name = safe_name_or_error,
  }
  if type(opts.update_record) == "function" then
    local ok, err = opts.update_record(existing, context)
    if ok == false then
      return fail(err or "Failed to update Codux workspace")
    end
  end

  if existing.workspace_kind == "worktree" then
    if next(project.workspaces) == nil and vim.empty_dict then
      project.workspaces = vim.empty_dict()
    end
    local next_project = runtime:project_state(state_data, new_worktree_path)
    next_project.workspaces[safe_name_or_error] = existing
    next_project.updated_at = runtime:timestamp()
  else
    project.workspaces[safe_name_or_error] = existing
  end
  project.updated_at = runtime:timestamp()

  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    local rollback_errors = {}
    if entry.window_id and old_window_name ~= new_window_name and not runtime:rename_tmux_window(entry.window_id, old_window_name) then
      table.insert(rollback_errors, "failed to restore tmux window")
    end
    if branch_renamed and not runtime:rename_git_branch(new_worktree_path, new_branch, old_branch) then
      table.insert(rollback_errors, "failed to restore Git branch")
    end
    if worktree_renamed and not runtime:move_git_worktree(new_worktree_path or root, new_worktree_path, old_worktree_path) then
      table.insert(rollback_errors, "failed to restore Git worktree")
    end
    state_data.projects[root] = previous_project
    if new_worktree_path then
      state_data.projects[new_worktree_path] = previous_next_project
    end
    local message = write_error or "Failed to write Codux workspace state"
    if #rollback_errors > 0 then
      message = message .. "; " .. table.concat(rollback_errors, "; ")
    end
    return fail(message)
  end

  local instruction_root = existing.workspace_kind == "worktree" and new_worktree_path or root
  local old_instruction_path = runtime:instruction_file_path(instruction_root, entry.safe_name)
  local new_instruction_path =
    runtime:instruction_file_path(existing.workspace_kind == "worktree" and new_worktree_path or root, safe_name_or_error)
  if
    old_instruction_path
    and new_instruction_path
    and old_instruction_path ~= new_instruction_path
    and vim.fn.filereadable(old_instruction_path) == 1
    and vim.fn.filereadable(new_instruction_path) ~= 1
  then
    local rename_ok, rename_result = pcall(vim.fn.rename, old_instruction_path, new_instruction_path)
    if not rename_ok or rename_result ~= 0 then
      if opts.return_errors == true then
        return false, "Renamed workspace, but failed to move Codux instruction file"
      end
      runtime.notify("Renamed workspace, but failed to move Codux instruction file", vim.log.levels.WARN)
    end
  end

  if type(opts.after_instruction_move) == "function" then
    local ok, err = opts.after_instruction_move(existing, context, instruction_root)
    if ok == false then
      return fail(err or "Renamed workspace, but failed to update Codux instruction file")
    end
  end

  if
    type(opts.update_active_workspace) == "function"
    and runtime.state.workspace
    and runtime.state.workspace.project_root == old_root
    and runtime.state.workspace.safe_name == old_safe_name
  then
    opts.update_active_workspace(runtime.state.workspace, existing, context)
  end

  if opts.success_message ~= false then
    runtime.notify("Renamed Codux workspace to " .. display_name)
  end
  if opts.close_manager ~= false then
    runtime.close_workspace_manager()
  end
  return true, nil
end

function M.rename_saved_workspace(runtime, entry, new_name)
  return rename_saved_workspace_impl(runtime, entry, new_name)
end

function M.rename_mission_role(runtime, entry, new_name, opts)
  entry = type(entry) == "table" and entry or {}
  opts = type(opts) == "table" and opts or {}
  local role_name, role_safe_or_error = runtime.sanitize_workspace_name(new_name)
  if not role_name then
    return false, tostring(role_safe_or_error or "Mission role name is required"):gsub("^Workspace", "Mission role")
  end

  local root = opts.project_root or entry.project_root or runtime:project_root()
  local mission_name = entry.mission_name or entry.mission_id
  local mission, mission_error = runtime:mission_for_name(root, mission_name)
  if not mission then
    return false, mission_error or "mission not found"
  end

  local mission_display, mission_safe_or_error = runtime.sanitize_workspace_name(mission.name or entry.mission_name)
  if not mission_display then
    return false, mission_safe_or_error
  end
  local new_workspace_name = mission_mod.workspace_name(mission_safe_or_error, { safe_name = role_safe_or_error })

  local selected_root = entry.project_root or root
  local selected_safe_name = entry.safe_name
  if type(selected_root) ~= "string" or selected_root == "" or type(selected_safe_name) ~= "string" or selected_safe_name == "" then
    return false, "mission role not found"
  end

  for _, role_entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    if not (role_entry.safe_name == selected_safe_name and (role_entry.project_root or root) == selected_root) then
      local other_display, other_safe =
        runtime.sanitize_workspace_name(role_entry.mission_role or role_entry.name or role_entry.safe_name)
      if other_display and other_safe == role_safe_or_error then
        return false, "mission role already exists"
      end
    end
  end

  return rename_saved_workspace_impl(runtime, entry, new_workspace_name, {
    return_errors = true,
    success_message = false,
    close_manager = false,
    update_record = function(existing)
      local role = mission_mod.role_from_entry({
        mission_role = role_name,
        resolved_instruction = existing.resolved_instruction or entry.resolved_instruction,
        custom_instruction = existing.custom_instruction or entry.custom_instruction,
      })
      role.name = role_name
      role.safe_name = role_safe_or_error

      local objective = existing.mission_objective or entry.mission_objective or mission.objective
      local instruction = mission_mod.role_instruction(mission.name, objective, role)
      existing.mission_role = role_name
      existing.custom_instruction = instruction
      existing.resolved_instruction = instruction
      return true, nil
    end,
    after_instruction_move = function(existing, _, instruction_root)
      return runtime:write_instruction_file(instruction_root, existing.safe_name, existing.resolved_instruction)
    end,
    update_active_workspace = function(workspace, existing)
      workspace.name = existing.name
      workspace.safe_name = existing.safe_name
      workspace.project_root = existing.project_root
      workspace.target_path = existing.target_path
      workspace.git_branch = existing.git_branch
      workspace.worktree_path = existing.worktree_path
      workspace.worktree_branch = existing.worktree_branch
      workspace.tmux_window = existing.tmux_window
      workspace.window_name = existing.tmux_window
      workspace.tmux_target = existing.tmux_target
      workspace.mission_role = existing.mission_role
      workspace.custom_instruction = existing.custom_instruction
      workspace.resolved_instruction = existing.resolved_instruction
    end,
  })
end

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
  updated.codex_status = record.codex_status or fallback.codex_status
  updated.codex_mode = record.codex_mode or fallback.codex_mode
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

  local current_path, path_error = runtime:current_worktree_path(entry_from_record(record, safe_name, root, entry))
  if path_error then
    return entry, false, path_error
  end
  if type(current_path) ~= "string" or current_path == "" then
    return entry_from_record(record, safe_name, root, entry), false, nil
  end

  current_path = workspace_git.strip_trailing_slashes(current_path)
  local old_worktree_path = workspace_git.strip_trailing_slashes(record.worktree_path or record.project_root or root)
  local old_root = root
  if current_path == old_worktree_path and record.project_root == current_path and record.worktree_path == current_path then
    return entry_from_record(record, safe_name, root, entry), false, nil
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

  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    return entry, false, write_error
  end

  update_active_workspace(runtime, old_root, safe_name, record)
  return entry_from_record(record, safe_name, current_path, entry), true, nil
end

function M.reconcile_moved_worktrees_for_project(runtime, root, opts)
  opts = type(opts) == "table" and opts or {}
  root = root or runtime:project_root()
  local state_data, state_error = runtime:read_state()
  if state_error then
    return 0, state_error
  end

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
          table.insert(entries, entry_from_record(record, safe_name, project_root, {}))
        end
      end
    end
  end

  local changed = 0
  for _, next_entry in ipairs(entries) do
    local _, did_change, error_message = M.reconcile_moved_worktree(runtime, next_entry, {
      ignore_missing = opts.ignore_missing ~= false,
    })
    if error_message then
      return changed, error_message
    end
    if did_change then
      changed = changed + 1
    end
  end
  return changed, nil
end

function M.delete_saved_workspace(runtime, entry)
  entry = type(entry) == "table" and entry or {}
  local root = entry.project_root or runtime.state.workspace_manager_project_root
  local state_data, state_error = runtime:read_state()
  if state_error then
    runtime.notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = runtime:project_state(state_data, root)
  local existing = project.workspaces[entry.safe_name]
  local instruction_path = runtime:instruction_file_path(root, entry.safe_name)
  local has_instruction_file = instruction_path and vim.fn.filereadable(instruction_path) == 1
  if type(existing) ~= "table" and not has_instruction_file then
    runtime.notify("workspace not found", vim.log.levels.ERROR)
    runtime.render_workspace_manager()
    return false
  end

  if type(existing) == "table" and existing.workspace_kind == "worktree" then
    local worktree_path = existing.worktree_path or existing.project_root or root
    local worktree_branch = existing.worktree_branch
    local git_common_dir = existing.git_common_dir
    local previous_project = vim.deepcopy(project)
    if type(git_common_dir) ~= "string" or git_common_dir == "" then
      git_common_dir = runtime:git_common_dir(worktree_path)
    end
    if type(git_common_dir) ~= "string" or git_common_dir == "" then
      runtime.notify("Failed to resolve Git common directory for " .. tostring(worktree_path), vim.log.levels.ERROR)
      runtime.render_workspace_manager()
      return false
    end
    project.workspaces[entry.safe_name] = nil
    if next(project.workspaces) == nil and vim.empty_dict then
      project.workspaces = vim.empty_dict()
    end
    if next(project.workspaces) == nil and root == (existing.worktree_path or existing.project_root) then
      state_data.projects[root] = nil
    end
    project.updated_at = runtime:timestamp()
    local write_ok, write_error = runtime:write_state(state_data)
    if not write_ok then
      state_data.projects[root] = previous_project
      runtime.notify(write_error, vim.log.levels.ERROR)
      return false
    end

    local function restore_state_after_delete(message)
      state_data.projects[root] = previous_project
      local restore_ok, restore_error = runtime:write_state(state_data)
      if not restore_ok then
        message = tostring(message or "Failed to delete Codux workspace")
          .. "; "
          .. tostring(restore_error or "failed to restore workspace state")
      end
      runtime.notify(message, vim.log.levels.ERROR)
      runtime.render_workspace_manager()
      return false
    end

    if entry.window_id and not runtime:kill_tmux_window(entry.window_id) then
      return restore_state_after_delete("Failed to close tmux window " .. tostring(entry.window_name))
    end

    local delete_instruction_ok, delete_instruction_error = runtime:delete_instruction_file(root, entry.safe_name)
    if not delete_instruction_ok then
      return restore_state_after_delete(delete_instruction_error)
    end

    local remove_ok, remove_error = runtime:remove_git_worktree_in_common_dir(git_common_dir, worktree_path)
    if not remove_ok then
      return restore_state_after_delete(remove_error or ("Failed to remove Git worktree " .. tostring(worktree_path)))
    end
    if type(worktree_branch) == "string" and worktree_branch ~= "" then
      local branch_ok, branch_error = runtime:delete_git_branch_in_common_dir(git_common_dir, worktree_branch)
      if not branch_ok then
        runtime.notify(
          (branch_error or ("Failed to delete Git branch " .. tostring(worktree_branch)))
            .. "; workspace state was removed but branch cleanup is incomplete",
          vim.log.levels.ERROR
        )
        runtime.render_workspace_manager()
        return false
      end
    end

    runtime.notify("Deleted Codux workspace " .. tostring(entry.name or entry.safe_name))
    runtime.close_workspace_manager()
    return true
  end

  local previous_project = vim.deepcopy(project)
  project.workspaces[entry.safe_name] = nil
  if next(project.workspaces) == nil and vim.empty_dict then
    project.workspaces = vim.empty_dict()
  end
  project.updated_at = runtime:timestamp()
  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    runtime.notify(write_error, vim.log.levels.ERROR)
    return false
  end

  local delete_instruction_ok, delete_instruction_error = runtime:delete_instruction_file(root, entry.safe_name)
  if not delete_instruction_ok then
    if type(existing) == "table" then
      state_data.projects[root] = previous_project
      local restore_ok, restore_error = runtime:write_state(state_data)
      if not restore_ok then
        local message = (delete_instruction_error or "Failed to delete Codux workspace instruction file")
          .. "; "
          .. (restore_error or "failed to restore workspace state")
        runtime.notify(message, vim.log.levels.ERROR)
      else
        runtime.notify(delete_instruction_error, vim.log.levels.ERROR)
      end
    else
      runtime.notify(delete_instruction_error, vim.log.levels.ERROR)
    end
    runtime.render_workspace_manager()
    return false
  end

  runtime.notify("Deleted Codux workspace " .. tostring(entry.name or entry.safe_name))
  runtime.close_workspace_manager()
  runtime:kill_tmux_window_deferred(entry.window_id, entry.window_name)
  return true
end

function M.close_saved_workspace_window(runtime, entry)
  local root = entry.project_root or runtime.state.workspace_manager_project_root
  local state_data, state_error = runtime:read_state()
  if state_error then
    runtime.notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = runtime:project_state(state_data, root)
  local existing = project.workspaces[entry.safe_name]
  if type(existing) ~= "table" then
    runtime.notify("workspace not found", vim.log.levels.ERROR)
    runtime.render_workspace_manager()
    return false
  end

  local session = runtime:current_tmux_session()
  local window_name = existing.tmux_window or existing.window_name or entry.window_name or entry.safe_name
  local window_id = entry.window_id or (session and runtime:tmux_window_id(session, window_name)) or nil
  if window_id and not runtime:kill_tmux_window(window_id) then
    runtime.notify("Failed to close tmux window " .. tostring(window_name), vim.log.levels.ERROR)
    return false
  end

  existing.status = "inactive"
  existing.codex_status = "idle"
  existing.codex_mode = nil
  existing.tmux_window = window_name
  existing.tmux_target = nil
  existing.last_reconciled_at = runtime:timestamp()
  project.updated_at = existing.last_reconciled_at

  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    runtime.notify(write_error, vim.log.levels.ERROR)
    return false
  end

  runtime.notify("Closed Codux workspace " .. tostring(existing.name or entry.name or entry.safe_name))
  runtime.render_workspace_manager()
  return true
end

function M.close_all_saved_workspace_windows(runtime, root)
  root = root or runtime.state.workspace_manager_project_root or runtime:project_root()
  local state_data, state_error = runtime:read_state()
  if state_error then
    runtime.notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  if type(workspaces) ~= "table" or next(workspaces) == nil then
    runtime.notify("No Codux workspaces to close", vim.log.levels.WARN)
    return false
  end

  local session = runtime:current_tmux_session()
  local closed = 0
  local failed = 0
  local now = runtime:timestamp()
  local close_results = {}

  for safe_name, record in pairs(workspaces) do
    if type(record) == "table" then
      local entry_safe_name = record.safe_name or safe_name
      local window_name = record.tmux_window or record.window_name or safe_name
      local window_id = session and runtime:tmux_window_id(session, window_name) or nil
      local close_failed = false
      if window_id then
        if runtime:kill_tmux_window(window_id) then
          closed = closed + 1
        else
          failed = failed + 1
          close_failed = true
        end
      end
      close_results[entry_safe_name] = not close_failed

      if not close_failed then
        record.status = "inactive"
        record.codex_status = "idle"
        record.codex_mode = nil
        record.tmux_target = nil
      end
      record.tmux_window = window_name
      record.last_reconciled_at = now
    end
  end

  project.updated_at = now
  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    runtime.notify(write_error, vim.log.levels.ERROR)
    return false
  end

  if runtime.state.workspace and runtime.state.workspace.project_root == root then
    local current_safe_name = runtime.state.workspace.safe_name
    if close_results[current_safe_name] then
      runtime.state.workspace.status = "inactive"
      runtime.state.workspace.codex_status = "idle"
      runtime.state.workspace.codex_mode = nil
      runtime.state.workspace.tmux_target = nil
    end
  end

  if failed > 0 then
    runtime.notify("Closed " .. tostring(closed) .. " Codux workspaces; " .. tostring(failed) .. " failed", vim.log.levels.WARN)
  else
    runtime.notify("Closed " .. tostring(closed) .. " Codux workspaces")
  end
  if runtime.state.workspace_manager_project_root == root then
    runtime.render_workspace_manager()
  end

  return failed == 0
end

function M.open_saved_workspace(runtime, name, project_root)
  local workspace, error_message = runtime:prepare_workspace(name, {
    allow_existing = true,
    initial_mode = "plan",
    require_existing = true,
    project_root = project_root,
  })
  if not workspace then
    runtime.notify(error_message or "Failed to open Codux workspace", vim.log.levels.ERROR)
    return false
  end

  if not runtime:switch_tmux_window(workspace.window_id) then
    runtime.notify("Failed to switch to Codux workspace " .. workspace.name, vim.log.levels.ERROR)
    return false
  end

  local branch = workspace.git_branch ~= "" and " on " .. workspace.git_branch or ""
  runtime.notify("Opened Codux workspace " .. workspace.name .. branch)
  return true
end

function M.select_workspace(runtime, name)
  return runtime:open_saved_workspace(name, runtime:project_root())
end

function M.rename_workspace(runtime, old_name, new_name)
  local root = runtime:project_root()
  local entry, error_message = runtime:entry_for_name(root, old_name)
  if not entry then
    runtime.notify(error_message or "workspace not found", vim.log.levels.ERROR)
    return false
  end
  return runtime:rename_saved_workspace(entry, new_name)
end

function M.delete_workspace(runtime, name)
  local root = runtime:project_root()
  local entry, error_message = runtime:entry_for_name(root, name)
  if not entry then
    runtime.notify(error_message or "workspace not found", vim.log.levels.ERROR)
    return false
  end
  return runtime:delete_saved_workspace(entry)
end

function M.restore_workspaces(runtime, opts)
  opts = opts or {}
  local root = opts.project_root or runtime:project_root()
  local summary, error_message = runtime:reconcile_project(root)
  if error_message then
    runtime.notify(error_message, vim.log.levels.WARN)
    return false
  end

  if not opts.silent then
    runtime.notify(
      "Restored Codux workspaces: "
        .. tostring(summary.total)
        .. " total, "
        .. tostring(summary.active)
        .. " active, "
        .. tostring(summary.question)
        .. " question, "
        .. tostring(summary.idle)
        .. " idle, "
        .. tostring(summary.inactive)
        .. " inactive"
    )
  end

  if runtime.state.workspace_manager_project_root == root then
    runtime.render_workspace_manager()
  end

  return true
end

return M
