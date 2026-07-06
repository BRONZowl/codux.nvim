local M = {}

local function window_info(win)
  if type(vim.fn.getwininfo) ~= "function" then
    return nil
  end
  local ok, info = pcall(vim.fn.getwininfo, win)
  info = ok and type(info) == "table" and info[1] or nil
  return type(info) == "table" and info or nil
end

local function restore_topline(win, topline)
  if type(vim.fn.win_execute) ~= "function" then
    return false
  end
  return pcall(vim.fn.win_execute, win, "call winrestview({'topline': " .. tostring(topline) .. "})")
end

function M.reveal_window_row(win, row)
  row = tonumber(row)
  if type(win) ~= "number" or type(row) ~= "number" or row < 1 then
    return false
  end

  local info = window_info(win)
  if not info then
    return false
  end

  local top = tonumber(info.topline) or 1
  local bottom = tonumber(info.botline) or top
  if row >= top and row <= bottom then
    return true
  end

  local height = tonumber(info.height) or math.max(1, bottom - top + 1)
  local next_top = row < top and row or math.max(1, row - height + 1)
  local ok = restore_topline(win, next_top)
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

function M.capture_output_preview_anchor(controller)
  local row = M.output_preview_row(controller)
  if not row or row ~= controller.state.mission_dashboard_selected_row then
    return nil
  end
  local win = controller.state.mission_dashboard_win
  if not controller.is_valid_win(win) then
    return nil
  end

  local info = window_info(win)
  if not info then
    return nil
  end

  local top = tonumber(info.topline) or 1
  local bottom = tonumber(info.botline) or top
  if row < top or row > bottom then
    return nil
  end

  local key = controller:output_entry_key(controller.state.mission_dashboard_output_entry)
  if key == "" then
    return nil
  end

  return {
    key = key,
    row = row,
    offset = math.max(0, row - top),
    win = win,
  }
end

function M.restore_output_preview_anchor(controller, anchor)
  if type(anchor) ~= "table" then
    return false
  end
  local row = M.output_preview_row(controller)
  if not row or row ~= anchor.row or row ~= controller.state.mission_dashboard_selected_row then
    return false
  end
  if controller:output_entry_key(controller.state.mission_dashboard_output_entry) ~= anchor.key then
    return false
  end
  local win = controller.state.mission_dashboard_win
  if win ~= anchor.win or not controller.is_valid_win(win) then
    return false
  end

  local info = window_info(win)
  if not info then
    return false
  end

  local height = math.max(1, tonumber(info.height) or 1)
  local offset = math.max(0, math.min(tonumber(anchor.offset) or 0, height - 1))
  local top = math.max(1, row - offset)
  return restore_topline(win, top)
end

function M.capture_stationary_output_preview_anchor(controller)
  local anchor = M.capture_output_preview_anchor(controller)
  if not anchor then
    return nil
  end

  local item = controller.state.mission_dashboard_items and controller.state.mission_dashboard_items[anchor.row] or nil
  if
    type(item) ~= "table"
    or item.kind ~= "role"
    or not controller:dashboard_workspace_preview_active(item.entry)
  then
    return nil
  end

  return anchor
end

function M.restore_stationary_output_preview_anchor(controller, anchor)
  if type(anchor) ~= "table" then
    return false
  end

  local row = M.output_preview_row(controller)
  if not row or row ~= controller.state.mission_dashboard_selected_row then
    return false
  end

  local item = controller.state.mission_dashboard_items and controller.state.mission_dashboard_items[row] or nil
  if
    type(item) ~= "table"
    or item.kind ~= "role"
    or not controller:dashboard_workspace_preview_active(item.entry)
  then
    return false
  end

  local win = controller.state.mission_dashboard_win
  if win ~= anchor.win or not controller.is_valid_win(win) then
    return false
  end

  local info = window_info(win)
  if not info then
    return false
  end

  local height = math.max(1, tonumber(info.height) or 1)
  local offset = math.max(0, math.min(tonumber(anchor.offset) or 0, height - 1))
  local top = math.max(1, row - offset)
  return restore_topline(win, top)
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
