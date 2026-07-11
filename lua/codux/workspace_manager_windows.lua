local filetypes = require("codux.filetypes")
local ui = require("codux.ui")

local M = {}

local dashboard_filetypes = filetypes.workspace_manager

function M.stop_refresh_timer(controller)
  local timer = controller.state.workspace_manager.refresh_timer
  controller.state.workspace_manager.refresh_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

function M.start_refresh_timer(controller)
  if controller.state.workspace_manager.refresh_timer then
    return
  end

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  controller.state.workspace_manager.refresh_timer = timer
  timer:start(1000, 1000, vim.schedule_wrap(function()
    if
      not controller.is_valid_win(controller.state.workspace_manager.win)
      or not controller.is_loaded_buf(controller.state.workspace_manager.buf)
    then
      controller:stop_refresh_timer()
      return
    end
    controller:render()
  end))
end

function M.max_dashboard_height(controller)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local editor_max_height = math.max(1, total_height - 2)
  local codux_max_height = tonumber(controller.workspace_manager_max_height())
  if codux_max_height and codux_max_height > 0 then
    return math.max(1, math.min(editor_max_height, math.floor(codux_max_height)))
  end
  return editor_max_height
end

function M.dashboard_height(controller, line_count)
  local max_height = controller:max_dashboard_height()
  local min_height = math.min(5, max_height)
  return math.min(max_height, math.max(min_height, line_count or 1))
end

function M.config(controller, line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local max_width = math.max(1, total_width - 4)
  local width = math.min(max_width, math.max(80, math.min(88, math.floor(total_width * 0.75))))
  local height = controller:dashboard_height(line_count)

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " current codux workspaces ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
  }
end

function M.close(controller)
  controller:stop_refresh_timer()

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = controller.window_buffer(win)
    if controller.is_loaded_buf(bufnr) and dashboard_filetypes[controller.buffer_filetype(bufnr)] then
      controller.ui.close_window(win)
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if controller.is_loaded_buf(bufnr) and dashboard_filetypes[controller.buffer_filetype(bufnr)] then
      controller.ui.delete_buffer(bufnr)
    end
  end

  controller.state.workspace_manager.win = nil
  controller.state.workspace_manager.buf = nil
  controller.state.workspace_manager.footer_win = nil
  controller.state.workspace_manager.footer_buf = nil
  controller.state.workspace_manager.search_win = nil
  controller.state.workspace_manager.search_buf = nil
  controller.state.workspace_manager.command_win = nil
  controller.state.workspace_manager.command_buf = nil
  controller.state.workspace_manager.action_win = nil
  controller.state.workspace_manager.action_buf = nil
  controller.state.workspace_manager.action_items = {}
  controller.state.workspace_manager.action_workspace = nil
  controller.state.workspace_manager.items = {}
  controller.state.workspace_manager.query = ""
  controller.state.workspace_manager.best_match_index = nil
  controller.state.workspace_manager.selected_index = nil
  controller.state.workspace_manager.focus_match = false
  controller.state.workspace_manager.search_confirmed = false
  controller.state.workspace_manager.project_root = nil
end

function M.window_height(controller)
  if not controller.is_valid_win(controller.state.workspace_manager.win) then
    return nil
  end

  local height = controller.get_window_height(controller.state.workspace_manager.win)
  if type(height) == "number" and height > 0 then
    return height
  end

  return nil
end

function M.window_width(controller)
  if not controller.is_valid_win(controller.state.workspace_manager.win) then
    return nil
  end

  local width = controller.get_window_width(controller.state.workspace_manager.win)
  if type(width) == "number" and width > 0 then
    return width
  end

  return nil
end

function M.footer_config(controller)
  if not controller.is_valid_win(controller.state.workspace_manager.win) then
    return nil
  end

  local height = controller:window_height() or 1
  local width = controller:window_width() or 1
  return {
    relative = "win",
    win = controller.state.workspace_manager.win,
    col = 0,
    row = height - 1,
    width = width,
    height = 1,
    border = "none",
    style = "minimal",
    zindex = 51,
  }
end

function M.position_footer(controller)
  if not controller.is_valid_win(controller.state.workspace_manager.footer_win) then
    return false
  end
  local config = controller:footer_config()
  if not config then
    return false
  end
  return controller.set_window_config(controller.state.workspace_manager.footer_win, config)
end

function M.resize_dashboard(controller, line_count)
  if not controller.is_valid_win(controller.state.workspace_manager.win) then
    return false
  end

  local next_height = controller:dashboard_height(line_count)
  if controller:window_height() == next_height then
    controller:position_footer()
    return true
  end

  local current = controller.get_window_config(controller.state.workspace_manager.win)
  local config = controller:config(line_count)
  config.width = type(current.width) == "number" and current.width or config.width
  config.col = type(current.col) == "number" and current.col or config.col
  config.row = type(current.row) == "number" and current.row or config.row
  config.height = next_height

  local ok = controller.set_window_config(controller.state.workspace_manager.win, config)
  if ok then
    controller:position_footer()
  end
  return ok
end

function M.render_footer(controller)
  if not controller.is_loaded_buf(controller.state.workspace_manager.footer_buf) then
    return false
  end

  local width = controller:window_width() or 1
  local segments = controller.workspace_ui.manager_footer_segments({}, width)
  local line = controller.workspace_ui.footer_line(segments)
  local padding = math.max(0, math.floor((width - #line) / 2))
  local text = string.rep(" ", padding) .. line
  local ns = controller:ns()

  controller.ui.set_lines(controller.state.workspace_manager.footer_buf, { text }, { modifiable = true })
  pcall(vim.api.nvim_buf_clear_namespace, controller.state.workspace_manager.footer_buf, ns, 0, -1)

  local col = padding
  for index, segment in ipairs(segments) do
    local key_end = col + #segment.key
    pcall(vim.api.nvim_buf_add_highlight, controller.state.workspace_manager.footer_buf, ns, "WhichKey", 0, col, key_end)
    local desc_width = #tostring(segment.desc or "")
    local desc_end = key_end
    if desc_width > 0 then
      desc_end = key_end + 1 + desc_width
      pcall(vim.api.nvim_buf_add_highlight, controller.state.workspace_manager.footer_buf, ns, "WhichKeySeparator", 0, key_end, desc_end)
    end
    col = desc_end
    if index < #segments then
      col = col + 2
    end
  end

  return true
end

function M.open_footer(controller)
  if not controller.is_valid_win(controller.state.workspace_manager.win) then
    return false
  end

  local bufnr = controller.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-workspaces-footer",
    modifiable = false,
  })
  if not bufnr then
    return false
  end

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, controller:footer_config())
  if not win_ok then
    controller.ui.delete_buffer(bufnr)
    return false
  end

  controller.state.workspace_manager.footer_buf = bufnr
  controller.state.workspace_manager.footer_win = win
  controller:render_footer()
  return true
end

function M.open_command_sink(controller)
  local sink_bufnr, sink_win = ui.open_hidden_command_sink({
    ui = controller.ui,
    filetype = "codux-workspaces-command",
    bind = function(target_bufnr)
      controller:bind_commands(target_bufnr)
    end,
  })
  if not sink_bufnr then
    return false
  end

  controller.state.workspace_manager.command_buf = sink_bufnr
  controller.state.workspace_manager.command_win = sink_win
  return true
end

function M.open(controller)
  if not controller.workspaces_enabled() then
    controller.notify("Codux workspaces are disabled", vim.log.levels.ERROR)
    return false
  end

  controller:close()
  local bufnr = controller.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-workspaces",
    modifiable = false,
  })
  if not bufnr then
    controller.notify("Failed to create Codux workspaces window", vim.log.levels.ERROR)
    return false
  end

  controller.state.workspace_manager.buf = bufnr
  controller.state.workspace_manager.project_root = controller.project_root()
  controller.restore_workspaces({ project_root = controller.state.workspace_manager.project_root, silent = true })
  local preview_entries = controller.workspace_entries_for_project(controller.state.workspace_manager.project_root)
  local line_count = 1 + math.max(1, #preview_entries) + 1

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, controller:config(line_count))
  if not win_ok then
    controller.state.workspace_manager.buf = nil
    controller.ui.delete_buffer(bufnr)
    controller.notify("Failed to open Codux workspaces window", vim.log.levels.ERROR)
    return false
  end

  controller.state.workspace_manager.win = win
  controller.ui.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    cursorline = true,
  })
  controller:open_footer()
  controller:bind_commands(bufnr)
  controller:open_command_sink()

  controller:render()
  controller:start_refresh_timer()
  if #controller.state.workspace_manager.items > 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { 2, 0 })
  end
  vim.schedule(function()
    if controller.is_valid_win(controller.state.workspace_manager.win) and controller.is_loaded_buf(controller.state.workspace_manager.buf) then
      controller:open_search_input()
      controller.prompt_merged_workspaces(controller.state.workspace_manager.project_root)
    end
  end)
  return true
end

return M
