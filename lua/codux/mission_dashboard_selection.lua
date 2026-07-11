local M = {}

function M.selected_row(controller)
  if controller.state.mission_dashboard.selected_row then
    return controller.state.mission_dashboard.selected_row
  end

  if controller.state.mission_dashboard.best_match_row then
    return controller.state.mission_dashboard.best_match_row
  end

  if not controller.is_valid_win(controller.state.mission_dashboard.win) then
    return nil
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, controller.state.mission_dashboard.win)
  return ok and cursor[1] or nil
end

function M.selected_item(controller)
  local row = controller:selected_row()
  if not row then
    return nil
  end
  return controller.state.mission_dashboard.items and controller.state.mission_dashboard.items[row] or nil
end

function M.selected_selectable_item(controller)
  local row = controller:selected_row()
  if not row then
    return nil
  end

  local selectable = controller.state.mission_dashboard.selectable_rows or {}
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

  return controller.state.mission_dashboard.items and controller.state.mission_dashboard.items[row] or nil
end

function M.mission_list_focus_row(controller)
  local rows = controller.state.mission_dashboard.selectable_rows or {}
  if #rows == 0 then
    return 1
  end

  local selected = controller.state.mission_dashboard.selected_row or controller.state.mission_dashboard.best_match_row
  for _, row in ipairs(rows) do
    if row == selected then
      return row
    end
  end
  return rows[1]
end

function M.focus_mission_list(controller)
  if not controller.is_valid_win(controller.state.mission_dashboard.win) then
    return false
  end

  controller.state.mission_dashboard.focus_match = false
  if controller.is_valid_win(controller.state.mission_dashboard.command_win) then
    return controller.set_current_win(controller.state.mission_dashboard.command_win)
  end
  return controller.set_current_win(controller.state.mission_dashboard.win)
end

function M.move_mission_selection(controller, delta)
  if not controller.is_valid_win(controller.state.mission_dashboard.win) then
    return false
  end

  local rows = controller.state.mission_dashboard.selectable_rows or {}
  if #rows == 0 then
    return false
  end

  local current = controller.state.mission_dashboard.selected_row
    or controller.state.mission_dashboard.best_match_row
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
  local preview_anchor = controller:capture_stationary_output_preview_anchor()
  controller.state.mission_dashboard.selected_row = next_row
  controller.state.mission_dashboard.search_confirmed = true
  controller.state.mission_dashboard.focus_match = false

  controller:render_dashboard({ stationary_preview_anchor = preview_anchor })
  return true
end

return M
