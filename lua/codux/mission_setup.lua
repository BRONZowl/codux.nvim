local mission_control_mod = require("codux.mission_control")

local M = {}

function M.new(deps)
  deps = type(deps) == "table" and deps or {}
  local codux = deps.codux or {}
  local workspace_runtime = deps.workspace_runtime

  return mission_control_mod.new({
    state = deps.state,
    mission = deps.mission,
    ui = deps.ui,
    workspace_ui = deps.workspace_ui,
    is_valid_win = deps.is_valid_win,
    is_loaded_buf = deps.is_loaded_buf,
    window_buffer = deps.window_buffer,
    buffer_filetype = deps.buffer_filetype,
    notify = deps.notify,
    token_usage_label = deps.token_usage_label,
    refresh_token_usage = deps.refresh_token_usage,
    token_usage_refresh_ms = deps.token_usage_refresh_ms,
    create_mission = function(mission)
      return codux.create_mission(mission)
    end,
    doctor = type(deps.doctor) == "function" and deps.doctor
      or function()
        if type(codux.doctor) == "function" then
          return codux.doctor()
        end
      end,
    create_workspace_prompt = function(opts)
      return codux.open_workspace_prompt(opts)
    end,
    select_provider_profile = function(opts)
      return codux._v5.select_keyed_provider_profile(opts)
    end,
    default_agent_provider = type(deps.default_agent_provider) == "function" and deps.default_agent_provider or nil,
    update_mission_objective = function(name, objective, root)
      return codux.update_mission_objective(name, objective, { project_root = root })
    end,
    update_mission_focus_packet = function(name, focus_packet, root)
      return codux.update_mission_focus_packet(name, focus_packet, { project_root = root })
    end,
    rename_mission_role = function(entry, new_name, root)
      local ok, error_message = workspace_runtime:rename_mission_role(entry, new_name, { project_root = root })
      if not ok and error_message then
        return false, error_message
      end
      return ok
    end,
    mission_dirty_roles = function(name, root)
      return workspace_runtime:mission_dirty_roles(name, { project_root = root })
    end,
    workspace_branch_state = function(entry)
      return workspace_runtime:workspace_branch_state(entry)
    end,
    start_mission = function(name, root, opts)
      opts = type(opts) == "table" and vim.deepcopy(opts) or {}
      opts.project_root = root
      return codux.start_mission(name, opts)
    end,
    close_mission = function(name, root)
      return codux.close_mission(name, { project_root = root })
    end,
    delete_mission = function(name, root)
      return codux.delete_mission(name, { project_root = root })
    end,
    missions_for_project = function(root)
      local _, reconcile_error = workspace_runtime:reconcile_moved_worktrees_for_project(root)
      if reconcile_error then
        return {}, reconcile_error
      end
      return workspace_runtime:missions_for_project(root)
    end,
    mission_residue_for_project = function(root)
      return workspace_runtime:mission_residue_for_project(root)
    end,
    cleanup_mission_residue = function(root)
      return workspace_runtime:cleanup_mission_residue(root)
    end,
    workspace_entries_for_project = deps.workspace_entries_for_project,
    edit_saved_workspace_instruction = deps.edit_saved_workspace_instruction,
    start_saved_workspace = function(entry, opts)
      if type(deps.start_saved_workspace) == "function" then
        return deps.start_saved_workspace(entry, opts)
      end
      return workspace_runtime:start_saved_workspace(entry, opts)
    end,
    delete_saved_workspace = deps.delete_saved_workspace,
    close_saved_workspace_window = function(entry)
      return codux._v5.close_saved_workspace_window(entry)
    end,
    workspace_interactive_preview = function(entry, opts)
      return workspace_runtime:workspace_interactive_preview(entry, opts)
    end,
    reconcile_workspace_entry = function(entry)
      local updated, _, error_message = workspace_runtime:reconcile_moved_worktree(entry)
      if error_message then
        return nil, error_message
      end
      return updated or entry, nil
    end,
    close_workspace_interactive_preview = function(preview)
      return workspace_runtime:close_workspace_interactive_preview(preview)
    end,
    send_prompt_to_workspace = function(entry, prompt)
      local ok, error_message = workspace_runtime:send_prompt_to_workspace(entry, prompt)
      if not ok and error_message then
        return false, error_message
      end
      return ok
    end,
    process_mission_dispatch = function(opts)
      opts = type(opts) == "table" and opts or {}
      if type(opts.project_root) ~= "string" or opts.project_root == "" then
        local dashboard = type(deps.state) == "table" and deps.state.mission_dashboard or nil
        opts.project_root = (type(dashboard) == "table" and dashboard.project_root)
          or (type(deps.project_root) == "function" and deps.project_root())
          or workspace_runtime:project_root()
      end
      return workspace_runtime:process_mission_dispatch(opts)
    end,
    select_workspace_question_option = function(entry, option, opts)
      local ok, error_message = workspace_runtime:select_workspace_question_option(entry, option, opts)
      if not ok and error_message then
        return false, error_message
      end
      return ok
    end,
    submit_workspace_question_note = function(entry, note, opts)
      local ok, error_message = workspace_runtime:submit_workspace_question_note(entry, note, opts)
      if not ok and error_message then
        return false, error_message
      end
      return ok
    end,
    interrupt_workspace = function(entry)
      local ok, error_message = workspace_runtime:interrupt_workspace(entry)
      if not ok and error_message then
        return false, error_message
      end
      return ok
    end,
    switch_workspace_mode = function(entry)
      local ok, error_message = workspace_runtime:switch_workspace_mode(entry)
      if not ok and error_message then
        return false, error_message
      end
      return ok
    end,
    switch_workspace_profile = deps.switch_workspace_profile,
    project_root = deps.project_root,
    set_buffer_keymap = deps.set_buffer_keymap,
    bind_close_keys = deps.bind_close_keys,
    namespace = deps.namespace,
  })
end

return M
