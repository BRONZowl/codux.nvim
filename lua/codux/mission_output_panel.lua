local Output = {}

local output_buffer = require("codux.mission_output_buffer")
local output_preview = require("codux.mission_output_preview")

local function role_cache_key(entry)
  entry = type(entry) == "table" and entry or {}
  return table.concat({
    tostring(entry.project_root or entry.worktree_path or ""),
    tostring(entry.safe_name or entry.name or entry.mission_role or ""),
    tostring(entry.status or ""),
    tostring(entry.worktree_branch or ""),
    tostring(entry.worktree_base or ""),
    tostring(entry.worktree_base_commit or ""),
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
  entry = type(entry) == "table" and entry or self:selected_output_entry()
  local key = self:output_entry_key(entry)
  if key ~= self.state.mission_dashboard_output_key then
    return self:start_output_preview(entry)
  end
  if self:output_preview_running() then
    return true
  end
  if key ~= "" and key == self.state.mission_dashboard_output_blocked_key then
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

function Output:bind_output_panel_commands(bufnr)
  self.set_buffer_keymap(bufnr, { "n", "t" }, "<C-q>", function()
    return self:close_dashboard()
  end, "Close Codux Missions", {
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
  self:close_output_preview()
  self.ui.close_window(self.state.mission_dashboard_output_win)
  self.ui.delete_buffer(self.state.mission_dashboard_output_buf)
  self.state.mission_dashboard_output_win = nil
  self.state.mission_dashboard_output_buf = nil
  self.state.mission_dashboard_output_entry = nil
  self.state.mission_dashboard_output_key = nil
  self.state.mission_dashboard_output_blocked_key = nil
  self.state.mission_dashboard_output_buf_kind = nil
  return true
end

for name, fn in pairs(output_buffer) do
  Output[name] = fn
end

for name, fn in pairs(output_preview) do
  Output[name] = fn
end

return Output
