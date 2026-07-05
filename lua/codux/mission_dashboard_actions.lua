local text_util = require("codux.text")
local ui = require("codux.ui")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.selected_mission(controller)
  local item = controller:selected_item()
  return item and item.mission or nil
end

function M.selected_mission_or_notify(controller)
  local mission = controller:selected_mission()
  if not mission then
    controller.notify("No Codux mission selected", vim.log.levels.WARN)
    return nil
  end
  return mission
end

function M.close_action_palette(controller)
  return controller:action_palette_controller():close()
end

function M.action_palette_width(controller)
  local dashboard_width = controller:window_width() or 58
  return math.min(math.max(32, dashboard_width - 8), 48)
end

function M.action_palette_config(controller, target, item_count, kind)
  local dashboard_config = controller.is_valid_win(controller.state.mission_dashboard_win)
      and controller.get_window_config(controller.state.mission_dashboard_win)
    or {}
  local dashboard_width = controller:window_width() or 58
  local dashboard_height = controller:window_height() or math.max(1, item_count or 1)
  local width = controller:action_palette_width()
  local height = math.max(1, item_count or 1)
  local col = type(dashboard_config.col) == "number"
      and dashboard_config.col
    or math.floor((vim.o.columns - dashboard_width) / 2)
  local row = type(dashboard_config.row) == "number" and dashboard_config.row or 0
  local title = target and (target.name or target.safe_name or target.mission_role or target.mission_id) or "item"
  local prefix = kind == "workspace" and " Codux workspace: " or " Codux mission: "
  local title_width = kind == "workspace" and width - 19 or width - 17

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = prefix .. controller.workspace_ui.truncate_display_tail(title, title_width) .. " ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, col + math.floor((dashboard_width - width) / 2)),
    row = math.max(0, row + math.floor((dashboard_height - height) / 2)),
    zindex = 70,
  }
end

function M.render_action_palette(controller)
  return controller:action_palette_controller():render(nil, controller.state.mission_dashboard_action_kind)
end

function M.edit_selected_mission(controller, mission)
  local root = controller.state.mission_dashboard_project_root or controller.project_root()
  mission = mission or controller:selected_mission()
  if not mission then
    controller.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  return controller:open_objective_editor(mission.name, mission.objective, {
    title = " Edit Codux Mission Objective ",
    footer = " Ctrl-s/:w save | Ctrl-q cancel ",
    on_save = function(_, objective)
      local ok = controller.update_mission_objective(mission.name, objective, root)
      if ok ~= false then
        vim.schedule(function()
          controller:refresh_loaded_dashboard(root)
        end)
      end
      return ok
    end,
  })
end

function M.delete_selected_mission(controller, mission)
  local root = controller.state.mission_dashboard_project_root or controller.project_root()
  mission = mission or controller:selected_mission()
  if not mission then
    controller.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  if not controller:confirm_delete_mission(mission, root) then
    return false
  end
  local ok = controller.delete_mission(mission.name or mission.mission_id, root)
  if ok then
    controller:update_dashboard_after_mission_delete(root)
  end
  return ok
end

function M.close_selected_mission(controller, mission)
  local root = controller.state.mission_dashboard_project_root or controller.project_root()
  mission = mission or controller:selected_mission()
  if not mission then
    controller.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  local ok = controller.close_mission(mission.name or mission.mission_id, root)
  if ok then
    controller:refresh_loaded_dashboard(root)
  end
  return ok
end

function M.start_selected_mission(controller, mission)
  local root = controller.state.mission_dashboard_project_root or controller.project_root()
  mission = mission or controller:selected_mission()
  if not mission then
    controller.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  local ok = controller.start_mission(mission.name or mission.mission_id, root, {
    restart_inactive = true,
    focus_first = false,
  })
  controller:refresh_loaded_dashboard(root)
  return ok
end

function M.action_palette_target(controller)
  if controller.state.mission_dashboard_action_kind == "workspace" then
    return controller.state.mission_dashboard_action_workspace
  end
  return controller.state.mission_dashboard_action_mission
end

function M.run_workspace_action(controller, action, target)
  local workspace = target or controller.state.mission_dashboard_action_workspace
  if action == "open_workspace" then
    return false
  end
  if action == "prompt_workspace" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    return controller:open_workspace_prompt(workspace)
  end
  if action == "answer_question" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    return controller:open_workspace_question_answer(workspace)
  end
  if action == "edit_instructions" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    return controller.edit_saved_workspace_instruction(workspace)
  end
  if action == "close_workspace" then
    workspace = workspace or controller:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    controller:close_action_palette()
    return controller.close_saved_workspace_window(workspace)
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
  return nil
end

function M.run_mission_action(controller, action, target)
  if action == "create_mission" then
    controller:close_action_palette()
    return controller:create_new_mission()
  end
  local mission = target or controller.state.mission_dashboard_action_mission or controller:selected_mission_or_notify()
  if not mission then
    return false
  end

  if action == "edit_objective" then
    controller:close_action_palette()
    return controller:edit_selected_mission(mission)
  end
  if action == "view_objective" then
    controller:close_action_palette()
    return controller:view_mission_objective(mission)
  end
  if action == "start_mission" then
    controller:close_action_palette()
    return controller:start_selected_mission(mission)
  end
  if action == "close_mission" then
    controller:close_action_palette()
    return controller:close_selected_mission(mission)
  end
  if action == "delete_mission" then
    controller:close_action_palette()
    return controller:delete_selected_mission(mission)
  end
  return false
end

function M.run_action(controller, action, target)
  local workspace_result = controller:run_workspace_action(action, target)
  if workspace_result ~= nil then
    return workspace_result
  end
  return controller:run_mission_action(action, target)
end

function M.run_highlighted_action(controller)
  return controller:action_palette_controller():run_highlighted()
end

function M.move_action_cursor(controller, delta)
  return controller:action_palette_controller():move_cursor(delta)
end

function M.open_action_palette_for(controller, target, kind)
  target = type(target) == "table" and target or nil
  if not target then
    return false
  end

  return controller:action_palette_controller():open(target, kind)
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

    local ok, error_message = submit_fn(entry, input)
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
  if entry.status ~= "active" and entry.codex_status ~= "working" then
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

function M.delete_role_workspace(controller, entry)
  if type(entry) ~= "table" then
    return false
  end
  if controller.workspace_ui.confirm_delete_workspace(entry) then
    return controller.delete_saved_workspace(entry)
  end
  return false
end

function M.open_action_palette(controller)
  local item = controller:selected_selectable_item()
  if not item then
    controller.notify("No Codux mission or workspace selected", vim.log.levels.WARN)
    return false
  end
  if item.kind == "mission" then
    return controller:open_action_palette_for(item.mission, "mission")
  end
  if item.kind == "role" then
    return controller:open_action_palette_for(item.entry, "workspace")
  end
  controller.notify("No Codux mission or workspace selected", vim.log.levels.WARN)
  return false
end

return M
