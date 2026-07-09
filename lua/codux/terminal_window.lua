local ui = require("codux.ui")
local terminal_keymaps = require("codux.terminal_keymaps")

local M = {}

local is_valid_buf = ui.is_valid_buf
local is_valid_win = ui.is_valid_win
local window_buffer = ui.window_buffer

function M.focus_window(controller)
  if not controller:valid_win() then
    return false
  end

  local focus_ok = pcall(vim.api.nvim_set_current_win, controller.state.win)
  if not focus_ok then
    controller.state.win = nil
    return false
  end
  if controller:terminal_running() then
    controller:focus_terminal_prompt()
  end

  return true
end

function M.dimension(_, value, total, fallback)
  if type(value) == "number" then
    if value > 0 and value < 1 then
      return math.max(1, math.floor(total * value))
    end
    if value >= 1 then
      return math.max(1, math.floor(value))
    end
  end

  return math.max(1, math.floor(total * fallback))
end

function M.popup_config(controller)
  local popup = controller:config().popup or {}
  local total_width = vim.o.columns
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local has_border = popup.border ~= nil and popup.border ~= "none"
  local available_width = math.max(1, total_width - (has_border and 2 or 0))
  local available_height = math.max(1, total_height - (has_border and 2 or 0))
  local width = math.min(available_width, controller:dimension(popup.width, available_width, 0.85))
  local height = math.min(available_height, controller:dimension(popup.height, available_height, 0.85))
  local border_size = has_border and 2 or 0

  return {
    relative = "editor",
    style = "minimal",
    border = popup.border or "rounded",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width - border_size) / 2)),
    row = math.max(0, math.floor((total_height - height - border_size) / 2) - 1),
  }
end

function M.popup_focus_lock_enabled(controller)
  local popup = controller:config().popup or {}
  return popup.lock_focus ~= false
end

function M.schedule_popup_focus_lock(controller)
  if controller.state.closing_popup or controller.state.focus_lock_pending then
    return
  end
  if not controller:popup_focus_lock_enabled() or not controller:valid_win() then
    return
  end

  controller.state.focus_lock_pending = true
  vim.schedule(function()
    controller.state.focus_lock_pending = false
    if controller.state.closing_popup or not controller:popup_focus_lock_enabled() or not controller:valid_win() then
      return
    end

    local current_ok, current_win = pcall(vim.api.nvim_get_current_win)
    if current_ok and current_win == controller.state.win then
      return
    end

    controller:focus_window()
  end)
end

function M.ensure_buffer(controller)
  if controller:valid_buf() then
    return true
  end

  controller:clear_stale_buffer()

  local bufnr = controller.ui.create_scratch_buffer({
    bufhidden = "hide",
    filetype = "codux",
  })
  if not bufnr then
    controller.state.buf = nil
    controller.notify("Failed to create Codux terminal buffer", vim.log.levels.ERROR)
    return false
  end

  controller.state.buf = bufnr
  pcall(vim.api.nvim_buf_set_name, bufnr, "codux://codex")
  terminal_keymaps.bind_prompt_controls(controller, bufnr, {
    close = function()
      return controller:close()
    end,
    close_desc = "Hide Codux Popup",
  })

  pcall(vim.api.nvim_create_autocmd, { "BufUnload", "BufDelete", "BufWipeout" }, {
    group = controller.augroup,
    buffer = bufnr,
    callback = function()
      if controller.state.buf == bufnr then
        controller.state.buf = nil
        controller.state.job_id = nil
        controller.state.last_prompt_line = nil
        controller:reset_terminal_prompt_input()
        controller:set_codex_working(false, { force_idle = true })
        controller:set_mode("not running")
      end
    end,
  })

  controller:attach_terminal_activity(bufnr)

  return true
end

function M.open_window(controller, focus)
  if not controller:ensure_buffer() then
    return false
  end

  if controller:valid_win() then
    local config_ok = pcall(vim.api.nvim_win_set_config, controller.state.win, controller:popup_config())
    if not config_ok then
      controller.state.win = nil
      return controller:open_window(focus)
    end
    controller:close_working_indicator()
    pcall(vim.api.nvim_set_option_value, "wrap", true, { win = controller.state.win })
    if focus then
      controller:focus_window()
    end
    return true
  end

  controller.state.win = nil

  local win_ok, win = pcall(vim.api.nvim_open_win, controller.state.buf, focus == true, controller:popup_config())
  if not win_ok then
    controller.state.buf = nil
    if not controller:ensure_buffer() then
      return false
    end
    win_ok, win = pcall(vim.api.nvim_open_win, controller.state.buf, focus == true, controller:popup_config())
  end
  if not win_ok then
    controller.notify("Failed to open Codux popup", vim.log.levels.ERROR)
    return false
  end

  controller.state.win = win
  controller.state.closing_popup = false
  controller:close_working_indicator()
  pcall(vim.api.nvim_set_option_value, "number", false, { win = controller.state.win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = controller.state.win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = controller.state.win })
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = controller.state.win })
  pcall(vim.api.nvim_set_option_value, "wrap", true, { win = controller.state.win })

  local win_id = controller.state.win
  if controller.state.focus_lock_autocmd then
    pcall(vim.api.nvim_del_autocmd, controller.state.focus_lock_autocmd)
    controller.state.focus_lock_autocmd = nil
  end
  vim.api.nvim_create_autocmd("WinClosed", {
    group = controller.augroup,
    pattern = tostring(win_id),
    once = true,
    callback = function()
      if controller.state.win == win_id then
        controller.state.win = nil
        if controller.state.focus_lock_autocmd then
          pcall(vim.api.nvim_del_autocmd, controller.state.focus_lock_autocmd)
          controller.state.focus_lock_autocmd = nil
        end
        controller:update_working_indicator()
      end
    end,
  })
  controller.state.focus_lock_autocmd = vim.api.nvim_create_autocmd("WinLeave", {
    group = controller.augroup,
    callback = function()
      if controller.state.win == win_id then
        controller:schedule_popup_focus_lock()
      end
    end,
  })

  vim.api.nvim_clear_autocmds({ group = controller.augroup, event = "VimResized" })
  vim.api.nvim_create_autocmd("VimResized", {
    group = controller.augroup,
    callback = function()
      if controller:valid_win() then
        pcall(vim.api.nvim_win_set_config, controller.state.win, controller:popup_config())
      end
      controller:update_working_indicator()
    end,
  })

  if focus then
    controller:focus_window()
  end

  return true
end

function M.close(controller)
  if controller:valid_win() then
    controller.state.closing_popup = true
    controller.ui.close_window(controller.state.win)
    controller.state.win = nil
    controller.state.closing_popup = false
    controller:update_working_indicator()
    controller.refresh_which_key()
    return true
  end

  return false
end

function M.health_popup_visible(controller)
  return is_valid_win(controller.state.win)
end

function M.health_working_indicator_visible(controller)
  return is_valid_win(controller.state.working_win)
end

function M.buffer_is_valid(bufnr)
  return is_valid_buf(bufnr)
end

function M.window_buffer(winid)
  return window_buffer(winid)
end

return M
