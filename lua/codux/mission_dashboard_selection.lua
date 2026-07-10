local M = {}

function M.selected_row(controller)
  if controller.state.mission_dashboard_selected_row then
    return controller.state.mission_dashboard_selected_row
  end

  if controller.state.mission_dashboard_best_match_row then
    return controller.state.mission_dashboard_best_match_row
  end

  if not controller.is_valid_win(controller.state.mission_dashboard_win) then
    return nil
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, controller.state.mission_dashboard_win)
  return ok and cursor[1] or nil
end

function M.selected_item(controller)
  local row = controller:selected_row()
  if not row then
    return nil
  end
  return controller.state.mission_dashboard_items and controller.state.mission_dashboard_items[row] or nil
end

function M.selected_selectable_item(controller)
  local row = controller:selected_row()
  if not row then
    return nil
  end

  local selectable = controller.state.mission_dashboard_selectable_rows or {}
  local found = false
  for _, selectable_row in ipairs(selectable) do
    if selectable_row == row then
      found = true
      break
    end
  end
  if not found then
    return nil
  end

  return controller.state.mission_dashboard_items and controller.state.mission_dashboard_items[row] or nil
end

function M.mission_list_focus_row(controller)
  local rows = controller.state.mission_dashboard_selectable_rows or {}
  if #rows == 0 then
    return 1
  end

  local selected = controller.state.mission_dashboard_selected_row or controller.state.mission_dashboard_best_match_row
  for _, row in ipairs(rows) do
    if row == selected then
      return row
    end
  end
  return rows[1]
end

function M.focus_mission_list(controller)
  if not controller.is_valid_win(controller.state.mission_dashboard_win) then
    return false
  end

  controller.state.mission_dashboard_focus_match = false
  if controller.is_valid_win(controller.state.mission_dashboard_command_win) then
    return controller.set_current_win(controller.state.mission_dashboard_command_win)
  end
  return controller.set_current_win(controller.state.mission_dashboard_win)
end

function M.move_mission_selection(controller, delta)
  if not controller.is_valid_win(controller.state.mission_dashboard_win) then
    return false
  end

  local rows = controller.state.mission_dashboard_selectable_rows or {}
  if #rows == 0 then
    return false
  end

  local current = controller.state.mission_dashboard_selected_row
    or controller.state.mission_dashboard_best_match_row
    or controller:selected_row()
    or rows[1]
  local current_index = 1
  for index, row in ipairs(rows) do
    if row >= current then
      current_index = index
      break
    end
  end

  local next_index = math.max(1, math.min(#rows, current_index + (tonumber(delta) or 0)))
  local next_row = rows[next_index]
  local previous_provider = controller.state.mission_dashboard_token_usage_provider
  local preview_anchor = controller:capture_stationary_output_preview_anchor()
  controller.state.mission_dashboard_selected_row = next_row
  controller.state.mission_dashboard_search_confirmed = true
  controller.state.mission_dashboard_focus_match = false

  local force_token = false
  if type(controller.dashboard_token_agent_provider) == "function" then
    local next_provider = controller:dashboard_token_agent_provider()
    if previous_provider and next_provider and previous_provider ~= next_provider then
      force_token = true
    end
  end
  if force_token and type(controller.refresh_dashboard_token_usage) == "function" then
    controller:refresh_dashboard_token_usage(true)
    controller:render_dashboard({ stationary_preview_anchor = preview_anchor, skip_token_refresh = true })
  else
    controller:render_dashboard({ stationary_preview_anchor = preview_anchor })
  end
  return true
end

return M
