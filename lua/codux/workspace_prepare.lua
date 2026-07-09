local mission_mod = require("codux.mission")
local text_util = require("codux.text")
local workspace_git = require("codux.workspace_git")
local providers = require("codux.providers")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

local normalize_codex_mode = workspace_git.normalize_codex_mode
local inactive_like_status = workspace_git.inactive_like_status

local function mission_role_specs(runtime, mission, base_root)
  local specs = {}
  local seen = {}
  for _, role in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    local display_name, safe_name_or_error = runtime.sanitize_workspace_name(role.workspace_name)
    if not display_name then
      return nil, safe_name_or_error
    end
    if seen[safe_name_or_error] then
      return nil, "Duplicate mission workspace: " .. safe_name_or_error
    end
    seen[safe_name_or_error] = true
    table.insert(specs, {
      role = role,
      safe_name = safe_name_or_error,
      worktree_path = runtime:mission_worktree_path(base_root, safe_name_or_error),
    })
  end
  return specs, nil
end

local function tmux_window_error(window_name, detail)
  local message = "Failed to create tmux window " .. tostring(window_name)
  detail = trim(detail)
  if detail ~= "" then
    message = message .. ": " .. detail
  end
  return message
end

function M.prepare(runtime, name, opts)
  opts = opts or {}
  if not runtime:workspaces_enabled() then
    return nil, "Codux workspaces are disabled"
  end

  if vim.fn.executable(runtime:tmux_cmd()) ~= 1 then
    return nil, "tmux not found on PATH"
  end

  local display_name, safe_name_or_error = runtime.sanitize_workspace_name(name)
  if not display_name then
    return nil, safe_name_or_error
  end

  local session = runtime:current_tmux_session()
  if not session then
    return nil, "no tmux session running"
  end

  local context = runtime:target_context()
  local base_root = context.root
  local root = opts.project_root or base_root
  local creating_worktree = not opts.allow_existing and not opts.require_existing
  local created_worktree_path = nil
  local created_worktree_branch = nil
  local worktree_base = nil
  local worktree_base_commit = nil
  local git_common_dir = nil

  if creating_worktree then
    local clean, clean_error = runtime:git_checkout_clean(base_root)
    if not clean then
      return nil, clean_error
    end

    local branch_error = nil
    created_worktree_branch, branch_error = runtime:resolve_worktree_branch(base_root, safe_name_or_error)
    if not created_worktree_branch then
      return nil, branch_error
    end
    created_worktree_path = opts.worktree_path or runtime:worktree_path(base_root, safe_name_or_error)
    worktree_base = runtime:git_current_ref(base_root)
    worktree_base_commit = runtime:git_rev_parse(base_root, worktree_base)
    if not worktree_base_commit then
      return nil, "failed to resolve workspace base commit"
    end
    git_common_dir = runtime:git_common_dir(base_root)
    if not git_common_dir then
      return nil, "not inside a Git repository"
    end
    if runtime.target_path_exists(created_worktree_path) then
      return nil, "worktree path already exists"
    end
    local worktree_ok, worktree_error =
      runtime:create_git_worktree(base_root, created_worktree_path, created_worktree_branch, worktree_base)
    if not worktree_ok then
      return nil, worktree_error
    end

    root = created_worktree_path
  end

  runtime:warn_workspace_instruction_ignore(root)
  local custom_instruction = type(opts.custom_instruction) == "string" and trim(opts.custom_instruction) or nil
  if custom_instruction == "" then
    custom_instruction = nil
  end
  local resolved_instruction = type(opts.resolved_instruction) == "string" and trim(opts.resolved_instruction) or nil
  if resolved_instruction == "" then
    resolved_instruction = nil
  end
  local initial_prompt = type(opts.initial_prompt) == "string" and trim(opts.initial_prompt) or nil
  if initial_prompt == "" then
    initial_prompt = nil
  end
  local initial_mode = normalize_codex_mode(opts.initial_mode)
  local runtime_agent_provider = type(runtime.agent_provider) == "function" and runtime:agent_provider() or "codex"
  local agent_provider = providers.normalize_provider(opts.agent_provider) or runtime_agent_provider
  local permission_profile = opts.permission_profile == "auto" and "auto"
    or opts.permission_profile == "danger" and "danger"
    or opts.permission_profile == "default" and "default"
    or runtime:permission_profile()

  local state_data, state_error = runtime:read_state()
  if state_error then
    runtime.notify(state_error .. "; starting with empty workspace state", vim.log.levels.WARN)
  end

  local project = runtime:project_state(state_data, root)
  local existing = project.workspaces[safe_name_or_error]
  local file_instruction = runtime:read_instruction_file(root, safe_name_or_error)
  if type(existing) == "table" and not opts.allow_existing then
    if creating_worktree then
      local cleanup_ok, cleanup_error = runtime:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
      if cleanup_ok == false then
        return nil, "workspace already exists; cleanup failed: " .. tostring(cleanup_error)
      end
    end
    return nil, "workspace already exists"
  end
  if type(existing) == "table" and existing.name ~= display_name and not opts.allow_existing then
    if creating_worktree then
      local cleanup_ok, cleanup_error = runtime:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
      if cleanup_ok == false then
        return nil, "workspace already exists; cleanup failed: " .. tostring(cleanup_error)
      end
    end
    return nil, "workspace already exists"
  end
  if type(existing) ~= "table" and file_instruction and not opts.allow_existing then
    if creating_worktree then
      local cleanup_ok, cleanup_error = runtime:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
      if cleanup_ok == false then
        return nil, "workspace already exists; cleanup failed: " .. tostring(cleanup_error)
      end
    end
    return nil, "workspace already exists"
  end
  if opts.require_existing and type(existing) ~= "table" and not file_instruction then
    return nil, "workspace not found"
  end

  local fallback_target_path = context.path
  local fallback_target_type = context.target and context.target.type or nil
  if creating_worktree then
    fallback_target_path, fallback_target_type =
      runtime:target_in_worktree(context.path, fallback_target_type, base_root, root)
  end

  local fallback = {
    name = display_name,
    safe_name = safe_name_or_error,
    project_root = root,
    target_path = fallback_target_path,
    target_type = fallback_target_type,
    git_branch = creating_worktree and created_worktree_branch or context.branch,
    workspace_kind = creating_worktree and "worktree" or nil,
    git_common_dir = git_common_dir,
    worktree_path = created_worktree_path,
    worktree_branch = created_worktree_branch,
    worktree_base = worktree_base,
    worktree_base_commit = worktree_base_commit,
    mission_id = opts.mission_id,
    mission_name = opts.mission_name,
    mission_role = opts.mission_role,
    mission_objective = opts.mission_objective,
    mission_focus_packet = opts.mission_focus_packet,
    window_name = runtime.workspace_window_name(safe_name_or_error),
    nvim_server = runtime:workspace_server_path(root, safe_name_or_error),
    custom_instruction = custom_instruction,
    resolved_instruction = resolved_instruction,
    initial_mode = initial_mode,
    agent_provider = agent_provider,
    permission_profile = permission_profile,
    codex_status = "idle",
    status = "idle",
  }
  local workspace = runtime:workspace_from_state(existing, fallback)
  workspace.project_root = workspace.project_root or root
  workspace.target_path, workspace.target_type =
    runtime.normalize_workspace_target(workspace.target_path, workspace.target_type, workspace.project_root)
  if custom_instruction then
    workspace.custom_instruction = custom_instruction
  end
  if initial_prompt then
    workspace.initial_prompt = initial_prompt
  end
  workspace.permission_profile = permission_profile
  workspace.agent_provider = agent_provider
  if agent_provider == "grok" and (type(workspace.agent_session_id) ~= "string" or workspace.agent_session_id == "") then
    workspace.agent_session_id = providers.generate_session_id()
  end
  workspace.mission_id = opts.mission_id or workspace.mission_id
  workspace.mission_name = opts.mission_name or workspace.mission_name
  workspace.mission_role = opts.mission_role or workspace.mission_role
  workspace.mission_objective = opts.mission_objective or workspace.mission_objective
  workspace.mission_focus_packet = opts.mission_focus_packet or workspace.mission_focus_packet
  workspace.session = session
  workspace.safe_name = workspace.safe_name or safe_name_or_error
  workspace.window_name = runtime.workspace_window_name(workspace.safe_name)
  workspace.tmux_target = runtime.tmux_target(session, workspace.window_name)
  workspace.initial_mode = initial_mode or workspace.initial_mode
  local saved_workspace = type(existing) == "table" or (opts.require_existing and file_instruction ~= nil)
  workspace.open_visible = not saved_workspace

  if not resolved_instruction and file_instruction then
    resolved_instruction = file_instruction
  end
  if not resolved_instruction and type(workspace.resolved_instruction) == "string" and trim(workspace.resolved_instruction) ~= "" then
    resolved_instruction = workspace.resolved_instruction
  end
  if resolved_instruction then
    workspace.resolved_instruction = resolved_instruction
  end
  if saved_workspace then
    runtime:resolve_workspace_resume_session(workspace)
  end

  local existing_window_id = runtime:tmux_window_id(session, workspace.window_name)
  local restarting_inactive = opts.restart_inactive == true
    and existing_window_id ~= nil
    and inactive_like_status(runtime:status_for_window(existing_window_id))
  if existing_window_id and not restarting_inactive then
    workspace.nvim_server = workspace.nvim_server or runtime:workspace_server_path(workspace.project_root, workspace.safe_name)
  else
    workspace.nvim_server = runtime:workspace_launch_server_path(workspace.project_root, workspace.safe_name)
  end

  local should_create_window = not existing_window_id or restarting_inactive
  local launch_script = nil
  if should_create_window then
    local launch_error = nil
    launch_script, launch_error = runtime:write_launch_script(workspace)
    if not launch_script then
      if creating_worktree then
        local cleanup_ok, cleanup_error = runtime:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
        if cleanup_ok == false then
          return nil, tostring(launch_error) .. "; cleanup failed: " .. tostring(cleanup_error)
        end
      end
      return nil, launch_error
    end
    workspace.launch_script = launch_script
  end

  local window_id, created, tmux_error =
    runtime:ensure_tmux_window(session, workspace.project_root, workspace.window_name, runtime:nvim_command(workspace), {
      restart_inactive = opts.restart_inactive == true,
    })
  if not window_id then
    runtime:delete_launch_script(launch_script)
    local create_error = tmux_window_error(workspace.window_name, tmux_error)
    if creating_worktree then
      local cleanup_ok, cleanup_error = runtime:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
      if cleanup_ok == false then
        return nil, create_error .. "; cleanup failed: " .. tostring(cleanup_error)
      end
    end
    return nil, create_error
  end

  local wrote_new_instruction_file = file_instruction == nil
    and type(workspace.resolved_instruction) == "string"
    and trim(workspace.resolved_instruction) ~= ""
  local instruction_ok, instruction_error =
    runtime:write_instruction_file(workspace.project_root, workspace.safe_name, workspace.resolved_instruction)
  if not instruction_ok then
    if created then
      runtime:kill_tmux_window(window_id)
    end
    runtime:delete_launch_script(launch_script)
    if creating_worktree then
      local cleanup_ok, cleanup_error = runtime:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
      if cleanup_ok == false then
        return nil, tostring(instruction_error) .. "; cleanup failed: " .. tostring(cleanup_error)
      end
    end
    return nil, instruction_error
  end

  workspace.window_id = window_id
  workspace.window_created = created == true
  if created and not workspace.initial_prompt then
    workspace.codex_status = "idle"
  end
  workspace.status = runtime:dashboard_workspace_status(workspace, window_id)
  if created and workspace.initial_prompt then
    workspace.status = "active"
    workspace.codex_status = "working"
    workspace.codex_mode = workspace.initial_mode == "plan" and "plan" or workspace.codex_mode
  elseif workspace.status ~= "active" then
    if workspace.status == "question" then
      workspace.codex_status = "question"
    else
      workspace.codex_status = "idle"
    end
  end
  if inactive_like_status(workspace.status) then
    workspace.codex_mode = nil
  end
  local had_initial_prompt = workspace.initial_prompt ~= nil
  workspace.initial_prompt = nil
  local previous_project = vim.deepcopy(project)
  project.workspaces[workspace.safe_name] = runtime:state_record(workspace, existing)
  project.updated_at = runtime:timestamp()

  local write_ok, write_error = runtime:write_state(state_data)
  if not write_ok then
    if created then
      runtime:kill_tmux_window(window_id)
    end
    runtime:delete_launch_script(launch_script)
    if wrote_new_instruction_file then
      runtime:delete_instruction_file(workspace.project_root, workspace.safe_name)
    end
    if creating_worktree then
      local cleanup_ok, cleanup_error = runtime:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
      if cleanup_ok == false then
        return nil, tostring(write_error) .. "; cleanup failed: " .. tostring(cleanup_error)
      end
    end
    return nil, write_error
  end

  local should_verify_launch = created == true
    and (opts.verify_launch == true or had_initial_prompt or type(workspace.mission_id) == "string")
  if should_verify_launch then
    local verify_ok, verify_error = runtime:verify_workspace_launch(workspace, {
      attempts = opts.launch_verify_attempts,
      sleep_ms = opts.launch_verify_sleep_ms,
      require_codex = opts.require_codex_ready == true,
    })
    if not verify_ok then
      if creating_worktree then
        state_data.projects[root] = previous_project
        runtime:write_state(state_data)
        runtime:kill_tmux_window(window_id)
        runtime:delete_launch_script(launch_script)
        if wrote_new_instruction_file then
          runtime:delete_instruction_file(workspace.project_root, workspace.safe_name)
        end
        local cleanup_ok, cleanup_error = runtime:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
        if cleanup_ok == false then
          return nil, tostring(verify_error or "workspace did not become ready") .. "; cleanup failed: " .. tostring(cleanup_error)
        end
      else
        local current_project = runtime:project_state(state_data, root)
        local record = current_project.workspaces[workspace.safe_name]
        if type(record) == "table" then
          record.status = "inactive"
          record.codex_status = "idle"
          record.codex_mode = nil
          record.tmux_target = nil
          record.last_reconciled_at = runtime:timestamp()
          current_project.updated_at = record.last_reconciled_at
          runtime:write_state(state_data)
        end
        if created then
          runtime:kill_tmux_window(window_id)
        end
        runtime:delete_launch_script(launch_script)
      end
      return nil, verify_error or "workspace did not become ready"
    end
  end

  return workspace, nil
end

function M.preflight_mission(runtime, mission)
  mission = type(mission) == "table" and mission or {}
  if type(mission.roles) ~= "table" or #mission.roles == 0 then
    return false, "Mission requires at least one role"
  end
  if not runtime:workspaces_enabled() then
    return false, "Codux workspaces are disabled"
  end
  if vim.fn.executable(runtime:tmux_cmd()) ~= 1 then
    return false, "tmux not found on PATH"
  end

  local session = runtime:current_tmux_session()
  if not session then
    return false, "no tmux session running"
  end

  local context = runtime:target_context()
  local base_root = context.root
  local clean, clean_error = runtime:git_checkout_clean(base_root)
  if not clean then
    return false, clean_error
  end

  local state_data = runtime:read_state()
  local projects = type(state_data) == "table" and type(state_data.projects) == "table" and state_data.projects or {}
  local role_specs, spec_error = mission_role_specs(runtime, mission, base_root)
  if not role_specs then
    return false, spec_error
  end
  for _, spec in ipairs(role_specs) do
    local safe_name = spec.safe_name
    local worktree_path = spec.worktree_path
    local project = type(projects[worktree_path]) == "table" and projects[worktree_path] or nil
    local workspaces = type(project) == "table" and type(project.workspaces) == "table" and project.workspaces or nil
    if type(workspaces) == "table" and type(workspaces[safe_name]) == "table" then
      return false, "workspace already exists: " .. safe_name
    end
    if runtime.target_path_exists(worktree_path) then
      return false, "worktree path already exists: " .. worktree_path
    end
    local branch, branch_error = runtime:resolve_worktree_branch(base_root, safe_name)
    if not branch then
      return false, branch_error
    end
    if runtime:tmux_window_id(session, runtime.workspace_window_name(safe_name)) then
      return false, "tmux window already exists: " .. safe_name
    end
    local instruction_path = runtime:instruction_file_path(worktree_path, safe_name)
    if instruction_path and vim.fn.filereadable(instruction_path) == 1 then
      return false, "workspace instruction already exists: " .. instruction_path
    end
  end

  return true, nil, role_specs
end

function M.create_mission(runtime, mission_or_name, objective, opts)
  opts = type(opts) == "table" and opts or {}
  local mission = mission_or_name
  local error_message = nil
  if type(mission_or_name) ~= "table" or type(mission_or_name.roles) ~= "table" then
    mission, error_message = mission_mod.plan(mission_or_name, objective, opts)
  end
  if not mission then
    runtime.notify(error_message or "Failed to plan Codux mission", vim.log.levels.ERROR)
    return false
  end

  local preflight_ok, preflight_error, role_specs = runtime:preflight_mission(mission)
  if not preflight_ok then
    runtime.notify(preflight_error or "Codux mission preflight failed", vim.log.levels.ERROR)
    return false
  end

  local created = {}
  local context = runtime:target_context()
  local base_root = context.root
  local spec_error = nil
  if type(role_specs) ~= "table" then
    role_specs, spec_error = mission_role_specs(runtime, mission, base_root)
  end
  if not role_specs then
    runtime.notify(spec_error or "Codux mission preflight failed", vim.log.levels.ERROR)
    return false
  end
  for _, spec in ipairs(role_specs) do
    local role = spec.role
    local workspace, workspace_error = runtime:prepare_workspace(role.workspace_name, {
      custom_instruction = role.instruction,
      resolved_instruction = role.instruction,
      initial_prompt = role.initial_prompt,
      initial_mode = "plan",
      agent_provider = providers.normalize_provider(role.agent_provider)
        or providers.normalize_provider(mission.agent_provider)
        or (type(runtime.agent_provider) == "function" and runtime:agent_provider() or "codex"),
      permission_profile = "auto",
      worktree_path = spec.worktree_path,
      mission_id = mission.mission_id,
      mission_name = mission.name,
      mission_role = role.name,
      mission_objective = mission.objective,
      mission_focus_packet = mission.focus_packet,
    })
    if not workspace then
      for index = #created, 1, -1 do
        runtime:delete_saved_workspace(created[index])
      end
      runtime.notify(workspace_error or "Failed to launch Codux mission", vim.log.levels.ERROR)
      return false
    end
    table.insert(created, workspace)
  end

  if runtime.state.workspace_manager_project_root then
    runtime.render_workspace_manager()
  end
  runtime.notify("Launched Codux mission " .. tostring(mission.name) .. " with " .. tostring(#created) .. " roles")
  return true
end

return M
