local M = {}
M.__index = M

local command_util = require("codux.command")
local terminal_job = require("codux.terminal_job")
local terminal_mode = require("codux.terminal_mode")
local terminal_prompt = require("codux.terminal_prompt")
local terminal_question = require("codux.terminal_question")
local terminal_startup = require("codux.terminal_startup")
local terminal_window = require("codux.terminal_window")
local ui = require("codux.ui")
local util = require("codux.util")
local working_indicator = require("codux.working_indicator")

local noop = util.noop
local now_ms = util.now_ms

local is_valid_buf = ui.is_valid_buf
local is_loaded_buf = ui.is_loaded_buf
local is_valid_win = ui.is_valid_win
local window_buffer = ui.window_buffer
local buffer_lines = ui.buffer_lines

local function workspace_mode_for(mode)
  if mode == "execute" or mode == "plan" then
    return mode
  end

  return nil
end

M.mode_display_label = terminal_mode.mode_display_label
M.strip_terminal_control_sequences = terminal_mode.strip_terminal_control_sequences
M.detect_terminal_mode_from_line = terminal_mode.detect_terminal_mode_from_line
M.detect_terminal_mode_from_lines = terminal_mode.detect_terminal_mode_from_lines
M.output_looks_like_question = terminal_mode.output_looks_like_question
M.terminal_prompt_is_plan_toggle = terminal_mode.terminal_prompt_is_plan_toggle
M.terminal_line_is_plan_toggle = terminal_mode.terminal_line_is_plan_toggle

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
    sync_workspace_mode = type(opts.sync_workspace_mode) == "function" and opts.sync_workspace_mode or noop,
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
  local workspace_mode = workspace_mode_for(mode)
  if self.state.mode == mode then
    self.sync_workspace_mode(workspace_mode)
    return
  end

  self.state.mode = mode
  self.sync_workspace_mode(workspace_mode)
  if
    mode ~= "plan"
    and type(self.state.workspace) == "table"
    and self.state.workspace.agent_status == "question"
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
    self:reset_terminal_prompt_input()
    self:set_agent_working(false, { force_idle = true })
    self:set_mode("not running")
    return false
  end

  if not self:valid_buf() then
    pcall(vim.fn.jobstop, self.state.job_id)
    self.state.exiting_jobs[self.state.job_id] = nil
    self.state.job_id = nil
    self.stop_token_monitor_timer()
    self.state.last_prompt_line = nil
    self:reset_terminal_prompt_input()
    self:set_agent_working(false, { force_idle = true })
    self:set_mode("not running")
    return false
  end

  local wait_ok, statuses = pcall(vim.fn.jobwait, { self.state.job_id }, 0)
  if not wait_ok or type(statuses) ~= "table" then
    self.state.exiting_jobs[self.state.job_id] = nil
    self.state.job_id = nil
    self.stop_token_monitor_timer()
    self.state.last_prompt_line = nil
    self:reset_terminal_prompt_input()
    self:set_agent_working(false, { force_idle = true })
    self:set_mode("not running")
    return false
  end

  if statuses[1] == -1 then
    return true
  end

  self.state.job_id = nil
  self.stop_token_monitor_timer()
  self.state.last_prompt_line = nil
  self:reset_terminal_prompt_input()
  self:set_agent_working(false, { force_idle = true })
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
    self:invalidate_terminal_prompt_tracking()
    pcall(vim.fn.chansend, self.state.job_id, input)
  end

  return true
end

function M:toggle_mode_state()
  self:set_mode(self.state.mode == "plan" and "execute" or "plan")
  self.notify("Agent mode: " .. self.state.mode)
end

function M:send_mode_toggle_sequence(sequence)
  if not self:terminal_running() then
    self.notify("Codux agent terminal is not running", vim.log.levels.WARN)
    return false
  end

  local send_ok, sent = pcall(vim.fn.chansend, self.state.job_id, sequence)
  if not send_ok or sent == 0 then
    self.notify("Failed to switch agent mode", vim.log.levels.ERROR)
    return false
  end

  self:toggle_mode_state()
  return true
end

function M:toggle_plan_mode()
  self:reset_terminal_prompt_input()
  return self:send_mode_toggle_sequence("\27[Z")
end

function M:send_shift_tab_mode_toggle()
  return self:toggle_plan_mode()
end

function M:reset_terminal_prompt_input()
  return terminal_prompt.reset_input(self)
end

function M:clear_terminal_prompt_input_line()
  return terminal_prompt.clear_input_line(self)
end

function M:schedule_terminal_prompt_input_clear_after_interrupt(opts)
  return terminal_prompt.schedule_clear_after_interrupt(self, opts)
end

function M:invalidate_terminal_prompt_tracking()
  return terminal_prompt.invalidate_tracking(self)
end

function M:append_terminal_prompt_input(input)
  return terminal_prompt.append_input(self, input)
end

function M:delete_terminal_prompt_input_char()
  return terminal_prompt.delete_input_char(self)
end

function M:terminal_input_key(input, opts)
  return terminal_prompt.input_key(self, input, opts)
end

function M:terminal_buffer_prompt_is_plan_toggle()
  return terminal_prompt.buffer_prompt_is_plan_toggle(self)
end

function M:terminal_prompt_key(input)
  return terminal_prompt.prompt_key(self, input)
end

function M:focus_window()
  return terminal_window.focus_window(self)
end

function M:dimension(value, total, fallback)
  return terminal_window.dimension(self, value, total, fallback)
end

function M:popup_config()
  return terminal_window.popup_config(self)
end

function M:popup_focus_lock_enabled()
  return terminal_window.popup_focus_lock_enabled(self)
end

function M:schedule_popup_focus_lock()
  return terminal_window.schedule_popup_focus_lock(self)
end

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
  return working_indicator.close(self)
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
    if not self.state.agent_working then
      self:stop_working_idle_timer()
      return
    end

    if not self:terminal_running() then
      self:set_agent_working(false, { force_idle = true })
      return
    end

    if now_ms() - self.state.last_working_activity >= self:working_idle_ms() then
      self:set_agent_working(false)
      return
    end

    self:update_working_indicator()
  end))
end

function M:mark_terminal_prompt_submission()
  return terminal_prompt.mark_submission(self)
end

function M:plan_question_pending()
  return terminal_prompt.plan_question_pending(self)
end

function M:set_agent_working(working, opts)
  opts = opts or {}
  local was_working = self.state.agent_working == true
  self.state.agent_working = working == true
  if not self.state.agent_working then
    local agent_status = "idle"
    if was_working and opts.force_idle ~= true and self:plan_question_pending() then
      agent_status = "question"
    end
    self.sync_workspace_activity(agent_status)
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

-- Legacy alias.
M.set_codex_working = M.set_agent_working

function M:note_terminal_activity()
  if not self.state.agent_working then
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
  return M.detect_terminal_mode_from_lines(lines)
end

function M:recent_terminal_lines(max_lines)
  if not self:valid_buf() then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(self.state.buf)
  local start_line = math.max(0, line_count - (tonumber(max_lines) or 80))
  return buffer_lines(self.state.buf, start_line, line_count)
end

function M:terminal_screen_height()
  if self:valid_win() then
    local ok, height = pcall(vim.api.nvim_win_get_height, self.state.win)
    if ok and type(height) == "number" and height > 0 then
      return height
    end
  end

  local height = tonumber(vim.o.lines) or 24
  local cmdheight = tonumber(vim.o.cmdheight) or 0
  return math.max(1, height - cmdheight)
end

function M:terminal_screen_lines()
  if not self:valid_buf() then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(self.state.buf)
  local screen_height = self:terminal_screen_height()
  local start_line = math.max(0, line_count - screen_height)
  return buffer_lines(self.state.buf, start_line, line_count)
end

function M:startup_sequence_ready()
  return terminal_startup.startup_sequence_ready(self)
end

function M:startup_plan_command_busy()
  return terminal_startup.startup_plan_command_busy(self)
end

function M:send_startup_plan_toggle()
  return terminal_startup.send_startup_plan_toggle(self)
end

function M:paste_startup_prompt(initial_prompt)
  return terminal_startup.paste_startup_prompt(self, initial_prompt)
end

function M:confirm_startup_plan_sequence(initial_prompt, prompt_after_mode, attempts_remaining, retry_toggle, opts)
  return terminal_startup.confirm_startup_plan_sequence(self, initial_prompt, prompt_after_mode, attempts_remaining, retry_toggle, opts)
end

function M:schedule_startup_plan_sequence(initial_prompt, prompt_after_mode, attempts_remaining, opts)
  return terminal_startup.schedule_startup_plan_sequence(self, initial_prompt, prompt_after_mode, attempts_remaining, opts)
end

function M:schedule_startup_prompt(initial_prompt, attempts_remaining)
  return terminal_startup.schedule_startup_prompt(self, initial_prompt, attempts_remaining)
end

function M:ensure_plan_mode(opts)
  return terminal_startup.ensure_plan_mode(self, opts)
end

function M:schedule_terminal_buffer_observation()
  if self.state.terminal_mode_sync_pending then
    return
  end

  self.state.terminal_mode_sync_pending = true
  vim.schedule(function()
    self.state.terminal_mode_sync_pending = false
    self:note_terminal_activity()
    local mode = self:sync_terminal_mode_from_buffer()
    if mode ~= nil then
      self:set_mode(mode)
    end
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
  return working_indicator.config(self)
end

function M:render_working_indicator()
  return working_indicator.render(self)
end

function M:ensure_working_indicator()
  return working_indicator.ensure(self)
end

function M:start_working_timer()
  return working_indicator.start_timer(self)
end

function M:working_activity_is_stale()
  return self.state.last_working_activity == 0 or now_ms() - self.state.last_working_activity >= self:working_idle_ms()
end

function M:update_working_indicator()
  return working_indicator.update(self)
end

function M:submit_terminal_prompt()
  return terminal_prompt.submit(self)
end

function M:interrupt_terminal_prompt()
  return terminal_prompt.interrupt(self)
end

function M:interrupt_agent_session()
  return terminal_prompt.interrupt(self)
end

M.interrupt_codex_session = M.interrupt_agent_session

function M:ensure_buffer()
  return terminal_window.ensure_buffer(self)
end

function M:open_window(focus)
  return terminal_window.open_window(self, focus)
end

function M:start_terminal(focus, initial_prompt, command, workspace, permission_profile, opts)
  return terminal_job.start(self, focus, initial_prompt, command, workspace, permission_profile, opts)
end

function M:ensure_agent(focus, initial_prompt)
  return terminal_job.ensure_agent(self, focus, initial_prompt)
end

M.ensure_codex = M.ensure_agent

function M:open(opts)
  return terminal_job.open(self, opts)
end

function M:restart_with_command(command, focus, permission_profile, initial_prompt, opts)
  return terminal_job.restart_with_command(self, command, focus, permission_profile, initial_prompt, opts)
end

function M:restart_hidden_with_command(command, permission_profile, initial_prompt)
  return terminal_job.restart_hidden_with_command(self, command, permission_profile, initial_prompt)
end

function M:start_hidden_with_command(command, permission_profile, initial_prompt)
  return terminal_job.start_hidden_with_command(self, command, permission_profile, initial_prompt)
end

function M:close()
  return terminal_window.close(self)
end

function M:toggle()
  return terminal_job.toggle(self)
end

function M:exit()
  return terminal_job.exit(self)
end

function M:send_to_agent(message)
  return terminal_job.send_to_agent(self, message)
end

M.send_to_codex = M.send_to_agent

function M:select_agent_question_option(option, with_note)
  return terminal_question.select_option(self, option, with_note)
end

M.select_codex_question_option = M.select_agent_question_option

function M:submit_agent_question_note(note)
  return terminal_question.submit_note(self, note)
end

M.submit_codex_question_note = M.submit_agent_question_note

function M:terminal_snapshot(max_lines)
  if not self:valid_buf() then
    return ""
  end

  max_lines = math.max(1, tonumber(max_lines) or 14)
  local line_count = vim.api.nvim_buf_line_count(self.state.buf)
  local start_line = math.max(0, line_count - max_lines)
  local lines = buffer_lines(self.state.buf, start_line, line_count)
  if type(lines) ~= "table" then
    return ""
  end

  return table.concat(lines, "\n")
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
    agent_provider = self.state.agent_provider,
    last_agent_provider = self.state.last_agent_provider,
    agent_working = self.state.agent_working,
    working_indicator_visible = is_valid_win(self.state.working_win),
  }
end

return M
