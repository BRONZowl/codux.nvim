local text_util = require("codux.text")
local mission_mod = require("codux.mission")
local providers = require("codux.providers")
local ui = require("codux.ui")

local M = {}

local trim = text_util.trim

local function profile_label(choice)
  return choice.profile_label or (providers.provider_label(choice.agent_provider) .. " " .. providers.profile_label(choice.profile))
end

local function open_profile_picker(controller, entry)
  entry = type(entry) == "table" and entry or nil
  if not entry then
    return false
  end

  local label = entry.mission_role or entry.name or entry.safe_name or "workspace"
  if type(controller.select_provider_profile) ~= "function" then
    controller.notify("Codux profile picker is unavailable", vim.log.levels.ERROR)
    return false
  end

  return controller.select_provider_profile({
    provider_title = " Profile " .. tostring(label) .. " agent ",
    provider_filetype = "codux-mission-workspace-provider",
    provider_zindex = 85,
    provider_cancel_desc = "Cancel Codux Profile",
    provider_create_error = "Failed to create Codux profile menu",
    provider_open_error = "Failed to open Codux profile menu",
    profile_title = " Profile " .. tostring(label) .. " ",
    profile_filetype = "codux-mission-workspace-profile",
    profile_zindex = 86,
    profile_cancel_desc = "Cancel Codux Profile",
    profile_create_error = "Failed to create Codux profile menu",
    profile_open_error = "Failed to open Codux profile menu",
    on_select = function(choice)
      if type(choice) ~= "table" then
        return false
      end

      local ok, error_message, restarted = controller.switch_workspace_profile(entry, choice.agent_provider, choice.profile, {
        restart = true,
      })
      if ok then
        if restarted and type(controller.invalidate_output_preview_for_entry) == "function" then
          controller:invalidate_output_preview_for_entry(entry)
        end
        controller.notify(
          "Switched Codux workspace "
            .. tostring(label)
            .. " to "
            .. profile_label(choice)
            .. (restarted and " and restarted it" or "")
        )
        -- Refresh usage for the newly selected agent profile, bypassing throttle.
        if type(controller.refresh_dashboard_token_usage) == "function" then
          controller:refresh_dashboard_token_usage(true, { agent_provider = choice.agent_provider })
        end
        controller:render_dashboard({ skip_token_refresh = true })
        if restarted and type(controller.retry_output_preview_for_entry) == "function" then
          controller:retry_output_preview_for_entry(entry)
        end
        return true
      end
      controller.notify(error_message or "Failed to switch Codux workspace profile", vim.log.levels.ERROR)
      return false
    end,
  })
end

function M.run_workspace_action(controller, action, target)
  local workspace = target or controller.state.mission_dashboard_action_workspace
  if action == "start_workspace" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    local root = workspace.project_root or controller.state.mission_dashboard_project_root or controller.project_root()
    local ok = controller.start_saved_workspace(workspace)
    -- Match profile-restart: clear blocked inactive preview, refresh, then retry attach.
    if ok and type(controller.invalidate_output_preview_for_entry) == "function" then
      controller:invalidate_output_preview_for_entry(workspace)
    end
    if type(controller.refresh_loaded_dashboard) == "function" then
      controller:refresh_loaded_dashboard(root)
    end
    if ok and type(controller.retry_output_preview_for_entry) == "function" then
      controller:retry_output_preview_for_entry(workspace)
    end
    return ok
  end
  if action == "rename_role" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    return controller:rename_selected_role(workspace)
  end
  if action == "edit_instructions" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    return controller.edit_saved_workspace_instruction(workspace)
  end
  if action == "switch_profile" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    return controller:switch_selected_workspace_profile(workspace)
  end
  if action == "close_workspace" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    local root = workspace.project_root or controller.state.mission_dashboard_project_root or controller.project_root()
    local ok = controller.close_saved_workspace_window(workspace)
    -- Tear down stale output attach and refresh status immediately (do not wait on monitor tick).
    if ok and type(controller.invalidate_output_preview_for_entry) == "function" then
      controller:invalidate_output_preview_for_entry(workspace)
    end
    if type(controller.refresh_loaded_dashboard) == "function" then
      controller:refresh_loaded_dashboard(root)
    end
    return ok
  end
  if action == "delete_workspace" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    return controller:delete_role_workspace(workspace)
  end
  if action == "create_workspace" then
    controller:close_action_palette()
    return controller:create_new_workspace(workspace)
  end
  if action == "prompt_role" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    return controller:open_workspace_prompt(workspace)
  end
  return nil
end

function M.selected_role_workspace_or_notify(controller)
  local item = controller:selected_selectable_item()
  if not item or item.kind ~= "role" or type(item.entry) ~= "table" then
    controller.notify("No Codux workspace selected", vim.log.levels.WARN)
    return nil
  end
  return item.entry
end

function M.mission_context_for_workspace(_, entry)
  entry = type(entry) == "table" and entry or nil
  if not entry then
    return nil
  end

  local mission_id = entry.mission_id
  if type(mission_id) ~= "string" or mission_id == "" then
    return nil
  end

  return {
    mission_id = mission_id,
    mission_name = entry.mission_name,
    mission_objective = entry.mission_objective,
    mission_focus_packet = entry.mission_focus_packet,
    agent_provider = entry.agent_provider,
    permission_profile = entry.permission_profile,
  }
end

function M.open_workspace_prompt(controller, entry)
  entry = type(entry) == "table" and entry or controller:selected_role_workspace_or_notify()
  if not entry then
    return false
  end

  local label = entry.mission_role or entry.name or entry.safe_name or "workspace"
  if entry.status == "inactive" then
    controller.notify("workspace is inactive", vim.log.levels.WARN)
    return false
  end

  local prompt_fn = controller.ui.single_line_prompt
  if type(prompt_fn) ~= "function" then
    controller.notify("Codux prompt input is unavailable", vim.log.levels.ERROR)
    return false
  end

  return controller:open_workspace_prompt_input(entry, label, controller.send_prompt_to_workspace, "Sent prompt to ")
end

function M.workspace_question_pending(_, entry)
  entry = type(entry) == "table" and entry or {}
  return entry.status ~= "inactive"
end

function M.open_workspace_question_answer(controller, entry)
  entry = type(entry) == "table" and entry or controller:selected_role_workspace_or_notify()
  if not entry then
    return false
  end
  if entry.status == "inactive" then
    controller.notify("workspace is inactive", vim.log.levels.WARN)
    return false
  end

  local label = entry.mission_role or entry.name or entry.safe_name or "workspace"
  return ui.key_choice_menu({
    title = " Answer " .. tostring(label) .. " ",
    filetype = "codux-mission-question-answer",
    zindex = 85,
    choices = {
      { key = "o", action = "option", label = "option", desc = "Send Codux Plan Option" },
      { key = "n", action = "option_note", label = "option + note", desc = "Send Codux Plan Option With Note" },
    },
    create_error = "Failed to create Codux answer menu",
    open_error = "Failed to open Codux answer menu",
    cancel_desc = "Cancel Codux Answer",
  }, function(choice)
    if type(choice) ~= "table" then
      return
    end
    if choice.action == "option_note" then
      controller:open_question_option_input(entry, label, true)
      return
    end
    controller:open_question_option_input(entry, label, false)
  end, {
    notify = controller.notify,
    create_scratch_buffer = controller.ui.create_scratch_buffer,
    set_lines = controller.ui.set_lines,
    set_window_options = controller.ui.set_window_options,
    close_window = controller.ui.close_window,
    delete_buffer = controller.ui.delete_buffer,
    set_buffer_keymap = controller.set_buffer_keymap,
    bind_close_keys = controller.bind_close_keys,
  })
end

function M.open_question_option_input(controller, entry, label, with_note)
  local prompt_fn = controller.ui.single_line_prompt
  if type(prompt_fn) ~= "function" then
    controller.notify("Codux prompt input is unavailable", vim.log.levels.ERROR)
    return false
  end

  label = label or (entry and (entry.mission_role or entry.name or entry.safe_name)) or "workspace"
  return prompt_fn({
    prompt = "Plan option " .. tostring(label) .. ": ",
    filetype = "codux-mission-question-option",
    zindex = 86,
    allowed_chars = "1234",
    max_length = 1,
    on_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })
    end,
  }, function(input)
    local option = trim(input)
    if option == "" then
      controller.notify("Option number is required", vim.log.levels.WARN)
      return
    end
    if not option:match("^[1-4]$") then
      controller.notify("Option number must be 1, 2, 3, or 4", vim.log.levels.WARN)
      return
    end

    local ok, error_message = controller.select_workspace_question_option(entry, option, { with_note = with_note == true })
    if not ok then
      controller.notify(error_message or "Failed to answer question", vim.log.levels.ERROR)
      return
    end
    if with_note == true then
      controller:open_question_note_input(entry, label)
      return
    end
    controller.notify("Answered question for " .. tostring(label))
    controller:render_dashboard()
  end, {
    notify = controller.notify,
    set_buffer_keymap = controller.set_buffer_keymap,
    bind_close_keys = controller.bind_close_keys,
  })
end

function M.open_question_note_input(controller, entry, label)
  local prompt_fn = controller.ui.single_line_prompt
  if type(prompt_fn) ~= "function" then
    controller.notify("Codux prompt input is unavailable", vim.log.levels.ERROR)
    return false
  end

  label = label or (entry and (entry.mission_role or entry.name or entry.safe_name)) or "workspace"
  local function restore_dashboard_focus()
    controller:focus_mission_list()
  end
  return prompt_fn({
    prompt = "Note " .. tostring(label) .. ": ",
    filetype = "codux-mission-question-note",
    zindex = 86,
    insert_input = true,
    on_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })
    end,
  }, function(input)
    local note = trim(input)
    if note == "" then
      controller.notify("Note is required", vim.log.levels.WARN)
      restore_dashboard_focus()
      return
    end

    local ok, error_message = controller.submit_workspace_question_note(entry, note)
    if ok then
      controller.notify("Sent note to " .. tostring(label))
      controller:render_dashboard()
      restore_dashboard_focus()
    else
      controller.notify(error_message or "Failed to send question note", vim.log.levels.ERROR)
      restore_dashboard_focus()
    end
  end, {
    notify = controller.notify,
    set_buffer_keymap = controller.set_buffer_keymap,
    bind_close_keys = controller.bind_close_keys,
  })
end

function M.open_workspace_prompt_input(controller, entry, label, submit_fn, success_prefix)
  entry = type(entry) == "table" and entry or nil
  label = label or (entry and (entry.mission_role or entry.name or entry.safe_name)) or "workspace"
  submit_fn = type(submit_fn) == "function" and submit_fn or controller.send_prompt_to_workspace
  success_prefix = type(success_prefix) == "string" and success_prefix or "Sent prompt to "
  local prompt_fn = controller.ui.single_line_prompt
  if type(prompt_fn) ~= "function" then
    controller.notify("Codux prompt input is unavailable", vim.log.levels.ERROR)
    return false
  end

  return prompt_fn({
    prompt = "Prompt " .. tostring(label) .. ": ",
    filetype = "codux-mission-workspace-prompt",
    zindex = 80,
    on_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })
    end,
  }, function(input)
    if input == nil then
      return
    end
    if trim(input) == "" then
      controller.notify("Prompt is required", vim.log.levels.WARN)
      return
    end

    local prompt = mission_mod.prompt_with_focus_packet(input, entry and entry.mission_focus_packet)
    local ok, error_message = submit_fn(entry, prompt)
    if ok then
      controller.notify(success_prefix .. tostring(label))
      controller:render_dashboard()
    else
      controller.notify(error_message or "Failed to send prompt", vim.log.levels.ERROR)
    end
  end, {
    notify = controller.notify,
    set_buffer_keymap = controller.set_buffer_keymap,
    bind_close_keys = controller.bind_close_keys,
  })
end

function M.interrupt_workspace_action(controller, entry)
  entry = type(entry) == "table" and entry or controller:selected_role_workspace_or_notify()
  if not entry then
    return false
  end
  if entry.status ~= "active" and entry.agent_status ~= "working" then
    return false
  end

  local ok, error_message = controller.interrupt_workspace(entry)
  if not ok then
    controller.notify(error_message or "Failed to interrupt workspace", vim.log.levels.ERROR)
    return false
  end

  local label = entry.mission_role or entry.name or entry.safe_name or "workspace"
  controller.notify("Interrupted " .. tostring(label))
  controller:render_dashboard()
  return true
end

function M.interrupt_selected_workspace(controller, entry)
  entry = type(entry) == "table" and entry or controller:selected_role_workspace_or_notify()
  if not entry then
    return false
  end
  return controller:interrupt_workspace_action(entry)
end

function M.switch_selected_workspace_mode(controller, entry)
  entry = type(entry) == "table" and entry or controller:selected_role_workspace_or_notify()
  if not entry then
    return false
  end

  local ok, error_message = controller.switch_workspace_mode(entry)
  if ok then
    controller.notify("Switched Codux mode for " .. tostring(entry.mission_role or entry.name or entry.safe_name))
    controller:render_dashboard()
    return true
  end

  controller.notify(error_message or "Failed to switch workspace mode", vim.log.levels.ERROR)
  return false
end

function M.switch_selected_workspace_profile(controller, entry)
  entry = type(entry) == "table" and entry or controller:selected_role_workspace_or_notify()
  if not entry then
    return false
  end
  return open_profile_picker(controller, entry)
end

function M.rename_selected_role(controller, entry)
  entry = type(entry) == "table" and entry or controller:selected_role_workspace_or_notify()
  if not entry then
    return false
  end

  local prompt_fn = controller.ui.single_line_prompt
  if type(prompt_fn) ~= "function" then
    controller.notify("Codux prompt input is unavailable", vim.log.levels.ERROR)
    return false
  end

  local current_name = entry.mission_role or entry.name or entry.safe_name or ""
  return prompt_fn({
    prompt = "Rename Codux role: ",
    default = current_name,
    filetype = "codux-mission-role-rename",
    zindex = 80,
    on_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })
    end,
  }, function(input)
    local new_name = trim(input)
    if new_name == "" then
      return
    end

    local root = controller.state.mission_dashboard_project_root or controller.project_root()
    local ok, error_message = controller.rename_mission_role(entry, new_name, root)
    if ok then
      controller.notify("Renamed Codux role to " .. tostring(new_name))
      controller:refresh_loaded_dashboard(root)
      return
    end
    controller.notify(error_message or "Failed to rename Codux role", vim.log.levels.ERROR)
  end, {
    notify = controller.notify,
    set_buffer_keymap = controller.set_buffer_keymap,
    bind_close_keys = controller.bind_close_keys,
  })
end

function M.delete_role_workspace(controller, entry)
  if type(entry) ~= "table" then
    return false
  end
  if controller.workspace_ui.confirm_delete_workspace(entry) then
    return controller.delete_saved_workspace(entry)
  end
  return false
end

return M
