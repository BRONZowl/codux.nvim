local action_palette = require("codux.action_palette")
local workspace_actions = require("codux.mission_dashboard_workspace_actions")

local M = {}

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
  return action_palette.palette_width(controller:window_width() or 58)
end

function M.action_palette_config(controller, target, item_count, kind)
  local dashboard_config = controller.is_valid_win(controller.state.mission_dashboard.win)
      and controller.get_window_config(controller.state.mission_dashboard.win)
    or {}
  local dashboard_width = controller:window_width() or 58
  local width = controller:action_palette_width()
  local title = target and (target.name or target.safe_name or target.mission_role or target.mission_id) or "item"
  local prefix = kind == "workspace" and " Codux workspace: " or " Codux mission: "
  local title_width = kind == "workspace" and width - 19 or width - 17

  return action_palette.centered_window_config({
    dashboard_width = dashboard_width,
    dashboard_height = controller:window_height() or math.max(1, item_count or 1),
    col = type(dashboard_config.col) == "number" and dashboard_config.col or nil,
    row = type(dashboard_config.row) == "number" and dashboard_config.row or nil,
    width = width,
    height = math.max(1, item_count or 1),
    title = prefix .. controller.workspace_ui.truncate_display_tail(title, title_width) .. " ",
  })
end

function M.render_action_palette(controller)
  return controller:action_palette_controller():render(nil, controller.state.mission_dashboard.action_kind)
end

local function edit_selected_mission_text(controller, mission, opts)
  opts = type(opts) == "table" and opts or {}
  local root = controller.state.mission_dashboard.project_root or controller.project_root()
  mission = mission or controller:selected_mission()
  if not mission then
    controller.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  return controller:open_objective_editor(mission.name, opts.value(mission), {
    title = opts.title,
    footer = " Ctrl-s/:w save | Ctrl-q cancel ",
    on_save = function(_, value)
      local ok = opts.update(mission.name, value, root)
      if ok ~= false then
        vim.schedule(function()
          controller:refresh_loaded_dashboard(root)
        end)
      end
      return ok
    end,
  })
end

function M.edit_selected_mission(controller, mission)
  return edit_selected_mission_text(controller, mission, {
    title = " Edit Codux Mission Objective ",
    value = function(selected)
      return selected.objective
    end,
    update = controller.update_mission_objective,
  })
end

function M.edit_selected_mission_focus(controller, mission)
  return edit_selected_mission_text(controller, mission, {
    title = " Edit Codux Mission Focus ",
    value = function(selected)
      return selected.focus_packet or ""
    end,
    update = controller.update_mission_focus_packet,
  })
end

function M.delete_selected_mission(controller, mission)
  local root = controller.state.mission_dashboard.project_root or controller.project_root()
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
  local root = controller.state.mission_dashboard.project_root or controller.project_root()
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
  local root = controller.state.mission_dashboard.project_root or controller.project_root()
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
  if controller.state.mission_dashboard.action_kind == "workspace" then
    return controller.state.mission_dashboard.action_workspace
  end
  return controller.state.mission_dashboard.action_mission
end

function M.run_workspace_action(controller, action, target)
  return workspace_actions.run_workspace_action(controller, action, target)
end

function M.run_mission_action(controller, action, target)
  if action == "create_mission" then
    controller:close_action_palette()
    return controller:create_new_mission()
  end
  local mission = target or controller.state.mission_dashboard.action_mission or controller:selected_mission_or_notify()
  if not mission then
    return false
  end

  if action == "edit_objective" then
    controller:close_action_palette()
    return controller:edit_selected_mission(mission)
  end
  if action == "edit_focus" then
    controller:close_action_palette()
    return controller:edit_selected_mission_focus(mission)
  end
  if action == "start_mission" then
    controller:close_action_palette()
    return controller:start_selected_mission(mission)
  end
  if action == "process_dispatch" then
    controller:close_action_palette()
    return M.process_selected_mission_dispatch(controller, mission)
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

function M.process_selected_mission_dispatch(controller, mission)
  mission = type(mission) == "table" and mission or nil
  local root = controller.state.mission_dashboard.project_root or controller.project_root()
  if type(controller.process_mission_dispatch) ~= "function" then
    controller.notify("Mission dispatch is unavailable", vim.log.levels.ERROR)
    return false
  end
  local summary = controller.process_mission_dispatch({
    project_root = root,
    missions = mission and { mission } or nil,
  })
  M.record_dispatch_summary(controller, summary)
  if type(summary) ~= "table" then
    controller.notify("Mission dispatch processing failed", vim.log.levels.ERROR)
    return false
  end
  if (summary.processed or 0) == 0 then
    controller.notify("No pending mission dispatch actions")
  else
    controller.notify(
      string.format(
        "Dispatched %d action(s) (%d ok, %d failed)",
        tonumber(summary.processed) or 0,
        tonumber(summary.succeeded) or 0,
        tonumber(summary.failed) or 0
      ),
      (summary.failed or 0) > 0 and vim.log.levels.WARN or vim.log.levels.INFO
    )
  end
  if type(controller.refresh_loaded_dashboard) == "function" then
    controller:refresh_loaded_dashboard(root)
  elseif type(controller.render_dashboard) == "function" then
    controller:render_dashboard()
  end
  return true
end

function M.record_dispatch_summary(controller, summary)
  if type(controller.state) ~= "table" or type(summary) ~= "table" then
    return
  end
  local util = require("codux.util")
  controller.state.mission_dashboard.last_dispatch = {
    processed = tonumber(summary.processed) or 0,
    succeeded = tonumber(summary.succeeded) or 0,
    failed = tonumber(summary.failed) or 0,
    at_ms = util.now_ms(),
    mission = summary.missions
        and summary.missions[1]
        and summary.missions[1].mission
      or nil,
  }
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

M.selected_role_workspace_or_notify = workspace_actions.selected_role_workspace_or_notify
M.mission_context_for_workspace = workspace_actions.mission_context_for_workspace
M.open_workspace_prompt = workspace_actions.open_workspace_prompt
M.workspace_question_pending = workspace_actions.workspace_question_pending
M.open_workspace_question_answer = workspace_actions.open_workspace_question_answer
M.open_question_option_input = workspace_actions.open_question_option_input
M.open_question_note_input = workspace_actions.open_question_note_input
M.open_workspace_prompt_input = workspace_actions.open_workspace_prompt_input
M.interrupt_workspace_action = workspace_actions.interrupt_workspace_action
M.interrupt_selected_workspace = workspace_actions.interrupt_selected_workspace
M.switch_selected_workspace_mode = workspace_actions.switch_selected_workspace_mode
M.switch_selected_workspace_profile = workspace_actions.switch_selected_workspace_profile
M.rename_selected_role = workspace_actions.rename_selected_role
M.delete_role_workspace = workspace_actions.delete_role_workspace

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
