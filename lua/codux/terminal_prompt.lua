local terminal_mode = require("codux.terminal_mode")
local providers = require("codux.providers")
local text_util = require("codux.text")
local ui = require("codux.ui")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.reset_input(controller)
  controller.state.terminal_prompt_input = ""
  controller.state.terminal_prompt_tracking_valid = true
end

function M.invalidate_tracking(controller)
  controller.state.terminal_prompt_input = ""
  controller.state.terminal_prompt_tracking_valid = false
end

function M.append_input(controller, input)
  if controller.state.terminal_prompt_tracking_valid ~= true then
    return
  end
  controller.state.terminal_prompt_input = (controller.state.terminal_prompt_input or "") .. tostring(input or "")
end

function M.delete_input_char(controller)
  if controller.state.terminal_prompt_tracking_valid ~= true then
    return
  end
  local input = tostring(controller.state.terminal_prompt_input or "")
  local length = vim.fn.strchars(input)
  if length <= 0 then
    return
  end

  controller.state.terminal_prompt_input = vim.fn.strcharpart(input, 0, length - 1)
end

function M.clear_input_line(controller)
  controller:reset_terminal_prompt_input()
  if not controller:terminal_running() then
    return false
  end

  local send_ok, sent = pcall(vim.fn.chansend, controller.state.job_id, "\21")
  return send_ok and sent ~= 0
end

function M.schedule_clear_after_interrupt(controller, opts)
  opts = type(opts) == "table" and opts or {}
  controller:reset_terminal_prompt_input()
  if controller.state.terminal_prompt_clear_after_interrupt_pending == true then
    return true
  end

  controller.state.terminal_prompt_clear_after_interrupt_pending = true
  local attempts = math.max(1, tonumber(opts.attempts) or 12)
  local delay_ms = math.max(1, tonumber(opts.delay_ms) or 80)

  local function clear_when_ready(attempts_left)
    if not controller:terminal_running() then
      controller.state.terminal_prompt_clear_after_interrupt_pending = false
      return
    end

    if controller:startup_sequence_ready() then
      controller:clear_terminal_prompt_input_line()
      controller.state.terminal_prompt_clear_after_interrupt_pending = false
      return
    end

    if attempts_left <= 0 or type(vim.defer_fn) ~= "function" then
      controller.state.terminal_prompt_clear_after_interrupt_pending = false
      return
    end

    vim.defer_fn(function()
      clear_when_ready(attempts_left - 1)
    end, delay_ms)
  end

  if type(vim.defer_fn) == "function" then
    vim.defer_fn(function()
      clear_when_ready(attempts - 1)
    end, delay_ms)
  else
    clear_when_ready(0)
  end

  return true
end

function M.input_key(controller, input, opts)
  opts = type(opts) == "table" and opts or {}
  return function()
    if not controller:terminal_running() then
      return false
    end

    if opts.delete_previous then
      controller:delete_terminal_prompt_input_char()
    else
      controller:append_terminal_prompt_input(input)
    end
    local send_ok, sent = pcall(vim.fn.chansend, controller.state.job_id, input)
    return send_ok and sent ~= 0
  end
end

function M.buffer_prompt_is_plan_toggle(controller)
  if not controller:valid_buf() then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(controller.state.buf)
  local start_line = math.max(0, line_count - 4)
  local lines = ui.buffer_lines(controller.state.buf, start_line, line_count)
  if type(lines) ~= "table" then
    return false
  end

  for index = #lines, 1, -1 do
    local line = trim(terminal_mode.strip_terminal_control_sequences(lines[index]))
    if line ~= "" then
      return terminal_mode.terminal_line_is_plan_toggle(line)
    end
  end

  return false
end

function M.prompt_key(controller, input)
  return function()
    return controller:focus_terminal_prompt(input)
  end
end

function M.mark_submission(controller)
  if not controller:valid_buf() then
    controller.state.last_prompt_line = nil
    return
  end

  controller.state.last_prompt_line = vim.api.nvim_buf_line_count(controller.state.buf)
end

function M.plan_question_pending(controller)
  if controller.state.mode ~= "plan" or not controller:valid_buf() or type(controller.state.last_prompt_line) ~= "number" then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(controller.state.buf)
  local start_line = math.max(0, math.min(controller.state.last_prompt_line, line_count))
  local lines = ui.buffer_lines(controller.state.buf, start_line, line_count)
  return terminal_mode.output_looks_like_question(lines)
end

function M.submit(controller)
  if not controller:terminal_running() then
    return false
  end

  local input = tostring(controller.state.terminal_prompt_input or "")
  local tracking_valid = controller.state.terminal_prompt_tracking_valid == true
  local agent_provider = providers.normalize_provider(controller.state.agent_provider)
    or providers.normalize_provider(controller.state.last_agent_provider)
    or "codex"
  local submit_input = "\r"
  if agent_provider == "grok" and tracking_valid and trim(input) ~= "" then
    submit_input = "\21\27[200~" .. input .. "\27[201~\r"
  end

  local send_ok, sent = pcall(vim.fn.chansend, controller.state.job_id, submit_input)
  if send_ok and sent ~= 0 then
    if
      terminal_mode.terminal_prompt_is_plan_toggle(
        input,
        tracking_valid
      )
      and controller:terminal_buffer_prompt_is_plan_toggle()
    then
      controller:set_mode("plan")
      controller.notify("Codex mode: " .. controller.state.mode)
    else
      controller:mark_terminal_prompt_submission()
      controller:set_codex_working(true)
    end
    controller:reset_terminal_prompt_input()
    return true
  end

  return false
end

function M.interrupt(controller)
  if not controller:terminal_running() then
    return false
  end

  controller:set_codex_working(false, { force_idle = true })
  controller:reset_terminal_prompt_input()
  local send_ok, sent = pcall(vim.fn.chansend, controller.state.job_id, "\3")
  if not send_ok or sent == 0 then
    return false
  end

  controller:schedule_terminal_prompt_input_clear_after_interrupt()
  return true
end

return M
