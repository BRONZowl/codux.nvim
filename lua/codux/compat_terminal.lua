local command_util_mod = require("codux.command")

local M = {}

function M.install_terminal(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local terminal = deps.terminal
  local command_util = type(deps.command_util) == "table" and deps.command_util or command_util_mod

  function api.mark_terminal_prompt_submission()
    return terminal:mark_terminal_prompt_submission()
  end

  function api.plan_question_pending()
    return terminal:plan_question_pending()
  end

  function api.sync_terminal_mode_from_buffer()
    return terminal:sync_terminal_mode_from_buffer()
  end

  function api.schedule_terminal_buffer_observation()
    return terminal:schedule_terminal_buffer_observation()
  end

  function api.command_with_args(command, args)
    return command_util.with_args(command, args)
  end

  function api.toml_basic_string(value)
    return command_util.toml_basic_string(value)
  end

  function api.command_with_developer_instructions(command, instructions)
    return command_util.with_developer_instructions(command, instructions)
  end

  function api.remote_terminal_snapshot(max_lines)
    max_lines = math.max(1, tonumber(max_lines) or 14)
    return terminal:terminal_snapshot(max_lines) or ""
  end

  function api.remote_send_to_codex(message)
    return terminal:send_to_codex(tostring(message or "")) and "ok" or "failed"
  end

  function api.remote_select_codex_question_option(option, with_note)
    return terminal:select_codex_question_option(tostring(option or ""), with_note == true) and "ok" or "failed"
  end

  function api.remote_submit_codex_question_note(note)
    return terminal:submit_codex_question_note(tostring(note or "")) and "ok" or "failed"
  end

  function api.remote_interrupt_codex_session()
    return terminal:interrupt_codex_session() and "ok" or "failed"
  end

  function api.remote_switch_codex_mode()
    return terminal:toggle_plan_mode() and "ok" or "failed"
  end

  function api.remote_show_existing_codex_terminal()
    if not terminal:terminal_running() then
      return "not_running"
    end
    return terminal:open_window(true) and "ok" or "failed"
  end

  function api.remote_workspace_status()
    return terminal:terminal_running() and "ready" or "not_running"
  end

  function api.suppress_startup_plan_warning_for_workspace(workspace)
    return type(workspace) == "table" and type(workspace.mission_id) == "string" and workspace.mission_id ~= ""
  end

  function api.remote_ensure_plan_mode()
    return terminal:ensure_plan_mode() and "ok" or "failed"
  end

  return api
end

return M
