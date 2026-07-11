local M = {}

function M.selected_item(controller)
  if not controller.is_valid_win(controller.state.workspace_manager.win) then
    return nil
  end

  if controller.state.workspace_manager.search_confirmed and controller.state.workspace_manager.selected_index then
    return controller.state.workspace_manager.items[controller.state.workspace_manager.selected_index]
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, controller.state.workspace_manager.win)
  if not ok then
    return nil
  end

  local index = cursor[1] - 1
  return controller.state.workspace_manager.items[index]
end

function M.workspace_list_focus_row(controller)
  if #controller.state.workspace_manager.items == 0 then
    return 1
  end

  local index = controller.state.workspace_manager.selected_index or controller.state.workspace_manager.best_match_index or 1
  index = math.max(1, math.min(#controller.state.workspace_manager.items, tonumber(index) or 1))
  return 2 + index - 1
end

function M.focus_workspace_list(controller)
  if not controller.is_valid_win(controller.state.workspace_manager.win) then
    return false
  end

  controller.state.workspace_manager.focus_match = false
  controller.set_window_cursor(controller.state.workspace_manager.win, { controller:workspace_list_focus_row(), 0 })
  return controller.set_current_win(controller.state.workspace_manager.win)
end

function M.move_workspace_selection(controller, delta)
  if not controller.is_valid_win(controller.state.workspace_manager.win) then
    return false
  end

  local count = #controller.state.workspace_manager.items
  if count == 0 then
    return false
  end

  local current_index = controller.state.workspace_manager.selected_index
    or controller.state.workspace_manager.best_match_index
    or controller:workspace_list_focus_row() - 1
  local next_index = math.max(1, math.min(count, (tonumber(current_index) or 1) + (tonumber(delta) or 0)))
  controller.state.workspace_manager.selected_index = next_index
  controller.state.workspace_manager.search_confirmed = true
  controller.state.workspace_manager.focus_match = false
  controller:render()
  controller.set_window_cursor(controller.state.workspace_manager.win, { 2 + next_index - 1, 0 })
  return true
end

return M
