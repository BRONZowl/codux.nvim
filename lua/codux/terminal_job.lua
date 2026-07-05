local ui = require("codux.ui")

local M = {}

local is_valid_buf = ui.is_valid_buf
local is_valid_win = ui.is_valid_win
local window_buffer = ui.window_buffer

local function normalize_initial_mode(mode)
  if mode == "execute" or mode == "plan" then
    return mode
  end

  return nil
end

function M.start(controller, focus, initial_prompt, command, workspace, permission_profile, opts)
  opts = opts or {}
  local hidden = opts.hidden == true
  local initial_mode = normalize_initial_mode(opts.initial_mode) or normalize_initial_mode(controller:config().default_initial_mode)
  local has_initial_prompt = type(initial_prompt) == "string" and initial_prompt ~= ""
  local apply_initial_mode = initial_mode == "plan"
  local prompt_after_mode = apply_initial_mode and has_initial_prompt

  if controller:terminal_running() then
    if focus and not hidden then
      controller:focus_window()
    end
    return true
  end

  command = command or controller:config().codex_cmd

  local error_message = controller.command_util.error(command)
  if error_message then
    controller.notify(error_message, vim.log.levels.ERROR)
    return false
  end

  local executable = controller.command_util.executable(command)
  if type(executable) == "string" and executable == "codex" and vim.fn.executable(executable) ~= 1 then
    controller.notify("Codex CLI not found on PATH", vim.log.levels.WARN)
  end

  local previous_win = vim.api.nvim_get_current_win()
  controller:invalidate_terminal_prompt_tracking()
  if hidden then
    if not controller:ensure_buffer() then
      return false
    end
  else
    if not controller:open_window(true) then
      return false
    end

    if not controller:valid_win() then
      controller.notify("Codux popup is not attached to a valid buffer", vim.log.levels.ERROR)
      return false
    end

    local current_win_ok, current_win = pcall(vim.api.nvim_get_current_win)
    if not current_win_ok or current_win ~= controller.state.win then
      local set_ok = pcall(vim.api.nvim_set_current_win, controller.state.win)
      if not set_ok then
        controller.state.win = nil
        return false
      end
    end

    if window_buffer(controller.state.win) ~= controller.state.buf then
      controller.state.win = nil
      return controller:start_terminal(focus, initial_prompt, command, workspace, permission_profile, opts)
    end
  end

  local job_id
  local session_capture_mtime = os.time() - 2
  local command_prompt = initial_prompt
  if prompt_after_mode then
    command_prompt = nil
  end
  local term_command = controller.command_util.with_prompt(command, command_prompt)
  local term_options = {
    on_exit = function(_, code)
      local expected_exit = controller.state.exiting_jobs[job_id] == true
      local pending_delete_buffer = controller.state.pending_delete_buffers[job_id]
      controller.state.exiting_jobs[job_id] = nil
      controller.state.pending_delete_buffers[job_id] = nil
      if controller.state.job_id == job_id then
        controller.state.job_id = nil
        controller.state.permission_profile = "default"
        controller.sync_workspace_activity("idle")
        controller.state.last_prompt_line = nil
        controller:reset_terminal_prompt_input()
        controller.stop_token_monitor_timer()
        controller:set_codex_working(false, { force_idle = true })
        controller:set_mode("not running")
        controller.reset_workspace_runtime()
      end
      if not expected_exit and code ~= 0 then
        controller.notify("Codex exited with code " .. tostring(code), vim.log.levels.WARN)
      end
      if pending_delete_buffer ~= nil then
        controller:delete_buffer_deferred(pending_delete_buffer)
      end
    end,
  }

  local term_ok
  if hidden then
    term_ok, job_id = pcall(vim.api.nvim_buf_call, controller.state.buf, function()
      return vim.fn.termopen(term_command, term_options)
    end)
  else
    term_ok, job_id = pcall(vim.fn.termopen, term_command, term_options)
  end

  if not term_ok or type(job_id) ~= "number" or job_id <= 0 then
    controller.state.job_id = nil
    controller.notify("Failed to start Codex", vim.log.levels.ERROR)
    if is_valid_win(previous_win) then
      pcall(vim.api.nvim_set_current_win, previous_win)
    end
    return false
  end

  controller.state.job_id = job_id
  controller.state.last_prompt_line = nil
  controller:invalidate_terminal_prompt_tracking()
  controller.state.permission_profile = permission_profile or "default"
  controller.state.last_permission_profile = controller.state.permission_profile
  if workspace ~= nil then
    controller.state.workspace = workspace
  end
  if controller:valid_win() then
    pcall(vim.api.nvim_set_option_value, "wrap", true, { win = controller.state.win })
  end
  controller:set_mode("execute")
  controller.start_token_monitor_timer()
  controller:set_codex_working(has_initial_prompt and not prompt_after_mode)
  if apply_initial_mode then
    controller:schedule_startup_plan_sequence(initial_prompt, prompt_after_mode, nil, {
      suppress_warning = opts.suppress_startup_plan_warning == true,
    })
  end
  if opts.capture_workspace_session == true and workspace ~= nil then
    controller.capture_workspace_session(workspace, session_capture_mtime)
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

function M.ensure_codex(controller, focus, initial_prompt)
  if controller:terminal_running() then
    return controller:open_window(focus)
  end

  if not controller:config().auto_open then
    controller.notify("Codex popup is not open", vim.log.levels.WARN)
    return false
  end

  return controller:start_terminal(focus, initial_prompt, nil, nil, "default")
end

function M.open(controller, opts)
  opts = opts or {}
  local focus = opts.focus
  if focus == nil then
    focus = true
  end

  if not controller:valid_win() then
    if not controller:open_window(focus) then
      return false
    end
  elseif focus then
    controller:focus_window()
  end

  return controller:start_terminal(focus, opts.initial_prompt, nil, nil, "default", {
    initial_mode = opts.initial_mode,
  })
end

function M.restart_with_command(controller, command, focus, permission_profile, initial_prompt, opts)
  opts = type(opts) == "table" and opts or {}
  controller:exit()
  return controller:start_terminal(focus ~= false, initial_prompt, command, nil, permission_profile, {
    initial_mode = opts.initial_mode,
  })
end

function M.restart_hidden_with_command(controller, command, permission_profile, initial_prompt)
  controller:exit()
  return controller:start_terminal(false, initial_prompt, command, nil, permission_profile, { hidden = true })
end

function M.start_hidden_with_command(controller, command, permission_profile, initial_prompt)
  return controller:start_terminal(false, initial_prompt, command, nil, permission_profile, { hidden = true })
end

function M.toggle(controller)
  if controller:valid_win() then
    return controller:close()
  end

  return controller:open({ focus = true })
end

function M.exit(controller)
  local job_id = controller.state.job_id
  local bufnr = controller.state.buf
  local running = controller:terminal_running()

  if running and job_id ~= nil then
    controller.state.exiting_jobs[job_id] = true
    if is_valid_buf(bufnr) then
      controller.state.pending_delete_buffers[job_id] = bufnr
    end
    pcall(vim.fn.jobstop, job_id)
  end
  controller.state.job_id = nil
  controller.state.permission_profile = "default"
  controller.sync_workspace_activity("idle")
  controller.state.last_prompt_line = nil
  controller:reset_terminal_prompt_input()
  controller.stop_token_monitor_timer()
  controller:set_codex_working(false, { force_idle = true })
  controller:set_mode("not running")
  controller.reset_workspace_runtime()

  if controller:valid_win() then
    controller.ui.close_window(controller.state.win)
  end
  controller.state.win = nil

  controller.state.buf = nil
  if not running and is_valid_buf(bufnr) then
    controller:delete_buffer_deferred(bufnr)
  end
  controller:set_codex_working(false, { force_idle = true })

  return true
end

function M.send_to_codex(controller, message)
  local running = controller:terminal_running()
  if not controller:ensure_codex(controller:config().auto_focus, running and nil or message) then
    return false
  end

  if not running then
    return true
  end

  if not controller:terminal_running() then
    controller.notify("Codex terminal is not running", vim.log.levels.WARN)
    return false
  end

  local paste = "\27[200~" .. message .. "\27[201~\r"
  local send_ok, sent = pcall(vim.fn.chansend, controller.state.job_id, paste)
  if not send_ok or sent == 0 then
    controller.notify("Failed to send prompt to Codex", vim.log.levels.ERROR)
    return false
  end

  controller:mark_terminal_prompt_submission()
  controller:invalidate_terminal_prompt_tracking()
  controller:set_codex_working(true)
  return true
end

return M
