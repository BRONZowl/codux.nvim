local terminal_mod = require("codux.terminal")
local ui = require("codux.ui")
local command_util_mod = require("codux.command")
local workspace_create_mod = require("codux.workspace_create")
local workspace_manager_mod = require("codux.workspace_manager")
local workspace_runtime_mod = require("codux.workspace_runtime")

local M = {}

local permission_profiles = {
  {
    profile = "default",
    selector_label = "Default",
    keyed_label = "default",
    key = "d",
    desc = "Open Codex Default",
  },
  {
    profile = "auto",
    selector_label = "Autopilot",
    keyed_label = "auto",
    key = "a",
    desc = "Open Codex Auto",
  },
  {
    profile = "danger",
    selector_label = "Full Access",
    keyed_label = "full",
    key = "f",
    desc = "Open Codex Full Access",
  },
}

local function filter_completion(values, arglead)
  local matches = {}
  arglead = arglead or ""
  for _, value in ipairs(type(values) == "table" and values or {}) do
    if arglead == "" or tostring(value):find(arglead, 1, true) == 1 then
      table.insert(matches, value)
    end
  end
  return matches
end

function M.install(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local project_root = type(deps.project_root) == "function" and deps.project_root or function()
    return nil
  end
  local names_for_project = type(deps.names_for_project) == "function" and deps.names_for_project or function()
    return {}
  end
  local mission_names_for_project = type(deps.mission_names_for_project) == "function" and deps.mission_names_for_project
    or function()
      return {}
    end

  api.mode_display_label = terminal_mod.mode_display_label
  api.strip_terminal_control_sequences = terminal_mod.strip_terminal_control_sequences
  api.detect_terminal_mode_from_lines = terminal_mod.detect_terminal_mode_from_lines
  api.output_looks_like_question = terminal_mod.output_looks_like_question

  function api.permission_profile_choices()
    local choices = {}
    for _, spec in ipairs(permission_profiles) do
      table.insert(choices, { label = spec.selector_label, profile = spec.profile })
    end
    return choices
  end

  function api.keyed_permission_profile_choices()
    local choices = {}
    for _, spec in ipairs(permission_profiles) do
      table.insert(choices, {
        key = spec.key,
        label = spec.keyed_label,
        profile = spec.profile,
        desc = spec.desc,
      })
    end
    return choices
  end

  function api.should_select_permission_profile(job_id)
    return job_id == nil
  end

  function api.open_permission_profile_choice(choice, opts)
    opts = type(opts) == "table" and opts or {}
    if type(choice) ~= "table" then
      return false
    end

    local openers = {
      default = opts.open_default,
      auto = opts.open_auto,
      danger = opts.open_danger,
    }
    local opener = openers[choice.profile]
    if type(opener) == "function" then
      return opener(opts.initial_prompt, opts.open_opts)
    end
    return false
  end

  function api.select_permission_profile_open(opts)
    opts = type(opts) == "table" and opts or {}
    local selector = opts.selector or (vim.ui and vim.ui.select)
    if type(selector) ~= "function" then
      if type(opts.open_default) == "function" then
        return opts.open_default(opts.initial_prompt, opts.open_opts)
      end
      return false
    end

    return selector(api.permission_profile_choices(), {
      prompt = "Codex permission profile:",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      return api.open_permission_profile_choice(choice, opts)
    end)
  end

  function api.select_keyed_permission_profile_open(opts)
    opts = type(opts) == "table" and opts or {}
    local menu = opts.menu or ui.key_choice_menu
    if type(menu) ~= "function" then
      if type(opts.open_default) == "function" then
        return opts.open_default(opts.initial_prompt, opts.open_opts)
      end
      return false
    end

    return menu({
      title = " Codex permission profile ",
      choices = api.keyed_permission_profile_choices(),
      filetype = "codux-open-profile",
      cancel_desc = "Cancel Codux Open",
      create_error = "Failed to create Codux open menu",
      open_error = "Failed to open Codux open menu",
    }, function(choice)
      return api.open_permission_profile_choice(choice, opts)
    end)
  end

  api.filter_completion = filter_completion

  function api.complete_workspace_names(arglead)
    return api.filter_completion(names_for_project(project_root()), arglead)
  end

  function api.complete_mission_names(arglead)
    return api.filter_completion(mission_names_for_project(project_root()), arglead)
  end

  function api.complete_create(arglead, _cmdline, _cursorpos)
    return api.filter_completion({ "--custom" }, arglead)
  end

  return api
end

function M.install_ui(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local ui_mod = type(deps.ui) == "table" and deps.ui or ui
  local notify = type(deps.notify) == "function" and deps.notify or function() end

  function api.set_buffer_keymap(bufnr, modes, lhs, rhs, desc, opts)
    return ui_mod.set_keymap(bufnr, modes, lhs, rhs, desc, opts)
  end

  function api.bind_close_keys(bufnr, close_fn, desc, modes, opts)
    return ui_mod.bind_close_keys(bufnr, close_fn, desc, modes, opts)
  end

  function api.single_line_prompt(opts, callback)
    return ui_mod.single_line_prompt(opts, callback, {
      notify = notify,
      set_buffer_keymap = api.set_buffer_keymap,
      bind_close_keys = api.bind_close_keys,
    })
  end

  return api
end

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

function M.install_prompt_open(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local state = type(deps.state) == "table" and deps.state or {}
  local terminal = deps.terminal
  local open_with_keyed_profile_menu = deps.open_with_keyed_profile_menu

  function api.send_prompt_or_open_with_profile(message)
    if not api.should_select_permission_profile(state.job_id) then
      return terminal:send_to_codex(message)
    end

    return open_with_keyed_profile_menu({
      initial_prompt = message,
      open_opts = {
        initial_mode = "plan",
      },
    })
  end

  return api
end

function M.install_workspace_static(api)
  api = type(api) == "table" and api or {}

  function api.workspace_window_name(safe_name)
    return workspace_runtime_mod.workspace_window_name(safe_name)
  end

  return api
end

function M.install_workspace_runtime(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local runtime = deps.runtime
  local store = deps.store

  M.install_workspace_static(api)

  function api.tmux_window_command(window_id)
    return runtime:tmux_window_command(window_id)
  end

  function api.status_for_window(window_id)
    return runtime:status_for_window(window_id)
  end

  function api.dashboard_workspace_status(record, window_id)
    return runtime:dashboard_workspace_status(record, window_id)
  end

  function api.tmux_target(session, window_name)
    return workspace_runtime_mod.tmux_target(session, window_name)
  end

  function api.normalize_codex_session_id(value)
    return store.normalize_session_id(value)
  end

  function api.codex_home()
    return runtime:codex_home()
  end

  function api.codex_session_files()
    return runtime:codex_session_files()
  end

  function api.read_codex_session_meta(path)
    return runtime:read_codex_session_meta(path)
  end

  function api.codex_session_for_id(session_id)
    return runtime:codex_session_for_id(session_id)
  end

  function api.latest_codex_session_for_cwd(cwd, min_mtime)
    return runtime:latest_codex_session_for_cwd(cwd, min_mtime)
  end

  function api.workspace_instruction_files_config()
    return runtime:instruction_files_config()
  end

  function api.workspace_instruction_directory(root)
    return runtime:instruction_directory(root)
  end

  function api.workspace_instruction_file_path(root, safe_name)
    return runtime:instruction_file_path(root, safe_name)
  end

  function api.read_workspace_instruction_file(root, safe_name)
    return runtime:read_instruction_file(root, safe_name)
  end

  function api.write_workspace_instruction_file(root, safe_name, instruction)
    return runtime:write_instruction_file(root, safe_name, instruction)
  end

  function api.delete_workspace_instruction_file(root, safe_name)
    return runtime:delete_instruction_file(root, safe_name)
  end

  function api.workspace_instruction_file_records(root)
    return runtime:instruction_file_records(root)
  end

  function api.workspace_instruction_ignore_status(root)
    return runtime:workspace_instruction_ignore_status(root)
  end

  function api.normalize_record(record, safe_name, root)
    return runtime:normalize_record(record, safe_name, root)
  end

  function api.apply_codex_session_meta(workspace, meta)
    return runtime:apply_codex_session_meta(workspace, meta)
  end

  function api.resolve_workspace_resume_session(workspace)
    return runtime:resolve_workspace_resume_session(workspace)
  end

  function api.persist_workspace_session_meta(workspace, meta)
    return runtime:persist_workspace_session_meta(workspace, meta)
  end

  function api.schedule_workspace_session_capture(workspace, min_mtime)
    return runtime:schedule_workspace_session_capture(workspace, min_mtime)
  end

  function api.entry_for_name(root, name)
    return runtime:entry_for_name(root, name)
  end

  function api.names_for_project(root)
    return runtime:names_for_project(root)
  end

  function api.mission_names_for_project(root)
    return runtime:mission_names_for_project(root)
  end

  function api.reconcile_project(root)
    return runtime:reconcile_project(root)
  end

  return api
end

function M.install_workspace_manager(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local controller = deps.controller
  local runtime = deps.runtime

  function api.fuzzy_workspace_score(value, query)
    return workspace_manager_mod.fuzzy_workspace_score(value, query)
  end

  function api.fuzzy_workspace_filter(entries, query)
    return workspace_manager_mod.fuzzy_workspace_filter(entries, query)
  end

  function api.render_workspace_manager_search()
    return controller:render_search()
  end

  function api.update_workspace_manager_query(query)
    return controller:update_query(query)
  end

  function api.append_workspace_manager_query(input)
    return controller:append_query(input)
  end

  function api.delete_workspace_manager_query_char()
    return controller:delete_query_char()
  end

  function api.clear_workspace_manager_query()
    return controller:clear_query()
  end

  function api.open_workspace_manager_search_input()
    return controller:open_search_input()
  end

  function api.close_saved_workspace_window(entry)
    return runtime:close_saved_workspace_window(entry)
  end

  function api.close_all_saved_workspace_windows(root)
    return runtime:close_all_saved_workspace_windows(root)
  end

  function api.saved_workspace_instruction_request(entry)
    return runtime:saved_workspace_instruction_request(entry)
  end

  function api.update_saved_workspace_instruction(entry, instruction)
    return runtime:update_saved_workspace_instruction(entry, instruction)
  end

  return api
end

function M.install_workspace_create(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local controller = deps.controller

  function api.parse_create_args(args)
    return workspace_runtime_mod.parse_create_args(args)
  end

  function api.workspace_create_preview_lines(request)
    return controller:preview_lines(request)
  end

  function api.workspace_create_preview_config(line_count)
    return controller:create_preview_config(line_count)
  end

  function api.workspace_create_footer_segments()
    return controller:create_footer_segments()
  end

  function api.workspace_create_footer_line()
    return controller:create_footer_line()
  end

  function api.render_workspace_create_footer(bufnr, width)
    return controller:render_create_footer(bufnr, width)
  end

  function api.open_workspace_create_footer(win)
    return controller:open_create_footer(win)
  end

  function api.workspace_instruction_editor_config(line_count)
    return controller:instruction_editor_config(line_count)
  end

  function api.workspace_instruction_mode_label(mode)
    return workspace_create_mod.instruction_mode_label(mode)
  end

  function api.update_workspace_instruction_mode_footer(win)
    return controller:update_instruction_mode_footer(win)
  end

  function api.disable_workspace_instruction_completion(bufnr)
    return controller:disable_instruction_completion(bufnr)
  end

  function api.open_workspace_instruction_editor(request, opts)
    return controller:open_instruction_editor(request, opts)
  end

  function api.open_workspace_create_preview(request)
    return controller:open_create_preview(request)
  end

  function api.open_custom_workspace_instruction_prompt(name)
    return controller:open_custom_instruction_prompt(name)
  end

  return api
end

return M
