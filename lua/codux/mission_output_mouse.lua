local M = {}

M.scroll_buttons = {
  ["<ScrollWheelUp>"] = 64,
  ["<ScrollWheelDown>"] = 65,
  ["<ScrollWheelLeft>"] = 66,
  ["<ScrollWheelRight>"] = 67,
}

local function clamp_coordinate(value)
  value = tonumber(value) or 1
  if value < 1 then
    return 1
  end
  return math.floor(value)
end

function M.position(controller)
  local win = controller.state.mission_dashboard.output_win
  local row = nil
  local col = nil

  if type(vim.fn.getmousepos) == "function" then
    local ok, mouse = pcall(vim.fn.getmousepos)
    if ok and type(mouse) == "table" and mouse.winid == win then
      row = mouse.winrow
      col = mouse.wincol
    end
  end

  if row == nil or col == nil then
    local cursor_ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
    if cursor_ok and type(cursor) == "table" then
      row = cursor[1]
      col = (tonumber(cursor[2]) or 0) + 1
    end
  end

  return clamp_coordinate(row), clamp_coordinate(col)
end

function M.sequence(controller, button)
  local row, col = M.position(controller)
  return "\27[<" .. tostring(button) .. ";" .. tostring(col) .. ";" .. tostring(row) .. "M"
end

function M.send(controller, terminal_controller, button)
  if not controller.state.mission_dashboard.output_control then
    return false
  end

  local state = terminal_controller:sync_output_terminal_state()
  if not terminal_controller:terminal_running() or type(state.job_id) ~= "number" or state.job_id <= 0 then
    return false
  end

  local send_ok, sent = pcall(vim.fn.chansend, state.job_id, M.sequence(controller, button))
  return send_ok and sent ~= 0
end

return M
