local ui = require("codux.ui")

local M = {}

function M.output_buffer_buftype(self, bufnr)
  if not self.is_loaded_buf(bufnr) then
    return nil
  end
  local ok, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = bufnr })
  return ok and buftype or nil
end

function M.attach_output_buffer_autocmd(self, bufnr)
  if not self.is_loaded_buf(bufnr) then
    return false
  end

  local group = vim.api.nvim_create_augroup("codux-mission-output-" .. tostring(bufnr), { clear = true })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if self.state.mission_dashboard_output_replacing_buf == bufnr then
        pcall(vim.api.nvim_del_augroup_by_id, group)
        return
      end
      if self.state.mission_dashboard_output_buf == bufnr then
        self:close_output_preview()
        self.state.mission_dashboard_output_buf = nil
        self.state.mission_dashboard_output_win = nil
        self.state.mission_dashboard_output_entry = nil
        self.state.mission_dashboard_output_key = nil
        self.state.mission_dashboard_output_blocked_key = nil
        self.state.mission_dashboard_output_buf_kind = nil
        self.state.mission_dashboard_output_control = false
        self.state.mission_dashboard_output_control_key = nil
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
  return true
end

function M.create_output_buffer(self, kind, lines)
  if type(self.ui.create_scratch_buffer) ~= "function" then
    return nil
  end

  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions-output",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    return nil
  end

  ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
  if type(lines) == "table" then
    self.ui.set_lines(bufnr, lines, { modifiable = true })
    self:highlight_output_panel(bufnr, lines)
  end
  self:bind_output_panel_commands(bufnr)
  self:attach_output_buffer_autocmd(bufnr)
  return bufnr
end

function M.output_window_buffer(self)
  if not self.is_valid_win(self.state.mission_dashboard_output_win) then
    return nil
  end

  local ok, current = pcall(vim.api.nvim_win_get_buf, self.state.mission_dashboard_output_win)
  return ok and current or nil
end

function M.unlock_output_window(self)
  local win = self.state.mission_dashboard_output_win
  if not self.is_valid_win(win) then
    return false
  end
  pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
  return true
end

function M.set_output_window_buffer(self, bufnr)
  local win = self.state.mission_dashboard_output_win
  if not self.is_valid_win(win) then
    return true
  end

  local current = self:output_window_buffer()
  if current == nil then
    return true
  end
  if current == bufnr then
    return true
  end

  local had_winfixbuf = false
  local winfix_ok, winfixbuf = pcall(vim.api.nvim_get_option_value, "winfixbuf", { win = win })
  if winfix_ok then
    had_winfixbuf = winfixbuf == true
    if had_winfixbuf then
      pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
    end
  end

  local set_ok = pcall(vim.api.nvim_win_set_buf, win, bufnr)
  if winfix_ok and had_winfixbuf then
    self:unlock_output_window()
  end
  if not set_ok then
    return false
  end

  return self:output_window_buffer() == bufnr
end

function M.replace_output_buffer(self, kind, lines)
  local old_buf = self.state.mission_dashboard_output_buf
  local bufnr = self:create_output_buffer(kind, lines)
  if not bufnr then
    if not self.is_loaded_buf(old_buf) then
      return false
    end
    self.state.mission_dashboard_output_buf_kind = kind
    return true
  end

  self.state.mission_dashboard_output_replacing_buf = old_buf
  if not self:set_output_window_buffer(bufnr) then
    if self.state.mission_dashboard_output_replacing_buf == old_buf then
      self.state.mission_dashboard_output_replacing_buf = nil
    end
    self.ui.delete_buffer(bufnr)
    return false
  end

  self.state.mission_dashboard_output_buf = bufnr
  self.state.mission_dashboard_output_buf_kind = kind
  if old_buf ~= bufnr then
    self.ui.delete_buffer(old_buf)
  end
  if self.state.mission_dashboard_output_replacing_buf == old_buf then
    self.state.mission_dashboard_output_replacing_buf = nil
  end
  return true
end

function M.ensure_output_buffer(self, kind, lines)
  local bufnr = self.state.mission_dashboard_output_buf
  local buftype = self:output_buffer_buftype(bufnr)
  local current_kind = self.state.mission_dashboard_output_buf_kind
  local must_replace = not self.is_loaded_buf(bufnr)
    or current_kind ~= kind
    or buftype == "terminal"
    or kind == "terminal"

  if must_replace then
    return self:replace_output_buffer(kind, lines)
  end

  self.state.mission_dashboard_output_buf_kind = kind
  return true
end

function M.prepare_output_terminal_buffer(self)
  if not self:ensure_output_buffer("terminal") then
    return false
  end

  local bufnr = self.state.mission_dashboard_output_buf
  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
  return true
end

return M
