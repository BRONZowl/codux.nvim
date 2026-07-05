local ui_mod = require("codux.ui")

local M = {}

local frames = {
  " codex is working    ",
  " codex is working.   ",
  " codex is working..  ",
  " codex is working... ",
}

function M.config()
  local width = 21
  local height = 1
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)

  return {
    relative = "editor",
    style = "minimal",
    focusable = false,
    width = width,
    height = height,
    col = math.max(0, total_width - width - 2),
    row = math.max(0, total_height - height - 1),
    border = "rounded",
    zindex = 40,
  }
end

function M.close(controller)
  controller:stop_working_timer()

  controller.ui.close_window(controller.state.working_win)
  controller.state.working_win = nil

  controller.ui.delete_buffer(controller.state.working_buf)
  controller.state.working_buf = nil
  controller.state.working_frame = 1
end

function M.render(controller)
  if not ui_mod.is_loaded_buf(controller.state.working_buf) then
    return
  end

  local frame = frames[controller.state.working_frame] or frames[1]
  controller.ui.set_lines(controller.state.working_buf, { frame })
end

function M.ensure(controller)
  if ui_mod.is_valid_win(controller.state.working_win) then
    pcall(vim.api.nvim_win_set_config, controller.state.working_win, controller:working_indicator_config())
    return true
  end

  if ui_mod.is_loaded_buf(controller.state.working_buf) then
    controller:render_working_indicator()
    local win_ok, win = pcall(vim.api.nvim_open_win, controller.state.working_buf, false, controller:working_indicator_config())
    if not win_ok then
      controller.state.working_win = nil
      return false
    end

    controller.state.working_win = win
    controller.ui.set_window_options(win, {
      winblend = 10,
      wrap = false,
    })
    return true
  end

  local frame = frames[controller.state.working_frame] or frames[1]
  local handle = ui_mod.open_scratch_float({
    ui = controller.ui,
    buffer_options = {
      bufhidden = "wipe",
      modifiable = true,
    },
    lines = { frame },
    modifiable = true,
    enter = false,
    config = function()
      return controller:working_indicator_config()
    end,
    window_options = {
      winblend = 10,
      wrap = false,
    },
  })
  if not handle then
    controller.state.working_buf = nil
    controller.state.working_win = nil
    return false
  end

  controller.state.working_buf = handle.bufnr
  controller.state.working_win = handle.win
  return true
end

function M.start_timer(controller)
  if controller.state.working_timer then
    return
  end

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  controller.state.working_timer = timer
  timer:start(0, 450, vim.schedule_wrap(function()
    if not ui_mod.is_valid_win(controller.state.working_win) then
      controller:stop_working_timer()
      return
    end

    controller.state.working_frame = (controller.state.working_frame % #frames) + 1
    controller:render_working_indicator()
  end))
end

function M.update(controller)
  if controller.state.codex_working and controller:working_activity_is_stale() then
    controller:set_codex_working(false)
    return
  end

  if controller.state.codex_working and controller:terminal_running() and not controller:valid_win() then
    if controller:ensure_working_indicator() then
      controller:start_working_timer()
    end
    return
  end

  controller:close_working_indicator()
end

return M
