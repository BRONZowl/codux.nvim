local workspace_create_mod = require("codux.workspace_create")
local workspace_manager_mod = require("codux.workspace_manager")
local workspace_runtime_mod = require("codux.workspace_runtime")

local M = {}

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
