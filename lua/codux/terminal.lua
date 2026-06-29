local M = {}
M.__index = M

local command_util = require("codux.command")
local ui = require("codux.ui")

local function noop() end

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local is_valid_buf = ui.is_valid_buf
local is_loaded_buf = ui.is_loaded_buf
local is_valid_win = ui.is_valid_win
local window_buffer = ui.window_buffer
local buffer_lines = ui.buffer_lines

local function now_ms()
  local loop = vim.uv or vim.loop
  if loop and type(loop.now) == "function" then
    return loop.now()
  end
  if loop and type(loop.hrtime) == "function" then
    return math.floor(loop.hrtime() / 1000000)
  end

  return os.time() * 1000
end

function M.mode_display_label(mode)
  if mode == "execute" then
    return "exec"
  end

  return mode or "not running"
end

function M.strip_terminal_control_sequences(value)
  return tostring(value or "")
    :gsub("\27%][^\7]*\7", "")
    :gsub("\27%][^\27]*\27\\", "")
    :gsub("\27%[[0-?]*[ -/]*[@-~]", "")
    :gsub("\27[@-_]", "")
    :gsub("\r", "")
    :gsub("[%z\1-\8\11-\12\14-\31\127]", "")
end

function M.detect_terminal_mode_from_lines(lines, first_index)
  if type(lines) ~= "table" then
    return nil
  end

  first_index = math.max(1, tonumber(first_index) or 1)
  local start_index = math.max(first_index, #lines - 39)
  local saw_execute = false
  local saw_plan = false

  for index = #lines, start_index, -1 do
    local line = trim(M.strip_terminal_control_sequences(lines[index]):lower():gsub("%s+", " "))
    if line ~= "" then
      saw_execute = saw_execute or line:find("%f[%w]execute%f[%W]") ~= nil
      saw_plan = saw_plan or line:find("%f[%w]plan%f[%W]") ~= nil
      if saw_execute and saw_plan then
        return nil
      end
    end
  end

  if saw_execute then
    return "execute"
  end
  if saw_plan then
    return "plan"
  end

  return nil
end

function M.output_looks_like_question(lines, first_index)
  if type(lines) ~= "table" then
    return false
  end

  first_index = math.max(1, tonumber(first_index) or 1)
  local start_index = math.max(first_index, #lines - 79)
  for index = #lines, start_index, -1 do
    local line = trim(M.strip_terminal_control_sequences(lines[index]))
    if line ~= "" and line:match("%?[%]%)}\"'`%s]*$") then
      return true
    end
  end

  return false
end

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local controller = {
    state = type(opts.state) == "table" and opts.state or {},
    defaults = type(opts.defaults) == "table" and opts.defaults or {},
    get_config = type(opts.get_config) == "function" and opts.get_config or function()
      return {}
    end,
    notify = type(opts.notify) == "function" and opts.notify or noop,
    augroup = opts.augroup,
    command_util = type(opts.command_util) == "table" and opts.command_util or command_util,
    ui = type(opts.ui) == "table" and opts.ui or ui,
    sync_workspace_activity = type(opts.sync_workspace_activity) == "function" and opts.sync_workspace_activity or noop,
    reset_workspace_runtime = type(opts.reset_workspace_runtime) == "function" and opts.reset_workspace_runtime or noop,
    capture_workspace_session = type(opts.capture_workspace_session) == "function" and opts.capture_workspace_session or noop,
    refresh_which_key = type(opts.refresh_which_key) == "function" and opts.refresh_which_key or noop,
    refresh_which_key_header = type(opts.refresh_which_key_header) == "function" and opts.refresh_which_key_header or noop,
    update_terminal_mode_mapping = type(opts.update_terminal_mode_mapping) == "function" and opts.update_terminal_mode_mapping
      or noop,
    start_token_monitor_timer = type(opts.start_token_monitor_timer) == "function" and opts.start_token_monitor_timer
      or noop,
    stop_token_monitor_timer = type(opts.stop_token_monitor_timer) == "function" and opts.stop_token_monitor_timer or noop,
  }

  return setmetatable(controller, M)
end

function M:config()
  local config = self.get_config()
  if type(config) ~= "table" then
    return {}
  end
  return config
end

function M:valid_buf()
  return is_loaded_buf(self.state.buf)
end

function M:valid_win()
  local bufnr = window_buffer(self.state.win)
  return bufnr ~= nil and bufnr == self.state.buf and self:valid_buf()
end

function M:clear_stale_buffer()
  if self.state.buf ~= nil and not is_valid_buf(self.state.buf) then
    self.state.buf = nil
  end
end

function M:delete_buffer_deferred(bufnr)
  if not is_valid_buf(bufnr) then
    return
  end

  vim.defer_fn(function()
    if is_valid_buf(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end, 100)
end

function M:set_mode(mode)
  if self.state.mode == mode then
    return
  end

  self.state.mode = mode
  if
    mode ~= "plan"
    and type(self.state.workspace) == "table"
    and self.state.workspace.codex_status == "question"
  then
    self.sync_workspace_activity("idle")
  end
  self.refresh_which_key()
  self.refresh_which_key_header()
end

function M:terminal_running()
  if self.state.job_id == nil then
    self.stop_token_monitor_timer()
    self.state.last_prompt_line = nil
    self:set_codex_working(false, { force_idle = true })
    self:set_mode("not running")
    return false
  end

  if not self:valid_buf() then
    pcall(vim.fn.jobstop, self.state.job_id)
    self.state.exiting_jobs[self.state.job_id] = nil
    self.state.job_id = nil
    self.stop_token_monitor_timer()
    self.state.last_prompt_line = nil
    self:set_codex_working(false, { force_idle = true })
    self:set_mode("not running")
    return false
  end

  local wait_ok, statuses = pcall(vim.fn.jobwait, { self.state.job_id }, 0)
  if not wait_ok or type(statuses) ~= "table" then
    self.state.exiting_jobs[self.state.job_id] = nil
    self.state.job_id = nil
    self.stop_token_monitor_timer()
    self.state.last_prompt_line = nil
    self:set_codex_working(false, { force_idle = true })
    self:set_mode("not running")
    return false
  end

  if statuses[1] == -1 then
    return true
  end

  self.state.job_id = nil
  self.stop_token_monitor_timer()
  self.state.last_prompt_line = nil
  self:set_codex_working(false, { force_idle = true })
  self:set_mode("not running")
  return false
end

function M:focus_terminal_prompt(input)
  if not self:valid_win() then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(self.state.buf)
  pcall(vim.api.nvim_win_set_cursor, self.state.win, { line_count, 0 })
  pcall(vim.cmd, "startinsert")

  if type(input) == "string" and input ~= "" and self:terminal_running() then
    pcall(vim.fn.chansend, self.state.job_id, input)
  end

  return true
end

function M:toggle_mode_state()
  self:set_mode(self.state.mode == "plan" and "execute" or "plan")
  self.notify("Codex mode: " .. self.state.mode)
end

function M:send_mode_toggle_sequence(sequence)
  if not self:terminal_running() then
    self.notify("Codex terminal is not running", vim.log.levels.WARN)
    return false
  end

  local send_ok, sent = pcall(vim.fn.chansend, self.state.job_id, sequence)
  if not send_ok or sent == 0 then
    self.notify("Failed to toggle Codex plan mode", vim.log.levels.ERROR)
    return false
  end

  self:toggle_mode_state()
  vim.defer_fn(function()
    self:sync_terminal_mode_from_buffer()
  end, 150)
  return true
end

function M:toggle_plan_mode()
  return self:send_mode_toggle_sequence("\27[200~/plan\27[201~\r")
end

function M:send_shift_tab_mode_toggle()
  return self:send_mode_toggle_sequence("\27[Z")
end

function M:reset_terminal_command_tail()
  self.state.terminal_command_tail = ""
end

function M:append_terminal_command_tail(input)
  self.state.terminal_command_tail = ((self.state.terminal_command_tail or "") .. input):sub(-5)
end

function M:terminal_tail_key(input)
  return function()
    if not self:terminal_running() then
      return false
    end

    self:append_terminal_command_tail(input)
    local send_ok, sent = pcall(vim.fn.chansend, self.state.job_id, input)
    return send_ok and sent ~= 0
  end
end

function M:terminal_prompt_key(input)
  return function()
    return self:focus_terminal_prompt(input)
  end
end

function M:focus_window()
  if not self:valid_win() then
    return false
  end

  local focus_ok = pcall(vim.api.nvim_set_current_win, self.state.win)
  if not focus_ok then
    self.state.win = nil
    return false
  end
  if self:terminal_running() then
    self:focus_terminal_prompt()
  end

  return true
end

function M:dimension(value, total, fallback)
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

function M:popup_config()
  local popup = self:config().popup or {}
  local total_width = vim.o.columns
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local has_border = popup.border ~= nil and popup.border ~= "none"
  local available_width = math.max(1, total_width - (has_border and 2 or 0))
  local available_height = math.max(1, total_height - (has_border and 2 or 0))
  local width = math.min(available_width, self:dimension(popup.width, available_width, 0.85))
  local height = math.min(available_height, self:dimension(popup.height, available_height, 0.85))
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

function M:popup_focus_lock_enabled()
  local popup = self:config().popup or {}
  return popup.lock_focus ~= false
end

function M:schedule_popup_focus_lock()
  if self.state.closing_popup or self.state.focus_lock_pending then
    return
  end
  if not self:popup_focus_lock_enabled() or not self:valid_win() then
    return
  end

  self.state.focus_lock_pending = true
  vim.schedule(function()
    self.state.focus_lock_pending = false
    if self.state.closing_popup or not self:popup_focus_lock_enabled() or not self:valid_win() then
      return
    end

    local current_ok, current_win = pcall(vim.api.nvim_get_current_win)
    if current_ok and current_win == self.state.win then
      return
    end

    self:focus_window()
  end)
end

local working_frames = {
  " codex is working    ",
  " codex is working.   ",
  " codex is working..  ",
  " codex is working... ",
}

function M:stop_working_timer()
  local timer = self.state.working_timer
  self.state.working_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

function M:stop_working_idle_timer()
  local timer = self.state.working_idle_timer
  self.state.working_idle_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

function M:close_working_indicator()
  self:stop_working_timer()

  self.ui.close_window(self.state.working_win)
  self.state.working_win = nil

  self.ui.delete_buffer(self.state.working_buf)
  self.state.working_buf = nil
  self.state.working_frame = 1
end

function M:working_idle_ms()
  local value = tonumber(self:config().working_idle_ms)
  if value == nil or value < 500 then
    return self.defaults.working_idle_ms
  end

  return value
end

function M:start_working_idle_timer()
  if self.state.working_idle_timer then
    return
  end

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  self.state.working_idle_timer = timer
  timer:start(self:working_idle_ms(), 500, vim.schedule_wrap(function()
    if not self.state.codex_working then
      self:stop_working_idle_timer()
      return
    end

    if not self:terminal_running() then
      self:set_codex_working(false, { force_idle = true })
      return
    end

    if now_ms() - self.state.last_working_activity >= self:working_idle_ms() then
      self:set_codex_working(false)
      return
    end

    self:update_working_indicator()
  end))
end

function M:mark_terminal_prompt_submission()
  if not self:valid_buf() then
    self.state.last_prompt_line = nil
    return
  end

  self.state.last_prompt_line = vim.api.nvim_buf_line_count(self.state.buf)
end

function M:plan_question_pending()
  if self.state.mode ~= "plan" or not self:valid_buf() or type(self.state.last_prompt_line) ~= "number" then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(self.state.buf)
  local start_line = math.max(0, math.min(self.state.last_prompt_line, line_count))
  local lines = buffer_lines(self.state.buf, start_line, line_count)
  return M.output_looks_like_question(lines)
end

function M:set_codex_working(working, opts)
  opts = opts or {}
  local was_working = self.state.codex_working == true
  self.state.codex_working = working == true
  if not self.state.codex_working then
    local codex_status = "idle"
    if was_working and opts.force_idle ~= true and self:plan_question_pending() then
      codex_status = "question"
    end
    self.sync_workspace_activity(codex_status)
    self.state.last_working_activity = 0
    self:stop_working_idle_timer()
    self:close_working_indicator()
  else
    self.sync_workspace_activity("working")
    self.state.last_working_activity = now_ms()
    self:start_working_idle_timer()
    self:update_working_indicator()
  end
end

function M:note_terminal_activity()
  if not self.state.codex_working then
    return
  end

  self.state.last_working_activity = now_ms()
  self:update_working_indicator()
end

function M:sync_terminal_mode_from_buffer()
  if self.state.job_id == nil or not self:valid_buf() then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(self.state.buf)
  local start_line = math.max(0, line_count - 40)
  local lines = buffer_lines(self.state.buf, start_line, line_count)
  local mode = M.detect_terminal_mode_from_lines(lines)
  if mode ~= nil and mode ~= self.state.mode then
    self:set_mode(mode)
  end

  return mode
end

function M:schedule_terminal_buffer_observation()
  if self.state.terminal_mode_sync_pending then
    return
  end

  self.state.terminal_mode_sync_pending = true
  vim.schedule(function()
    self.state.terminal_mode_sync_pending = false
    self:note_terminal_activity()
    self:sync_terminal_mode_from_buffer()
  end)
end

function M:attach_terminal_activity(bufnr)
  if self.state.terminal_attached_buf == bufnr then
    return
  end

  self.state.terminal_attached_buf = bufnr
  local attach_ok = pcall(vim.api.nvim_buf_attach, bufnr, false, {
    on_lines = function(_, attached_buf)
      if attached_buf == self.state.buf then
        self:schedule_terminal_buffer_observation()
      end
    end,
    on_detach = function(_, attached_buf)
      if self.state.terminal_attached_buf == attached_buf then
        self.state.terminal_attached_buf = nil
      end
    end,
  })

  if not attach_ok then
    self.state.terminal_attached_buf = nil
  end
end

function M:working_indicator_config()
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

function M:render_working_indicator()
  if not is_loaded_buf(self.state.working_buf) then
    return
  end

  local frame = working_frames[self.state.working_frame] or working_frames[1]
  self.ui.set_lines(self.state.working_buf, { frame })
end

function M:ensure_working_indicator()
  if is_valid_win(self.state.working_win) then
    pcall(vim.api.nvim_win_set_config, self.state.working_win, self:working_indicator_config())
    return true
  end

  if not is_loaded_buf(self.state.working_buf) then
    local bufnr = self.ui.create_scratch_buffer({
      bufhidden = "wipe",
      modifiable = true,
    })
    if not bufnr then
      self.state.working_buf = nil
      return false
    end

    self.state.working_buf = bufnr
  end

  self:render_working_indicator()
  local win_ok, win = pcall(vim.api.nvim_open_win, self.state.working_buf, false, self:working_indicator_config())
  if not win_ok then
    self.state.working_win = nil
    return false
  end

  self.state.working_win = win
  self.ui.set_window_options(win, {
    winblend = 10,
    wrap = false,
  })
  return true
end

function M:start_working_timer()
  if self.state.working_timer then
    return
  end

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  self.state.working_timer = timer
  timer:start(0, 450, vim.schedule_wrap(function()
    if not is_valid_win(self.state.working_win) then
      self:stop_working_timer()
      return
    end

    self.state.working_frame = (self.state.working_frame % #working_frames) + 1
    self:render_working_indicator()
  end))
end

function M:working_activity_is_stale()
  return self.state.last_working_activity == 0 or now_ms() - self.state.last_working_activity >= self:working_idle_ms()
end

function M:update_working_indicator()
  if self.state.codex_working and self:working_activity_is_stale() then
    self:set_codex_working(false)
    return
  end

  if self.state.codex_working and self:terminal_running() and not self:valid_win() then
    if self:ensure_working_indicator() then
      self:start_working_timer()
    end
    return
  end

  self:close_working_indicator()
end

function M:submit_terminal_prompt()
  if not self:terminal_running() then
    return false
  end

  local send_ok, sent = pcall(vim.fn.chansend, self.state.job_id, "\r")
  if send_ok and sent ~= 0 then
    if self.state.terminal_command_tail == "/plan" then
      self:toggle_mode_state()
      vim.defer_fn(function()
        self:sync_terminal_mode_from_buffer()
      end, 150)
    else
      self:mark_terminal_prompt_submission()
      self:set_codex_working(true)
    end
    self:reset_terminal_command_tail()
    return true
  end

  return false
end

function M:interrupt_terminal_prompt()
  if not self:terminal_running() then
    return false
  end

  self:set_codex_working(false, { force_idle = true })
  self:reset_terminal_command_tail()
  local send_ok, sent = pcall(vim.fn.chansend, self.state.job_id, "\3")
  return send_ok and sent ~= 0
end

function M:ensure_buffer()
  if self:valid_buf() then
    return true
  end

  self:clear_stale_buffer()

  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "hide",
    filetype = "codux",
  })
  if not bufnr then
    self.state.buf = nil
    self.notify("Failed to create Codux terminal buffer", vim.log.levels.ERROR)
    return false
  end

  self.state.buf = bufnr
  pcall(vim.api.nvim_buf_set_name, bufnr, "codux://codex")
  self.ui.set_keymap(bufnr, { "n", "t" }, "<C-q>", function()
    return self:close()
  end, "Hide Codux Popup")
  self.ui.set_keymap(bufnr, "t", "<CR>", function()
    return self:submit_terminal_prompt()
  end, "Submit Codux Prompt", {
    nowait = true,
  })
  self.ui.set_keymap(bufnr, { "n", "t" }, "<C-c>", function()
    return self:interrupt_terminal_prompt()
  end, "Interrupt Codex", {
    nowait = true,
  })
  self.update_terminal_mode_mapping()
  for _, key in ipairs({
    { "/", "/" },
    { "p", "p" },
    { "l", "l" },
    { "a", "a" },
    { "n", "n" },
  }) do
    self.ui.set_keymap(bufnr, "t", key[1], self:terminal_tail_key(key[2]), "Type in Codux Prompt", {
      nowait = true,
    })
  end
  self.ui.set_keymap(bufnr, { "n", "t" }, "<S-Tab>", function()
    return self:send_shift_tab_mode_toggle()
  end, "Switch Codex Mode", {
    nowait = true,
  })
  self.ui.set_keymap(bufnr, "n", "<CR>", function()
    return self:focus_terminal_prompt()
  end, "Return to Codux Prompt")
  for _, key in ipairs(self.ui.printable_prompt_keys()) do
    local lhs = key[1]
    local input = key[2]
    self.ui.set_keymap(bufnr, "n", lhs, self:terminal_prompt_key(input), "Type in Codux Prompt")
  end
  self.ui.set_keymap(bufnr, "n", "q", function()
    return self:close()
  end, "Hide Codux Popup")

  pcall(vim.api.nvim_create_autocmd, { "BufUnload", "BufDelete", "BufWipeout" }, {
    group = self.augroup,
    buffer = bufnr,
    callback = function()
      if self.state.buf == bufnr then
        self.state.buf = nil
        self.state.job_id = nil
        self.state.last_prompt_line = nil
        self:set_codex_working(false, { force_idle = true })
        self:set_mode("not running")
      end
    end,
  })

  self:attach_terminal_activity(bufnr)

  return true
end

function M:open_window(focus)
  if not self:ensure_buffer() then
    return false
  end

  if self:valid_win() then
    local config_ok = pcall(vim.api.nvim_win_set_config, self.state.win, self:popup_config())
    if not config_ok then
      self.state.win = nil
      return self:open_window(focus)
    end
    self:close_working_indicator()
    pcall(vim.api.nvim_set_option_value, "wrap", true, { win = self.state.win })
    if focus then
      self:focus_window()
    end
    return true
  end

  self.state.win = nil

  local win_ok, win = pcall(vim.api.nvim_open_win, self.state.buf, focus == true, self:popup_config())
  if not win_ok then
    self.state.buf = nil
    if not self:ensure_buffer() then
      return false
    end
    win_ok, win = pcall(vim.api.nvim_open_win, self.state.buf, focus == true, self:popup_config())
  end
  if not win_ok then
    self.notify("Failed to open Codux popup", vim.log.levels.ERROR)
    return false
  end

  self.state.win = win
  self.state.closing_popup = false
  self:close_working_indicator()
  pcall(vim.api.nvim_set_option_value, "number", false, { win = self.state.win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = self.state.win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = self.state.win })
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = self.state.win })
  pcall(vim.api.nvim_set_option_value, "wrap", true, { win = self.state.win })

  local win_id = self.state.win
  if self.state.focus_lock_autocmd then
    pcall(vim.api.nvim_del_autocmd, self.state.focus_lock_autocmd)
    self.state.focus_lock_autocmd = nil
  end
  vim.api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    pattern = tostring(win_id),
    once = true,
    callback = function()
      if self.state.win == win_id then
        self.state.win = nil
        if self.state.focus_lock_autocmd then
          pcall(vim.api.nvim_del_autocmd, self.state.focus_lock_autocmd)
          self.state.focus_lock_autocmd = nil
        end
        self:update_working_indicator()
      end
    end,
  })
  self.state.focus_lock_autocmd = vim.api.nvim_create_autocmd("WinLeave", {
    group = self.augroup,
    callback = function()
      if self.state.win == win_id then
        self:schedule_popup_focus_lock()
      end
    end,
  })

  vim.api.nvim_clear_autocmds({ group = self.augroup, event = "VimResized" })
  vim.api.nvim_create_autocmd("VimResized", {
    group = self.augroup,
    callback = function()
      if self:valid_win() then
        pcall(vim.api.nvim_win_set_config, self.state.win, self:popup_config())
      end
      self:update_working_indicator()
    end,
  })

  if focus then
    self:focus_window()
  end

  return true
end

function M:start_terminal(focus, initial_prompt, command, workspace, permission_profile, opts)
  opts = opts or {}
  local hidden = opts.hidden == true

  if self:terminal_running() then
    if focus and not hidden then
      self:focus_window()
    end
    return true
  end

  command = command or self:config().codex_cmd

  local error_message = self.command_util.error(command)
  if error_message then
    self.notify(error_message, vim.log.levels.ERROR)
    return false
  end

  local executable = self.command_util.executable(command)
  if type(executable) == "string" and executable == "codex" and vim.fn.executable(executable) ~= 1 then
    self.notify("Codex CLI not found on PATH", vim.log.levels.WARN)
  end

  local previous_win = vim.api.nvim_get_current_win()
  if hidden then
    if not self:ensure_buffer() then
      return false
    end
  else
    if not self:open_window(true) then
      return false
    end

    if not self:valid_win() then
      self.notify("Codux popup is not attached to a valid buffer", vim.log.levels.ERROR)
      return false
    end

    local current_win_ok, current_win = pcall(vim.api.nvim_get_current_win)
    if not current_win_ok or current_win ~= self.state.win then
      local set_ok = pcall(vim.api.nvim_set_current_win, self.state.win)
      if not set_ok then
        self.state.win = nil
        return false
      end
    end

    if window_buffer(self.state.win) ~= self.state.buf then
      self.state.win = nil
      return self:start_terminal(focus, initial_prompt, command, workspace, permission_profile, opts)
    end
  end

  local job_id
  local session_capture_mtime = os.time() - 2
  local term_command = self.command_util.with_prompt(command, initial_prompt)
  local term_options = {
    on_exit = function(_, code)
      local expected_exit = self.state.exiting_jobs[job_id] == true
      local pending_delete_buffer = self.state.pending_delete_buffers[job_id]
      self.state.exiting_jobs[job_id] = nil
      self.state.pending_delete_buffers[job_id] = nil
      if self.state.job_id == job_id then
        self.state.job_id = nil
        self.state.permission_profile = "default"
        self.sync_workspace_activity("idle")
        self.state.last_prompt_line = nil
        self.reset_workspace_runtime()
        self.stop_token_monitor_timer()
        self:set_codex_working(false, { force_idle = true })
        self:set_mode("not running")
      end
      if not expected_exit and code ~= 0 then
        self.notify("Codex exited with code " .. tostring(code), vim.log.levels.WARN)
      end
      if pending_delete_buffer ~= nil then
        self:delete_buffer_deferred(pending_delete_buffer)
      end
    end,
  }

  local term_ok
  if hidden then
    term_ok, job_id = pcall(vim.api.nvim_buf_call, self.state.buf, function()
      return vim.fn.termopen(term_command, term_options)
    end)
  else
    term_ok, job_id = pcall(vim.fn.termopen, term_command, term_options)
  end

  if not term_ok or type(job_id) ~= "number" or job_id <= 0 then
    self.state.job_id = nil
    self.notify("Failed to start Codex", vim.log.levels.ERROR)
    if is_valid_win(previous_win) then
      pcall(vim.api.nvim_set_current_win, previous_win)
    end
    return false
  end

  self.state.job_id = job_id
  self.state.last_prompt_line = nil
  self.state.permission_profile = permission_profile or "default"
  self.state.last_permission_profile = self.state.permission_profile
  if workspace ~= nil then
    self.state.workspace = workspace
  end
  if self:valid_win() then
    pcall(vim.api.nvim_set_option_value, "wrap", true, { win = self.state.win })
  end
  self:set_mode("execute")
  self.start_token_monitor_timer()
  self:set_codex_working(type(initial_prompt) == "string" and initial_prompt ~= "")
  if opts.capture_workspace_session == true and workspace ~= nil then
    self.capture_workspace_session(workspace, session_capture_mtime)
  end

  if hidden then
    if is_valid_win(previous_win) then
      pcall(vim.api.nvim_set_current_win, previous_win)
    end
  elseif focus then
    pcall(vim.cmd, "startinsert")
  elseif is_valid_win(previous_win) then
    pcall(vim.api.nvim_set_current_win, previous_win)
  end

  return true
end

function M:ensure_codex(focus, initial_prompt)
  if self:terminal_running() then
    return self:open_window(focus)
  end

  if not self:config().auto_open then
    self.notify("Codex popup is not open", vim.log.levels.WARN)
    return false
  end

  return self:start_terminal(focus, initial_prompt, nil, nil, "default")
end

function M:open(opts)
  opts = opts or {}
  local focus = opts.focus
  if focus == nil then
    focus = true
  end

  if not self:valid_win() then
    if not self:open_window(focus) then
      return false
    end
  elseif focus then
    self:focus_window()
  end

  return self:start_terminal(focus, opts.initial_prompt, nil, nil, "default")
end

function M:restart_with_command(command, focus, permission_profile, initial_prompt)
  self:exit()
  return self:start_terminal(focus ~= false, initial_prompt, command, nil, permission_profile)
end

function M:start_hidden_with_command(command, permission_profile, initial_prompt)
  return self:start_terminal(false, initial_prompt, command, nil, permission_profile, { hidden = true })
end

function M:close()
  if self:valid_win() then
    self.state.closing_popup = true
    self.ui.close_window(self.state.win)
    self.state.win = nil
    self.state.closing_popup = false
    self:update_working_indicator()
    self.refresh_which_key()
    return true
  end

  return false
end

function M:toggle()
  if self:valid_win() then
    return self:close()
  end

  return self:open({ focus = true })
end

function M:exit()
  local job_id = self.state.job_id
  local bufnr = self.state.buf
  local running = self:terminal_running()

  if running and job_id ~= nil then
    self.state.exiting_jobs[job_id] = true
    if is_valid_buf(bufnr) then
      self.state.pending_delete_buffers[job_id] = bufnr
    end
    pcall(vim.fn.jobstop, job_id)
  end
  self.state.job_id = nil
  self.state.permission_profile = "default"
  self.sync_workspace_activity("idle")
  self.state.last_prompt_line = nil
  self.reset_workspace_runtime()
  self.stop_token_monitor_timer()
  self:set_codex_working(false, { force_idle = true })
  self:set_mode("not running")

  if self:valid_win() then
    self.ui.close_window(self.state.win)
  end
  self.state.win = nil

  self.state.buf = nil
  if not running and is_valid_buf(bufnr) then
    self:delete_buffer_deferred(bufnr)
  end
  self:set_codex_working(false, { force_idle = true })

  return true
end

function M:send_to_codex(message)
  local running = self:terminal_running()
  if not self:ensure_codex(self:config().auto_focus, running and nil or message) then
    return false
  end

  if not running then
    return true
  end

  if not self:terminal_running() then
    self.notify("Codex terminal is not running", vim.log.levels.WARN)
    return false
  end

  local paste = "\27[200~" .. message .. "\27[201~\r"
  local send_ok, sent = pcall(vim.fn.chansend, self.state.job_id, paste)
  if not send_ok or sent == 0 then
    self.notify("Failed to send prompt to Codex", vim.log.levels.ERROR)
    return false
  end

  self:mark_terminal_prompt_submission()
  self:set_codex_working(true)
  return true
end

function M:health_info()
  return {
    popup_visible = self:valid_win(),
    terminal_running = self:terminal_running(),
    terminal_buffer = self:valid_buf() and self.state.buf or nil,
    terminal_job_id = self.state.job_id,
    mode = self.state.mode,
    permission_profile = self.state.permission_profile,
    last_permission_profile = self.state.last_permission_profile,
    codex_working = self.state.codex_working,
    working_indicator_visible = is_valid_win(self.state.working_win),
  }
end

return M
