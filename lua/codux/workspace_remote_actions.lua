local text_util = require("codux.text")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.workspace_interactive_preview(runtime, entry, opts)
  opts = type(opts) == "table" and opts or {}
  local workspace, ensure_error = runtime:ensure_workspace_remote(entry, {
    attempts = opts.remote_attempts or 1,
    sleep_ms = opts.remote_sleep_ms or 100,
  })
  if not workspace then
    return nil, ensure_error or "workspace is inactive"
  end

  local server = workspace.nvim_server or runtime:workspace_server_path(workspace.project_root, workspace.safe_name or workspace.name)
  local output, remote_error = runtime:remote_luaeval(
    server,
    "require('codux')._v5.remote_show_existing_codex_terminal()",
    { attempts = opts.attempts or 15, sleep_ms = opts.sleep_ms or 120 }
  )
  if output ~= "ok" then
    if output == "not_running" then
      return nil, "workspace Codex session is not running"
    end
    return nil, remote_error or output or "workspace Codex session is not reachable"
  end

  local session = runtime:current_tmux_session()
  if not session then
    return nil, "no tmux session running"
  end

  local preview_session = opts.preview_session or runtime:workspace_preview_session_name(workspace)
  runtime:kill_tmux_session(preview_session)
  local _, create_code = runtime:tmux_system({ "new-session", "-d", "-t", session, "-s", preview_session })
  if create_code ~= 0 then
    return nil, "failed to create Codux preview session"
  end

  local window_name = workspace.tmux_window
    or workspace.window_name
    or runtime.workspace_window_name(workspace.safe_name or workspace.name)
  local _, select_code = runtime:tmux_system({ "select-window", "-t", preview_session .. ":" .. window_name })
  if select_code ~= 0 then
    runtime:kill_tmux_session(preview_session)
    return nil, "failed to select Codux workspace preview window"
  end

  return {
    command = { "env", "-u", "TMUX", runtime:tmux_cmd(), "attach-session", "-f", "read-only", "-t", preview_session },
    preview_session = preview_session,
    workspace = workspace,
    window_name = window_name,
    window_id = workspace.window_id,
  }, nil
end

function M.close_workspace_interactive_preview(runtime, preview)
  local session_name = type(preview) == "table" and preview.preview_session or preview
  return runtime:kill_tmux_session(session_name)
end

function M.ensure_workspace_remote(runtime, entry, opts)
  opts = type(opts) == "table" and opts or {}
  entry = type(entry) == "table" and entry or {}
  local safe_name = entry.safe_name or entry.name
  local root = entry.project_root
  if type(safe_name) ~= "string" or safe_name == "" then
    return nil, "workspace name is required"
  end
  if type(root) ~= "string" or root == "" then
    return nil, "workspace root is required"
  end

  local window_name = entry.tmux_window or entry.window_name or runtime.workspace_window_name(safe_name)
  local attempts = math.max(1, tonumber(opts.attempts) or 1)
  local sleep_ms = math.max(1, tonumber(opts.sleep_ms) or 100)
  local last_error = "workspace is inactive"

  for attempt = 1, attempts do
    local session = runtime:current_tmux_session()
    if not session then
      last_error = "workspace is inactive"
    else
      local window_id = runtime:tmux_window_id(session, window_name)
      if not window_id then
        last_error = "workspace is inactive"
      elseif runtime:status_for_window(window_id) == "active" then
        entry.window_id = window_id
        entry.nvim_server = entry.nvim_server or runtime:workspace_server_path(root, safe_name)
        return entry, nil
      else
        last_error = "workspace is inactive"
      end
    end

    if attempt < attempts then
      pcall(vim.fn.sleep, tostring(sleep_ms) .. "m")
    end
  end

  return nil, last_error
end

function M.remote_workspace_call(runtime, entry, lua_expression, opts)
  opts = type(opts) == "table" and opts or {}
  local workspace = type(opts.workspace) == "table" and opts.workspace or nil
  local ensure_error = nil
  if not workspace then
    workspace, ensure_error = runtime:ensure_workspace_remote(entry, {
      attempts = opts.remote_attempts,
      sleep_ms = opts.remote_sleep_ms,
    })
  end
  if not workspace then
    return false, ensure_error or opts.missing_error or "workspace not found"
  end

  local server = workspace.nvim_server or runtime:workspace_server_path(workspace.project_root, workspace.safe_name or workspace.name)
  local output, remote_error = runtime:remote_luaeval(server, lua_expression, {
    attempts = opts.attempts or 15,
    sleep_ms = opts.sleep_ms or 120,
  })
  if output == "ok" then
    return true, nil, workspace
  end

  return false, remote_error or output or opts.error_message or "workspace command failed", workspace
end

function M.send_prompt_to_workspace(runtime, entry, prompt, opts)
  opts = type(opts) == "table" and opts or {}
  prompt = tostring(prompt or "")
  if trim(prompt) == "" then
    return false, "Prompt is required"
  end

  local plan_ok, plan_error, workspace = runtime:ensure_workspace_plan_mode(entry, {
    attempts = opts.plan_attempts or opts.attempts,
    sleep_ms = opts.plan_sleep_ms or opts.sleep_ms,
    remote_attempts = opts.remote_attempts,
    remote_sleep_ms = opts.remote_sleep_ms,
  })
  if not plan_ok then
    return false, plan_error or "Failed to switch workspace to plan mode"
  end

  return runtime:remote_workspace_call(entry, "require('codux')._v5.remote_send_to_codex(" .. runtime:lua_string(prompt) .. ")", {
    attempts = opts.attempts,
    sleep_ms = opts.sleep_ms,
    remote_attempts = opts.remote_attempts,
    remote_sleep_ms = opts.remote_sleep_ms,
    workspace = workspace,
    error_message = "Failed to send prompt",
  })
end

function M.select_workspace_question_option(runtime, entry, option, opts)
  opts = type(opts) == "table" and opts or {}
  option = trim(option)
  if option == "" then
    return false, "Option number is required"
  end
  if not option:match("^[1-4]$") then
    return false, "Option number must be 1, 2, 3, or 4"
  end

  return runtime:remote_workspace_call(
    entry,
    "require('codux')._v5.remote_select_codex_question_option("
      .. runtime:lua_string(option)
      .. ", "
      .. tostring(opts.with_note == true)
      .. ")",
    {
      attempts = opts.attempts,
      sleep_ms = opts.sleep_ms,
      remote_attempts = opts.remote_attempts,
      remote_sleep_ms = opts.remote_sleep_ms,
      error_message = "Failed to answer question",
    }
  )
end

function M.submit_workspace_question_note(runtime, entry, note, opts)
  opts = type(opts) == "table" and opts or {}
  note = tostring(note or "")
  if trim(note) == "" then
    return false, "Note is required"
  end

  return runtime:remote_workspace_call(
    entry,
    "require('codux')._v5.remote_submit_codex_question_note(" .. runtime:lua_string(note) .. ")",
    {
      attempts = opts.attempts,
      sleep_ms = opts.sleep_ms,
      remote_attempts = opts.remote_attempts,
      remote_sleep_ms = opts.remote_sleep_ms,
      error_message = "Failed to send question note",
    }
  )
end

function M.interrupt_workspace(runtime, entry, opts)
  opts = type(opts) == "table" and opts or {}
  return runtime:remote_workspace_call(entry, "require('codux')._v5.remote_interrupt_codex_session()", {
    attempts = opts.attempts,
    sleep_ms = opts.sleep_ms,
    remote_attempts = opts.remote_attempts,
    remote_sleep_ms = opts.remote_sleep_ms,
    error_message = "Failed to interrupt workspace",
  })
end

function M.switch_workspace_mode(runtime, entry, opts)
  opts = type(opts) == "table" and opts or {}
  return runtime:remote_workspace_call(entry, "require('codux')._v5.remote_switch_codex_mode()", {
    attempts = opts.attempts,
    sleep_ms = opts.sleep_ms,
    remote_attempts = opts.remote_attempts,
    remote_sleep_ms = opts.remote_sleep_ms,
    error_message = "Failed to switch workspace mode",
  })
end

function M.ensure_workspace_plan_mode(runtime, entry, opts)
  opts = type(opts) == "table" and opts or {}
  return runtime:remote_workspace_call(entry, "require('codux')._v5.remote_ensure_plan_mode()", {
    attempts = opts.attempts or 60,
    sleep_ms = opts.sleep_ms or 250,
    remote_attempts = opts.remote_attempts or 60,
    remote_sleep_ms = opts.remote_sleep_ms or 250,
    error_message = "Failed to switch workspace to plan mode",
  })
end

function M.verify_workspace_launch(runtime, workspace, opts)
  opts = type(opts) == "table" and opts or {}
  workspace = type(workspace) == "table" and workspace or {}
  local safe_name = workspace.safe_name or workspace.name
  local root = workspace.project_root
  local server = workspace.nvim_server or runtime:workspace_server_path(root, safe_name)
  local window_name = workspace.tmux_window or workspace.window_name or runtime.workspace_window_name(safe_name)
  local attempts = math.max(1, tonumber(opts.attempts) or 24)
  local sleep_ms = math.max(1, tonumber(opts.sleep_ms) or 500)
  local require_codex = opts.require_codex == true
  local last_error = "workspace did not become ready"

  for attempt = 1, attempts do
    local session = runtime:current_tmux_session()
    if not session then
      last_error = "no tmux session running"
    else
      local window_id = runtime:tmux_window_id(session, window_name)
      if not window_id then
        last_error = "workspace tmux window disappeared"
      elseif runtime:status_for_window(window_id) ~= "active" then
        last_error = "workspace Neovim process is not running"
      else
        workspace.window_id = window_id
        local output, remote_error =
          runtime:remote_luaeval(server, "require('codux')._v5.remote_workspace_status()", { attempts = 1 })
        if output == "ready" then
          return true, nil
        end
        if output == "not_running" then
          if not require_codex then
            return true, nil
          end
          last_error = "workspace Codex session is not running"
        else
          last_error = remote_error or output or "workspace Neovim server is not reachable"
        end
      end
    end

    if attempt < attempts then
      pcall(vim.fn.sleep, tostring(sleep_ms) .. "m")
    end
  end

  return false, last_error
end

return M
