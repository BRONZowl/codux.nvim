local M = {}

function M.reveal_window_row(win, row)
  row = tonumber(row)
  if type(win) ~= "number" or type(row) ~= "number" or row < 1 then
    return false
  end

  local info = vim.fn.getwininfo(win)[1]
  if type(info) ~= "table" then
    return false
  end

  local top = tonumber(info.topline) or 1
  local bottom = tonumber(info.botline) or top
  if row >= top and row <= bottom then
    return true
  end

  local height = tonumber(info.height) or math.max(1, bottom - top + 1)
  local next_top = row < top and row or math.max(1, row - height + 1)
  local ok = pcall(vim.fn.win_execute, win, "call winrestview({'topline': " .. tostring(next_top) .. "})")
  return ok
end

function M.output_preview_row(controller)
  if not controller:output_preview_running() then
    return nil
  end

  local entry = controller.state.mission_dashboard_output_entry
  local key = controller:output_entry_key(entry)
  if key == "" then
    return nil
  end

  for row, item in pairs(controller.state.mission_dashboard_items or {}) do
    if type(item) == "table" and item.kind == "role" and controller:output_entry_key(item.entry) == key then
      return row
    end
  end
  return nil
end

function M.reveal_output_preview_row(controller)
  local row = M.output_preview_row(controller)
  if not row or row ~= controller.state.mission_dashboard_selected_row then
    return false
  end
  if not controller.is_valid_win(controller.state.mission_dashboard_win) then
    return false
  end
  return controller.reveal_window_row(controller.state.mission_dashboard_win, row)
end

return M
