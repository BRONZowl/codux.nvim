local terminal_mode = require("codux.terminal_mode")
local text_util = require("codux.text")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.startup_sequence_ready(controller)
  if controller.state.job_id == nil then
    return false
  end

  local lines = controller:terminal_screen_lines()
  if type(lines) ~= "table" then
    return false
  end

  local saw_ready_surface = false
  for index = #lines, 1, -1 do
    local line = trim(terminal_mode.strip_terminal_control_sequences(lines[index]):lower():gsub("%s+", " "))
    if line ~= "" then
      if line:find("booting mcp server", 1, true) or line:find("esc to interrupt", 1, true) then
        return false
      end
      saw_ready_surface = saw_ready_surface
        or line:match("^>") ~= nil
        or line:match("^›") ~= nil
        or line:match("^grok[>%s]") ~= nil
        or line:match("^%$") ~= nil
        or terminal_mode.detect_terminal_mode_from_line(line) ~= nil
    end
  end

  return saw_ready_surface
end

function M.startup_plan_command_busy(controller)
  local lines = controller:recent_terminal_lines(24)
  if type(lines) ~= "table" then
    return false
  end

  for index = #lines, 1, -1 do
    local line = trim(terminal_mode.strip_terminal_control_sequences(lines[index]):lower():gsub("%s+", " "))
    if line:find("'/plan' is disabled while a task is in progress", 1, true) then
      return true
    end
  end

  return false
end

local function startup_send_error(label, detail)
  local message = "Failed to send " .. label .. " to Codex"
  if detail ~= nil and tostring(detail) ~= "" then
    message = message .. ": " .. tostring(detail)
  end
  return message
end

function M.send_startup_input(controller, label, input)
  if type(controller) ~= "table" or type(controller.state) ~= "table" then
    return false, startup_send_error(label, "terminal is not available")
  end
  if not controller:terminal_running() or type(controller.state.job_id) ~= "number" then
    local message = startup_send_error(label, "terminal is not running")
    controller.state.last_startup_send_error = message
    return false, message
  end

  local send_ok, sent = pcall(vim.fn.chansend, controller.state.job_id, input)
  if send_ok and sent ~= 0 then
    controller.state.last_startup_send_error = nil
    return true, nil
  end

  local detail = send_ok and "broken pipe" or sent
  local message = startup_send_error(label, detail)
  controller.state.last_startup_send_error = message
  return false, message
end

function M.send_startup_plan_toggle(controller)
  local ok = M.send_startup_input(controller, "startup plan command", "\27[200~/plan\27[201~\r")
  return ok
end

function M.paste_startup_prompt(controller, initial_prompt)
  local paste = "\27[200~" .. initial_prompt .. "\27[201~\r"
  local paste_ok = M.send_startup_input(controller, "startup prompt", paste)
  if paste_ok then
    controller:mark_terminal_prompt_submission()
    controller:invalidate_terminal_prompt_tracking()
    controller:set_codex_working(true)
    return true
  end

  return false
end

function M.confirm_startup_plan_sequence(controller, initial_prompt, prompt_after_mode, attempts_remaining, retry_toggle, opts)
  opts = type(opts) == "table" and opts or {}
  attempts_remaining = tonumber(attempts_remaining) or 60
  retry_toggle = retry_toggle == true

  local function run(attempts_left)
    if not controller:terminal_running() then
      return
    end

    local mode = controller:sync_terminal_mode_from_buffer()
    if mode == "plan" then
      controller:set_mode("plan")
      if prompt_after_mode then
        controller:paste_startup_prompt(initial_prompt)
      end
      return
    end

    if mode == "execute" and retry_toggle then
      if controller:send_startup_plan_toggle() then
        retry_toggle = false
      end
      if attempts_left > 0 and type(vim.defer_fn) == "function" then
        vim.defer_fn(function()
          run(attempts_left - 1)
        end, 250)
        return
      end
    end

    if controller:startup_plan_command_busy() then
      controller:send_startup_plan_toggle()
    end

    if attempts_left > 0 and type(vim.defer_fn) == "function" then
      vim.defer_fn(function()
        run(attempts_left - 1)
      end, 250)
      return
    end

    if opts.suppress_warning ~= true then
      controller.notify("Codex did not confirm plan mode on startup", vim.log.levels.WARN)
    end
  end

  if type(vim.defer_fn) == "function" then
    vim.defer_fn(function()
      run(attempts_remaining - 1)
    end, 250)
  else
    run(0)
  end
end

function M.schedule_startup_plan_sequence(controller, initial_prompt, prompt_after_mode, attempts_remaining, opts)
  opts = type(opts) == "table" and opts or {}
  attempts_remaining = tonumber(attempts_remaining) or 20
  local settle_ms = math.max(250, tonumber(controller:config().startup_plan_settle_ms) or 4000)

  local function run(attempts_left)
    if not controller:terminal_running() then
      return
    end

    local mode = controller:sync_terminal_mode_from_buffer()
    if mode == "plan" then
      controller:set_mode("plan")
      if prompt_after_mode then
        controller:paste_startup_prompt(initial_prompt)
      end
      return
    end

    if mode == "execute" then
      if not controller:send_startup_plan_toggle() then
        return
      end

      controller:confirm_startup_plan_sequence(initial_prompt, prompt_after_mode, nil, false, {
        suppress_warning = opts.suppress_warning,
      })
      return
    end

    if not controller:startup_sequence_ready() then
      if attempts_left > 0 and type(vim.defer_fn) == "function" then
        vim.defer_fn(function()
          run(attempts_left - 1)
        end, 250)
      end
      return
    end

    local function send_after_settle()
      if not controller:terminal_running() then
        return
      end

      local settled_mode = controller:sync_terminal_mode_from_buffer()
      if settled_mode == "plan" then
        controller:set_mode("plan")
        if prompt_after_mode then
          controller:paste_startup_prompt(initial_prompt)
        end
        return
      end

      if not controller:send_startup_plan_toggle() then
        return
      end

      controller:confirm_startup_plan_sequence(initial_prompt, prompt_after_mode, nil, false, {
        suppress_warning = opts.suppress_warning,
      })
    end

    if type(vim.defer_fn) == "function" then
      vim.defer_fn(send_after_settle, settle_ms)
    else
      send_after_settle()
    end
  end

  if type(vim.defer_fn) == "function" then
    vim.defer_fn(function()
      run(attempts_remaining - 1)
    end, 250)
  else
    run(0)
  end
end

function M.schedule_startup_prompt(controller, initial_prompt, attempts_remaining)
  attempts_remaining = tonumber(attempts_remaining) or 20
  if type(initial_prompt) ~= "string" or initial_prompt == "" then
    return false
  end

  local function run(attempts_left)
    if not controller:terminal_running() then
      return
    end

    if controller:startup_sequence_ready() then
      controller:paste_startup_prompt(initial_prompt)
      return
    end

    if attempts_left > 0 and type(vim.defer_fn) == "function" then
      vim.defer_fn(function()
        run(attempts_left - 1)
      end, 250)
    end
  end

  if type(vim.defer_fn) == "function" then
    vim.defer_fn(function()
      run(attempts_remaining - 1)
    end, 250)
  else
    run(0)
  end

  return true
end

function M.ensure_plan_mode(controller, opts)
  opts = type(opts) == "table" and opts or {}
  local attempts = math.max(1, tonumber(opts.attempts) or 60)
  local sleep_ms = math.max(1, tonumber(opts.sleep_ms) or 250)
  local retry_toggle = opts.retry_toggle == true
  local sent_toggle = false

  if not controller:terminal_running() then
    return false
  end

  for attempt = 1, attempts do
    local mode = controller:sync_terminal_mode_from_buffer()
    if mode == "plan" then
      controller:set_mode("plan")
      return true
    end

    if not sent_toggle then
      sent_toggle = controller:send_startup_plan_toggle()
    elseif controller:startup_plan_command_busy() then
      controller:send_startup_plan_toggle()
    elseif mode == "execute" and retry_toggle then
      if controller:send_startup_plan_toggle() then
        retry_toggle = false
      end
    end

    if attempt < attempts then
      pcall(vim.fn.sleep, tostring(sleep_ms) .. "m")
    end
  end

  local mode = controller:sync_terminal_mode_from_buffer()
  if mode == "plan" then
    controller:set_mode("plan")
    return true
  end

  return false
end

return M
