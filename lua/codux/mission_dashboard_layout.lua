local M = {}

local MISSION_CREATION_ZINDEX = 80

local function available_dimension(total, margin)
  return math.max(1, total - margin)
end

local function bordered_float_outer_height(content_height)
  return math.max(1, tonumber(content_height) or 1) + 2
end

local function next_bordered_float_row(row, content_height)
  return math.max(0, tonumber(row) or 0) + bordered_float_outer_height(content_height)
end

local function editor_size()
  return math.max(1, vim.o.columns), math.max(1, vim.o.lines - vim.o.cmdheight)
end

local function centered_col(total_width, width)
  return math.max(0, math.floor((total_width - width) / 2))
end

local function centered_row(total_height, height)
  return math.max(0, math.floor((total_height - height) / 2))
end

local function dashboard_window_config(controller)
  if not controller.is_valid_win(controller.state.mission_dashboard_win) then
    return {}
  end

  local ok, config = pcall(controller.get_window_config, controller.state.mission_dashboard_win)
  return ok and type(config) == "table" and config or {}
end

local function text_tuple_value(value)
  if type(value) == "string" then
    return value
  end
  if type(value) == "table" and type(value[1]) == "table" and type(value[1][1]) == "string" then
    return value[1][1]
  end
  return value
end

local function border_value(value)
  if type(value) ~= "table" then
    return value
  end
  local rounded = {
    "\226\149\173",
    "\226\148\128",
    "\226\149\174",
    "\226\148\130",
    "\226\149\175",
    "\226\148\128",
    "\226\149\176",
    "\226\148\130",
  }
  for index, char in ipairs(rounded) do
    if value[index] ~= char then
      return value
    end
  end
  return "rounded"
end

local function config_value(key, value)
  if key == "title" or key == "footer" then
    return text_tuple_value(value)
  end
  if key == "border" then
    return border_value(value)
  end
  return value
end

local function values_equal(left, right)
  if type(left) ~= type(right) then
    return false
  end
  if type(left) ~= "table" then
    return left == right
  end
  for key, value in pairs(left) do
    if not values_equal(value, right[key]) then
      return false
    end
  end
  for key in pairs(right) do
    if left[key] == nil then
      return false
    end
  end
  return true
end

local function window_config_matches(current, desired)
  current = type(current) == "table" and current or {}
  desired = type(desired) == "table" and desired or {}
  for key, desired_value in pairs(desired) do
    if not values_equal(config_value(key, current[key]), config_value(key, desired_value)) then
      return false
    end
  end
  return true
end

local function apply_window_config(controller, win, config)
  local ok, current = pcall(controller.get_window_config, win)
  if ok and window_config_matches(current, config) then
    return true
  end
  return controller.set_window_config(win, config)
end

local function dashboard_width(controller, dashboard_config)
  local ok, width = pcall(function()
    return controller:window_width()
  end)
  if ok and type(width) == "number" and width > 0 then
    return width
  end
  if type(dashboard_config) == "table" and type(dashboard_config.width) == "number" then
    return dashboard_config.width
  end
  return controller:dashboard_config(1).width
end

local function dashboard_height(controller)
  local ok, height = pcall(function()
    return controller:window_height()
  end)
  if ok and type(height) == "number" and height > 0 then
    return height
  end
  return 8
end

local function dashboard_frame(controller)
  local total_width = math.max(1, vim.o.columns)
  local config = dashboard_window_config(controller)
  local width = dashboard_width(controller, config)
  local height = dashboard_height(controller)
  local col = type(config.col) == "number" and config.col or centered_col(total_width, width)
  local row = type(config.row) == "number" and config.row or 0

  return {
    config = config,
    width = width,
    height = height,
    col = col,
    row = row,
  }
end

function M.window_height(controller)
  if not controller.is_valid_win(controller.state.mission_dashboard_win) then
    return nil
  end

  local height = controller.get_window_height(controller.state.mission_dashboard_win)
  if type(height) == "number" and height > 0 then
    return height
  end

  return nil
end

function M.window_width(controller)
  if not controller.is_valid_win(controller.state.mission_dashboard_win) then
    return nil
  end

  local width = controller.get_window_width(controller.state.mission_dashboard_win)
  if type(width) == "number" and width > 0 then
    return width
  end

  return nil
end

function M.objective_editor_config(_, line_count, opts)
  opts = type(opts) == "table" and opts or {}
  local total_width, total_height = editor_size()
  local max_width = available_dimension(total_width, 4)
  local max_height = available_dimension(total_height, 4)
  local width = math.min(max_width, math.min(96, math.max(58, math.floor(total_width * 0.72))))
  local height = math.min(max_height, math.max(10, line_count or 1))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = opts.title or " Codux Mission Objective ",
    title_pos = "center",
    footer = opts.footer or " Ctrl-s/:w preview | Ctrl-q cancel ",
    footer_pos = "center",
    width = width,
    height = height,
    col = centered_col(total_width, width),
    row = centered_row(total_height, height),
    zindex = MISSION_CREATION_ZINDEX,
  }
end

function M.preview_config(_, line_count)
  local total_width, total_height = editor_size()
  local max_width = available_dimension(total_width, 4)
  local max_height = available_dimension(total_height, 4)
  local width = math.min(max_width, math.min(92, math.max(56, math.floor(total_width * 0.68))))
  local height = math.min(max_height, math.max(12, (line_count or 1) + 1))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Codux Mission Control ",
    title_pos = "center",
    width = width,
    height = height,
    col = centered_col(total_width, width),
    row = centered_row(total_height, height),
    focusable = true,
    zindex = MISSION_CREATION_ZINDEX,
  }
end

function M.dashboard_workspace_preview_active(_, entry)
  if type(entry) ~= "table" then
    return false
  end
  local status = entry.status
  return status == "active" or status == "idle" or status == "question"
end

function M.dashboard_preview_mode(controller, item)
  if type(item) == "table" and item.kind == "role" and controller:dashboard_workspace_preview_active(item.entry) then
    return "workspace"
  end
  return "compact"
end

function M.dashboard_preview_height(_, total_height, command_height, mode, dashboard_min_height)
  total_height = math.max(1, tonumber(total_height) or (vim.o.lines - vim.o.cmdheight))
  command_height = math.max(0, tonumber(command_height) or 0)
  mode = mode == "workspace" and "workspace" or "compact"
  dashboard_min_height = math.max(1, tonumber(dashboard_min_height) or 1)

  if mode == "compact" then
    return 1
  end

  local target = math.min(40, math.max(14, math.floor(total_height * 0.80)))
  local reserved_gaps = (command_height > 0 and 1 or 0) + 1
  local content_capacity = available_dimension(total_height, 4)
  local preferred_available = content_capacity - command_height - reserved_gaps - dashboard_min_height
  if preferred_available >= 1 then
    return math.min(target, preferred_available)
  end

  local compact_available = content_capacity - command_height - reserved_gaps - dashboard_min_height
  return math.min(target, math.max(1, compact_available))
end

function M.dashboard_config(controller, line_count, opts)
  opts = type(opts) == "table" and opts or {}
  local total_width, total_height = editor_size()
  local max_width = available_dimension(total_width, 4)
  local width = math.min(max_width, math.max(80, math.min(160, math.floor(total_width * 0.92))))
  local search_reserve = opts.reserve_search_input and bordered_float_outer_height(1) or 0
  local command_height = opts.reserve_command_bar and #controller:dashboard_command_lines(width) or 0
  local preview_mode = opts.preview_mode or controller:dashboard_preview_mode(opts.selected_item)
  local dashboard_min_height = math.max(1, tonumber(opts.dashboard_min_height) or 1)
  local preview_height = opts.reserve_output_panel
      and controller:dashboard_preview_height(total_height, command_height, preview_mode, dashboard_min_height)
    or 0
  local command_reserve = command_height > 0 and bordered_float_outer_height(command_height) or 0
  local preview_reserve = preview_height > 0 and bordered_float_outer_height(preview_height) or 0
  local output_reserve = search_reserve + command_reserve + preview_reserve
  local max_height = output_reserve > 0 and math.max(dashboard_min_height, total_height - output_reserve - 2)
    or available_dimension(total_height, 4)
  local height = math.min(max_height, math.max(8, dashboard_min_height, line_count or 1))
  local stack_height = bordered_float_outer_height(height) + output_reserve
  local stack_top = math.max(0, math.floor((total_height - stack_height) / 2))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Mission Control ",
    title_pos = "center",
    footer = " Commands shown below ",
    footer_pos = "center",
    width = width,
    height = height,
    col = centered_col(total_width, width),
    row = stack_top + search_reserve,
  }
end

function M.dashboard_search_config(controller)
  local frame = dashboard_frame(controller)
  local height = 1

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Search Codux missions: ",
    title_pos = "center",
    width = math.max(20, frame.width),
    height = height,
    col = math.max(0, frame.col),
    row = math.max(0, frame.row - bordered_float_outer_height(height)),
    zindex = 60,
  }
end

function M.dashboard_command_config(controller, line_count)
  local frame = dashboard_frame(controller)

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Commands ",
    title_pos = "center",
    width = frame.width,
    height = math.max(1, tonumber(line_count) or 1),
    col = math.max(0, frame.col),
    row = next_bordered_float_row(frame.row, frame.height),
    zindex = 54,
    focusable = false,
  }
end

function M.dashboard_output_config(controller, line_count, opts)
  opts = type(opts) == "table" and opts or {}
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local frame = dashboard_frame(controller)
  local command_config = controller.is_valid_win(controller.state.mission_dashboard_command_bar_win)
      and controller.get_window_config(controller.state.mission_dashboard_command_bar_win)
    or nil
  local command_height = controller.is_valid_win(controller.state.mission_dashboard_command_bar_win)
      and controller.get_window_height(controller.state.mission_dashboard_command_bar_win)
    or nil
  command_height = command_height or #controller:dashboard_command_lines(frame.width)
  local row = command_config and type(command_config.row) == "number" and command_height
      and next_bordered_float_row(command_config.row, command_height)
    or next_bordered_float_row(frame.row, frame.height)
  local available_below = total_height - row - 2
  local preview_mode = opts.preview_mode or controller:dashboard_preview_mode(opts.selected_item)
  local desired_height = controller:dashboard_preview_height(
    total_height,
    command_height,
    preview_mode,
    opts.dashboard_min_height
  )
  local height = math.min(desired_height, math.max(1, available_below))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Output ",
    title_pos = "center",
    width = frame.width,
    height = height,
    col = math.max(0, frame.col),
    row = math.max(0, row),
    zindex = 55,
    focusable = false,
  }
end

function M.resize_dashboard_stack(controller, line_count, opts)
  opts = type(opts) == "table" and opts or {}
  if not controller.is_valid_win(controller.state.mission_dashboard_win) then
    return false
  end

  local dashboard_config = controller:dashboard_config(line_count, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    reserve_search_input = controller.is_valid_win(controller.state.mission_dashboard_search_win),
    selected_item = opts.selected_item,
    preview_mode = opts.preview_mode,
    dashboard_min_height = opts.dashboard_min_height,
  })
  local ok = apply_window_config(controller, controller.state.mission_dashboard_win, dashboard_config)
  if not ok then
    return false
  end

  if controller.is_valid_win(controller.state.mission_dashboard_search_win) then
    ok = apply_window_config(controller, controller.state.mission_dashboard_search_win, controller:dashboard_search_config())
      and ok
  end
  if controller.is_valid_win(controller.state.mission_dashboard_command_bar_win) then
    local command_lines = controller:dashboard_command_lines(dashboard_config.width)
    ok = apply_window_config(
      controller,
      controller.state.mission_dashboard_command_bar_win,
      controller:dashboard_command_config(#command_lines)
    ) and ok
  end
  if controller.is_valid_win(controller.state.mission_dashboard_output_win) then
    ok = apply_window_config(
      controller,
      controller.state.mission_dashboard_output_win,
      controller:dashboard_output_config(line_count, {
        selected_item = opts.selected_item,
        preview_mode = opts.preview_mode,
        dashboard_min_height = opts.dashboard_min_height,
      })
    ) and ok
  end
  return ok
end

function M.objective_preview_config(_, line_count)
  local total_width, total_height = editor_size()
  local max_width = available_dimension(total_width, 4)
  local max_height = available_dimension(total_height, 4)
  local width = math.min(max_width, math.min(92, math.max(56, math.floor(total_width * 0.68))))
  local height = math.min(max_height, math.max(8, (line_count or 1) + 2))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Codux Mission Objective ",
    title_pos = "center",
    footer = " q close ",
    footer_pos = "center",
    width = width,
    height = height,
    col = centered_col(total_width, width),
    row = centered_row(total_height, height),
    zindex = 80,
  }
end

return M
