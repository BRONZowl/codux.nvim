local Output = {}

local ui = require("codux.ui")

local function command_display(command)
  if type(command) == "table" then
    local parts = {}
    for _, part in ipairs(command) do
      table.insert(parts, tostring(part))
    end
    return table.concat(parts, " ")
  end
  return tostring(command or "")
end

local function preview_attach_error(command, detail)
  local message = "failed to attach workspace session preview"
  detail = tostring(detail or "")
  if detail ~= "" then
    message = message .. ": " .. detail
  end

  local display = command_display(command)
  if display ~= "" then
    message = message .. " (" .. display .. ")"
  end
  return message
end

local function role_cache_key(entry)
  entry = type(entry) == "table" and entry or {}
  return table.concat({
    tostring(entry.project_root or entry.worktree_path or ""),
    tostring(entry.safe_name or entry.name or entry.mission_role or ""),
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

function Output:output_preview_running()
  local job_id = self.state.mission_dashboard_output_job
  if type(job_id) ~= "number" or job_id <= 0 then
    return false
  end
  local ok, statuses = pcall(vim.fn.jobwait, { job_id }, 0)
  return ok and type(statuses) == "table" and statuses[1] == -1
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

function Output:output_buffer_buftype(bufnr)
  if not self.is_loaded_buf(bufnr) then
    return nil
  end
  local ok, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = bufnr })
  return ok and buftype or nil
end

function Output:attach_output_buffer_autocmd(bufnr)
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
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
  return true
end

function Output:create_output_buffer(kind, lines)
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

function Output:output_window_buffer()
  if not self.is_valid_win(self.state.mission_dashboard_output_win) then
    return nil
  end

  local ok, current = pcall(vim.api.nvim_win_get_buf, self.state.mission_dashboard_output_win)
  return ok and current or nil
end

function Output:unlock_output_window()
  local win = self.state.mission_dashboard_output_win
  if not self.is_valid_win(win) then
    return false
  end
  pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
  return true
end

function Output:set_output_window_buffer(bufnr)
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

function Output:replace_output_buffer(kind, lines)
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

function Output:ensure_output_buffer(kind, lines)
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

function Output:prepare_output_terminal_buffer()
  if not self:ensure_output_buffer("terminal") then
    return false
  end

  local bufnr = self.state.mission_dashboard_output_buf
  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
  return true
end

function Output:close_output_preview()
  local job_id = self.state.mission_dashboard_output_job
  self.state.mission_dashboard_output_job = nil
  if type(job_id) == "number" and job_id > 0 then
    pcall(self.jobstop, job_id)
  end
  local preview = self.state.mission_dashboard_output_preview
  self.state.mission_dashboard_output_preview = nil
  if preview then
    pcall(self.close_workspace_interactive_preview, preview)
  end
end

function Output:start_output_preview(entry)
  if not self.is_loaded_buf(self.state.mission_dashboard_output_buf) then
    return false
  end

  self:close_output_preview()
  self.state.mission_dashboard_output_generation = (tonumber(self.state.mission_dashboard_output_generation) or 0) + 1
  local generation = self.state.mission_dashboard_output_generation
  self.state.mission_dashboard_output_entry = entry
  self.state.mission_dashboard_output_key = self:output_entry_key(entry)
  self.state.mission_dashboard_output_blocked_key = nil
  if type(entry) ~= "table" then
    return self:render_output_status(entry, "select a workspace to preview")
  end
  if entry.status == "inactive" then
    return self:render_output_status(entry, "workspace is not active")
  end

  self:render_output_status(entry, "opening workspace session preview...")
  local preview, error_message = self.workspace_interactive_preview(entry)
  if not preview then
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, error_message or "workspace session preview unavailable")
  end

  local command = preview.command
  if type(command) ~= "table" and type(command) ~= "string" then
    self.close_workspace_interactive_preview(preview)
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, "workspace session preview command unavailable")
  end

  if not self:prepare_output_terminal_buffer() then
    self.close_workspace_interactive_preview(preview)
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, "workspace session preview buffer unavailable")
  end
  local preview_key = self.state.mission_dashboard_output_key
  local preview_buf = self.state.mission_dashboard_output_buf
  local term_ok, term_error = pcall(vim.api.nvim_buf_call, self.state.mission_dashboard_output_buf, function()
    return self.termopen(command, {
      on_exit = function(exited_job_id, code)
        if
          self.state.mission_dashboard_output_job == exited_job_id
          and self.state.mission_dashboard_output_generation == generation
          and self.state.mission_dashboard_output_key == preview_key
        then
          self.state.mission_dashboard_output_job = nil
          local active_entry = self.state.mission_dashboard_output_entry
          local active_key = self.state.mission_dashboard_output_key
          local active_preview = self.state.mission_dashboard_output_preview
          self.state.mission_dashboard_output_preview = nil
          if active_preview then
            pcall(self.close_workspace_interactive_preview, active_preview)
          end
          self.state.mission_dashboard_output_blocked_key = active_key
          self:render_output_status(active_entry, "workspace preview exited with code " .. tostring(code))
        end
      end,
    })
  end)
  if not term_ok or type(term_error) ~= "number" or term_error <= 0 then
    self.close_workspace_interactive_preview(preview)
    local detail = term_ok and ("invalid job id " .. tostring(term_error)) or term_error
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, preview_attach_error(command, detail))
  end

  self.state.mission_dashboard_output_job = term_error
  self.state.mission_dashboard_output_preview = preview
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-missions-output", { buf = preview_buf })
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

return Output
