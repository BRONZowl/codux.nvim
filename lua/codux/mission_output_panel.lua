local Output = {}

local output_buffer = require("codux.mission_output_buffer")
local output_preview = require("codux.mission_output_preview")
local output_terminal = require("codux.mission_output_terminal")

local function role_cache_key(entry)
  entry = type(entry) == "table" and entry or {}
  return table.concat({
    tostring(entry.project_root or entry.worktree_path or ""),
    tostring(entry.safe_name or entry.name or entry.mission_role or ""),
  }, "\0")
end

function Output:dashboard_output_entry(item)
  if type(item) == "table" then
    if item.kind == "role" and type(item.entry) == "table" then
      return item.entry
    end
  end
  return nil
end

function Output:highlight_output_panel(bufnr, lines)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, self.namespace, 0, -1)
  for index, line in ipairs(lines or {}) do
    if line:find("^Output:%s", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 0, -1)
    elseif line:find("^%s+", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 0, -1)
    end
  end
end

function Output:output_panel_lines(entry, message)
  local lines = {}
  if type(entry) ~= "table" then
    table.insert(lines, "Output: select a workspace row to preview its Codux session")
    return lines
  end

  if entry.status == "inactive" then
    table.insert(lines, "Output: workspace inactive")
    return lines
  end

  local role = entry.mission_role or entry.name or entry.safe_name or "workspace"
  table.insert(lines, "Output: " .. tostring(role))
  table.insert(lines, "  " .. tostring(message or "opening workspace session preview..."))
  return lines
end

function Output:selected_output_entry()
  local item = self:selected_item()
  return self:dashboard_output_entry(item)
end

function Output:output_entry_key(entry)
  if type(entry) ~= "table" then
    return ""
  end
  return role_cache_key(entry)
end

function Output:clear_output_panel_state()
  self.state.mission_dashboard_output_win = nil
  self.state.mission_dashboard_output_buf = nil
  self.state.mission_dashboard_output_entry = nil
  self.state.mission_dashboard_output_key = nil
  self.state.mission_dashboard_output_blocked_key = nil
  self.state.mission_dashboard_output_job = nil
  self.state.mission_dashboard_output_preview = nil
  self.state.mission_dashboard_output_buf_kind = nil
  self.state.mission_dashboard_output_control = false
  self.state.mission_dashboard_output_control_key = nil
  self.state.mission_dashboard_output_control_mouse = nil
  self.state.mission_dashboard_output_terminal_controller = nil
  self.state.mission_dashboard_output_terminal_state = nil
end

function Output:render_output_status(entry, message)
  if not self:ensure_output_buffer("status", self:output_panel_lines(entry, message)) then
    return false
  end
  local lines = self:output_panel_lines(entry, message)
  self.ui.set_lines(self.state.mission_dashboard_output_buf, lines, { modifiable = true })
  self:highlight_output_panel(self.state.mission_dashboard_output_buf, lines)
  pcall(vim.api.nvim_set_option_value, "modified", false, { buf = self.state.mission_dashboard_output_buf })
  return true
end

function Output:render_output_panel(entry)
  if not self.is_loaded_buf(self.state.mission_dashboard_output_buf) then
    return false
  end
  if self.state.mission_dashboard_output_control then
    return true
  end
  entry = type(entry) == "table" and entry or self:selected_output_entry()
  local key = self:output_entry_key(entry)
  if type(entry) == "table" and entry.status == "inactive" then
    self:close_output_preview()
    self.state.mission_dashboard_output_entry = entry
    self.state.mission_dashboard_output_key = key
    self.state.mission_dashboard_output_blocked_key = key ~= "" and key or nil
    return self:render_output_status(entry, "workspace is not active")
  end
  if key ~= self.state.mission_dashboard_output_key then
    return self:start_output_preview(entry)
  end
  if self:output_preview_running() then
    self.state.mission_dashboard_output_entry = entry
    return true
  end
  if key ~= "" and key == self.state.mission_dashboard_output_blocked_key then
    self.state.mission_dashboard_output_entry = entry
    return true
  end
  return self:start_output_preview(entry)
end

function Output:focus_output_panel()
  if not self.is_valid_win(self.state.mission_dashboard_output_win) then
    return false
  end
  self:unlock_output_window()
  local ok = self.set_current_win(self.state.mission_dashboard_output_win)
  if ok and self:output_preview_running() then
    pcall(vim.cmd, "startinsert")
  end
  return ok
end

function Output:set_output_window_focusable(focusable)
  local win = self.state.mission_dashboard_output_win
  if not self.is_valid_win(win) then
    return false
  end
  local config = self.get_window_config(win)
  config = type(config) == "table" and config or {}
  config.focusable = focusable == true
  return self.set_window_config(win, config)
end

function Output:reset_output_control_state()
  self.state.mission_dashboard_output_control = false
  self.state.mission_dashboard_output_control_key = nil
  self:relock_output_control_mouse()
  self:set_output_window_focusable(false)
  return true
end

function Output:enter_output_control()
  local entry = self:selected_output_entry()
  if type(entry) ~= "table" then
    self.notify("Select a workspace row to control its output", vim.log.levels.WARN)
    return false
  end
  if entry.status == "inactive" then
    self.notify("Workspace output is inactive", vim.log.levels.WARN)
    return false
  end
  if not self.is_loaded_buf(self.state.mission_dashboard_output_buf) or not self.is_valid_win(self.state.mission_dashboard_output_win) then
    if not self:open_output_panel(entry) then
      return false
    end
  end

  self:stop_monitor_timer()
  self.state.mission_dashboard_output_control = true
  self.state.mission_dashboard_output_control_key = self:output_entry_key(entry)
  self:set_output_window_focusable(true)

  if not self:start_output_preview(entry, { control = true }) then
    self:reset_output_control_state()
    self:start_monitor_timer()
    return false
  end
  self:enable_output_control_mouse()
  if not self:focus_output_panel() then
    self:exit_output_control()
    return false
  end
  self:refresh_dashboard_highlight()
  return true
end

function Output:exit_output_control()
  if not self.state.mission_dashboard_output_control then
    return false
  end

  local entry = self:selected_output_entry() or self.state.mission_dashboard_output_entry
  self:reset_output_control_state()
  self:close_output_preview()
  self:render_output_panel(entry)
  self:refresh_dashboard_highlight()
  self:start_monitor_timer()
  self:focus_mission_list()
  return true
end

function Output:bind_output_panel_commands(bufnr)
  self.set_buffer_keymap(bufnr, { "n", "t" }, "<C-q>", function()
    return self:close_dashboard()
  end, "Close Codux Missions", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, { "n", "t" }, "<C-o>", function()
    if self.state.mission_dashboard_output_control then
      return self:exit_output_control()
    end
    return self:focus_mission_list()
  end, "Return to Codux Missions", {
    nowait = true,
  })
end

function Output:open_output_panel(entry)
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return false
  end
  if self.is_valid_win(self.state.mission_dashboard_output_win) and self.is_loaded_buf(self.state.mission_dashboard_output_buf) then
    return self:render_output_panel(entry)
  end

  local initial_lines = self:output_panel_lines(entry, "opening workspace session preview...")
  local bufnr = self:create_output_buffer("status", initial_lines)
  if not bufnr then
    self.notify("Failed to create Codux mission output", vim.log.levels.ERROR)
    return false
  end
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, self:dashboard_output_config(#initial_lines, {
    preview_mode = self:dashboard_preview_mode({ kind = "role", entry = entry }),
  }))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission output", vim.log.levels.ERROR)
    return false
  end

  self.state.mission_dashboard_output_buf = bufnr
  self.state.mission_dashboard_output_win = win
  self.state.mission_dashboard_output_buf_kind = "status"
  self.state.mission_dashboard_output_entry = entry
  self.state.mission_dashboard_output_key = nil
  self.ui.set_window_options(win, {
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = false,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  self:start_output_preview(entry)

  return true
end

function Output:close_output_panel()
  self:relock_output_control_mouse()
  self:close_output_preview()
  self.ui.close_window(self.state.mission_dashboard_output_win)
  self.ui.delete_buffer(self.state.mission_dashboard_output_buf)
  self:clear_output_panel_state()
  return true
end

for name, fn in pairs(output_buffer) do
  Output[name] = fn
end

for name, fn in pairs(output_preview) do
  Output[name] = fn
end

for name, fn in pairs(output_terminal) do
  Output[name] = fn
end

return Output
