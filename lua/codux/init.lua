local M = {}
local command_util = require("codux.command")
local context_mod = require("codux.context")
local health_mod = require("codux.health")
local mission_control_mod = require("codux.mission_control")
local mission_mod = require("codux.mission")
local prompt_actions_mod = require("codux.prompt_actions")
local terminal_mod = require("codux.terminal")
local token_monitor_mod = require("codux.token_monitor")
local ui = require("codux.ui")
local which_key_mod = require("codux.which_key")
local workspace_create_mod = require("codux.workspace_create")
local workspace_manager_mod = require("codux.workspace_manager")
local workspace_runtime_mod = require("codux.workspace_runtime")
local workspace_store_mod = require("codux.workspace_store")
local workspace_ui = require("codux.workspace_ui")

local defaults = {
  codex_cmd = vim.env.CODEX_CMD or 'codex -s workspace-write -a on-request -c approvals_reviewer="user"',
  workspace_auto_cmd = vim.env.CODEX_WORKSPACE_AUTO_CMD
    or 'codex -s workspace-write -a on-request -c approvals_reviewer="auto_review"',
  danger_full_access_cmd = vim.env.CODEX_DANGER_FULL_ACCESS_CMD or "codex -s danger-full-access -a never",
  auto_open = true,
  auto_focus = true,
  popup = {
    width = 0.85,
    height = 0.85,
    border = "rounded",
    lock_focus = true,
  },
  working_idle_ms = 3000,
  health_timeout_ms = 10000,
  token_monitor = {
    enabled = true,
    refresh_ms = 60000,
    timeout_ms = 5000,
  },
  workspaces = {
    enabled = true,
    tmux_cmd = vim.env.TMUX_CMD or "tmux",
    state_file = nil,
    worktree = {
      directory = "../codux-worktrees",
      branch_prefix = "dev/",
    },
    instruction_files = {
      enabled = true,
      directory = ".agents/codux",
    },
  },
  mappings = {
    open = "<leader>zc",
    open_auto = "<leader>za",
    open_danger = "<leader>zA",
    review_file = "<leader>zf",
    review_selection = "<leader>zs",
    diagnostics = "<leader>zd",
    diff = "<leader>zg",
    workspace = "<leader>zw",
    workspaces = "<leader>zW",
    mission = "<leader>zm",
    missions = "<leader>zM",
    mode = "<leader>zp",
  },
  prompts = {
    file = "Review this %{target_type}, identify issues, and suggest or make fixes where appropriate: %{path}",
    review_selection = "Review this selected code from %{relative_path}%{line_range} (%{filetype}):\n\n%{selection}",
    diagnostics = "Explain these %{diagnostics_source} issues for %{relative_path}, identify the likely causes, and suggest fixes:\n\n%{diagnostics}",
    git_diff = "Review these Git changes on branch %{git_branch} in %{relative_path}. Identify issues, risks, and concrete improvements:\n\n%{git_diff}",
  },
  explorers = {
    neo_tree = true,
    oil = true,
    nvim_tree = true,
    mini_files = true,
  },
  target_providers = {},
}

local config = vim.deepcopy(defaults)
local state = {
  buf = nil,
  win = nil,
  job_id = nil,
  mode = "not running",
  working_buf = nil,
  working_win = nil,
  working_timer = nil,
  working_idle_timer = nil,
  working_frame = 1,
  codex_working = false,
  last_working_activity = 0,
  last_prompt_line = nil,
  token_usage = {
    five_hour_percent = nil,
    weekly_percent = nil,
    last_error = nil,
    in_flight = false,
    job_id = nil,
    stdout = "",
    initialized = false,
    timeout_timer = nil,
  },
  terminal_attached_buf = nil,
  terminal_prompt_input = "",
  terminal_prompt_tracking_valid = true,
  terminal_mode_sync_pending = false,
  permission_profile = "default",
  last_permission_profile = "default",
  workspace = nil,
  workspace_manager_buf = nil,
  workspace_manager_win = nil,
  workspace_manager_footer_buf = nil,
  workspace_manager_footer_win = nil,
  workspace_manager_search_buf = nil,
  workspace_manager_search_win = nil,
  workspace_manager_command_buf = nil,
  workspace_manager_command_win = nil,
  workspace_manager_action_buf = nil,
  workspace_manager_action_win = nil,
  workspace_manager_action_items = {},
  workspace_manager_action_workspace = nil,
  workspace_manager_items = {},
  workspace_manager_query = "",
  workspace_manager_best_match_index = nil,
  workspace_manager_selected_index = nil,
  workspace_manager_focus_match = false,
  workspace_manager_search_confirmed = false,
  workspace_manager_project_root = nil,
  workspace_manager_refresh_timer = nil,
  workspace_manager_ns = vim.api.nvim_create_namespace("codux.workspace_manager"),
  mission_dashboard_buf = nil,
  mission_dashboard_win = nil,
  mission_dashboard_items = {},
  workspace_instruction_ignore_warnings = {},
  workspace_target_signature = nil,
  workspace_target_update_pending = false,
  closing_popup = false,
  focus_lock_pending = false,
  focus_lock_autocmd = nil,
  exiting_jobs = {},
  pending_delete_buffers = {},
  installed_mappings = {},
}

local augroup = vim.api.nvim_create_augroup("codux.nvim", { clear = true })
local refresh_which_key
local update_terminal_mode_mapping
local refresh_which_key_header
local refresh_token_usage
local start_token_monitor_timer
local stop_token_monitor_timer
local token_monitor
local terminal
local context_util
local which_key_controller
local workspace_create_controller
local workspace_manager_controller
local mission_controller
local workspace_runtime
local prompt_actions
local current_target
local git_branch_for
local git_root_for
local render_workspace_manager
local close_workspace_manager

M._v5 = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "codux.nvim" })
end

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M._v5.mode_display_label(mode)
  return terminal_mod.mode_display_label(mode)
end

function M._v5.strip_terminal_control_sequences(value)
  return terminal_mod.strip_terminal_control_sequences(value)
end

function M._v5.detect_terminal_mode_from_lines(lines, first_index)
  return terminal_mod.detect_terminal_mode_from_lines(lines, first_index)
end

function M._v5.output_looks_like_question(lines, first_index)
  return terminal_mod.output_looks_like_question(lines, first_index)
end

local function system(args, input)
  local output = vim.fn.system(args, input)
  return output, vim.v.shell_error
end

local function system_with_timeout(args, timeout_ms)
  if vim.system then
    local ok, result = pcall(function()
      return vim.system(args, { text = true, timeout = timeout_ms }):wait()
    end)
    if not ok then
      return tostring(result), 124
    end
    if type(result) ~= "table" then
      return "Command timed out or returned no result", 124
    end

    return (result.stdout or "") .. (result.stderr or ""), result.code or 0
  end

  return system(args)
end

local is_valid_buf = ui.is_valid_buf
local is_loaded_buf = ui.is_loaded_buf
local is_valid_win = ui.is_valid_win

local function valid_buf()
  return terminal:valid_buf()
end

local window_buffer = ui.window_buffer
local buffer_filetype = ui.buffer_filetype

local function current_filetype()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = buffer_filetype(bufnr)
  if filetype == nil or filetype == "" then
    return "unknown"
  end

  return filetype
end

local function current_buffer_name()
  local bufnr = vim.api.nvim_get_current_buf()
  if not is_valid_buf(bufnr) then
    return ""
  end

  local ok, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  if ok and type(name) == "string" then
    return name
  end

  return ""
end

local buffer_lines = ui.buffer_lines

context_util = context_mod.new({
  config = function()
    return config
  end,
  notify = notify,
  system = system,
  system_with_timeout = system_with_timeout,
  current_filetype = current_filetype,
  current_buffer_name = current_buffer_name,
})

current_target = function()
  return context_util.current_target()
end

git_branch_for = function(path)
  return context_util.git_branch_for(path)
end

git_root_for = function(path)
  return context_util.git_root_for(path)
end

local function is_explorer_filetype(filetype)
  return context_util.is_explorer_filetype(filetype)
end

terminal = terminal_mod.new({
  state = state,
  defaults = defaults,
  get_config = function()
    return config
  end,
  notify = notify,
  augroup = augroup,
  command_util = command_util,
  ui = ui,
  sync_workspace_activity = function(codex_status)
    if type(M._sync_workspace_activity) == "function" then
      return M._sync_workspace_activity(codex_status)
    end
    return false
  end,
  sync_workspace_mode = function(mode)
    if type(M._sync_workspace_mode) == "function" then
      return M._sync_workspace_mode(mode)
    end
    return false
  end,
  reset_workspace_runtime = function()
    state.workspace = nil
    state.workspace_target_signature = nil
    state.workspace_target_update_pending = false
  end,
  capture_workspace_session = function(workspace, min_mtime)
    if type(M._v5.schedule_workspace_session_capture) == "function" then
      return M._v5.schedule_workspace_session_capture(workspace, min_mtime)
    end
    return false
  end,
  refresh_which_key = function()
    if type(refresh_which_key) == "function" then
      return refresh_which_key()
    end
    return false
  end,
  refresh_which_key_header = function()
    if type(refresh_which_key_header) == "function" then
      return refresh_which_key_header()
    end
    return false
  end,
  update_terminal_mode_mapping = function()
    if type(update_terminal_mode_mapping) == "function" then
      return update_terminal_mode_mapping()
    end
    return false
  end,
  start_token_monitor_timer = function()
    if type(start_token_monitor_timer) == "function" then
      return start_token_monitor_timer()
    end
    return false
  end,
  stop_token_monitor_timer = function()
    if type(stop_token_monitor_timer) == "function" then
      return stop_token_monitor_timer()
    end
    return false
  end,
})

local function terminal_running()
  return terminal:terminal_running()
end

function M._v5.set_buffer_keymap(bufnr, modes, lhs, rhs, desc, opts)
  return ui.set_keymap(bufnr, modes, lhs, rhs, desc, opts)
end

function M._v5.bind_close_keys(bufnr, close_fn, desc, modes, opts)
  return ui.bind_close_keys(bufnr, close_fn, desc, modes, opts)
end

function M._v5.single_line_prompt(opts, callback)
  return ui.single_line_prompt(opts, callback, {
    notify = notify,
    set_buffer_keymap = M._v5.set_buffer_keymap,
    bind_close_keys = M._v5.bind_close_keys,
  })
end

function M._v5.mark_terminal_prompt_submission()
  return terminal:mark_terminal_prompt_submission()
end

function M._v5.plan_question_pending()
  return terminal:plan_question_pending()
end

function M._v5.sync_terminal_mode_from_buffer()
  return terminal:sync_terminal_mode_from_buffer()
end

function M._v5.schedule_terminal_buffer_observation()
  return terminal:schedule_terminal_buffer_observation()
end

function M._v5.command_with_args(command, args)
  return command_util.with_args(command, args)
end

function M._v5.toml_basic_string(value)
  return command_util.toml_basic_string(value)
end

function M._v5.command_with_developer_instructions(command, instructions)
  return command_util.with_developer_instructions(command, instructions)
end

local function json_encode(value)
  if vim.json and type(vim.json.encode) == "function" then
    return vim.json.encode(value)
  end

  return vim.fn.json_encode(value)
end

local function json_decode(value)
  local ok, decoded
  if vim.json and type(vim.json.decode) == "function" then
    ok, decoded = pcall(vim.json.decode, value)
  else
    ok, decoded = pcall(vim.fn.json_decode, value)
  end

  if ok then
    return decoded
  end

  return nil
end

token_monitor = token_monitor_mod.new({
  get_config = function()
    return config
  end,
  defaults = defaults.token_monitor,
  state = state.token_usage,
  is_running = function()
    return state.job_id ~= nil
  end,
  get_mode = function()
    return state.mode
  end,
  command_util = command_util,
  json_encode = json_encode,
  json_decode = json_decode,
  on_update = function()
    if type(refresh_which_key_header) == "function" then
      refresh_which_key_header()
    end
  end,
})

local function token_usage_label()
  return token_monitor:label({
    running = state.job_id ~= nil,
    mode = state.mode,
  })
end

refresh_token_usage = function(force)
  return token_monitor:refresh(force)
end

start_token_monitor_timer = function()
  return token_monitor:start()
end

stop_token_monitor_timer = function()
  return token_monitor:stop()
end

local function workspace_config()
  if config.workspaces == false then
    return { enabled = false }
  end

  if type(config.workspaces) ~= "table" then
    return defaults.workspaces
  end

  return config.workspaces
end

local function workspaces_enabled()
  return workspace_runtime:workspaces_enabled()
end

local function tmux_cmd()
  return workspace_runtime:tmux_cmd()
end

local function sanitize_workspace_name(name)
  return workspace_runtime_mod.sanitize_workspace_name(name)
end

function M._v5.workspace_window_name(safe_name)
  return workspace_runtime_mod.workspace_window_name(safe_name)
end

local workspace_store = workspace_store_mod.new({
  get_workspace_config = workspace_config,
  default_instruction_files = defaults.workspaces.instruction_files,
  json_encode = json_encode,
  json_decode = json_decode,
  sanitize_workspace_name = sanitize_workspace_name,
  workspace_window_name = M._v5.workspace_window_name,
})

workspace_runtime = workspace_runtime_mod.new({
  state = state,
  defaults = defaults,
  get_config = function()
    return config
  end,
  notify = notify,
  system = system,
  command_util = command_util,
  store = workspace_store,
  current_target = function()
    return current_target()
  end,
  current_buffer_name = current_buffer_name,
  current_buffer = function()
    return vim.api.nvim_get_current_buf()
  end,
  alternate_buffer = function()
    return vim.fn.bufnr("#")
  end,
  list_buffers = function()
    return vim.api.nvim_list_bufs()
  end,
  is_loaded_buf = is_loaded_buf,
  git_root_for = function(path)
    return git_root_for(path)
  end,
  git_branch_for = function(path)
    return git_branch_for(path)
  end,
  is_explorer_filetype = is_explorer_filetype,
  terminal_running = terminal_running,
  render_workspace_manager = function()
    if type(render_workspace_manager) == "function" then
      return render_workspace_manager()
    end
    return false
  end,
  close_workspace_manager = function()
    if type(close_workspace_manager) == "function" then
      return close_workspace_manager()
    end
    return false
  end,
})

local function current_tmux_session()
  return workspace_runtime:current_tmux_session()
end

function M._v5.tmux_window_command(window_id)
  return workspace_runtime:tmux_window_command(window_id)
end

function M._v5.status_for_window(window_id)
  return workspace_runtime:status_for_window(window_id)
end

function M._v5.dashboard_workspace_status(record, window_id)
  return workspace_runtime:dashboard_workspace_status(record, window_id)
end

function M._v5.tmux_target(session, window_name)
  return workspace_runtime_mod.tmux_target(session, window_name)
end

function M._v5.normalize_codex_session_id(value)
  return workspace_store.normalize_session_id(value)
end

function M._v5.codex_home()
  return workspace_runtime:codex_home()
end

function M._v5.codex_session_files()
  return workspace_runtime:codex_session_files()
end

function M._v5.read_codex_session_meta(path)
  return workspace_runtime:read_codex_session_meta(path)
end

function M._v5.codex_session_for_id(session_id)
  return workspace_runtime:codex_session_for_id(session_id)
end

function M._v5.latest_codex_session_for_cwd(cwd, min_mtime)
  return workspace_runtime:latest_codex_session_for_cwd(cwd, min_mtime)
end

local function workspace_state_file()
  return workspace_runtime:state_file()
end

function M._v5.workspace_instruction_files_config()
  return workspace_runtime:instruction_files_config()
end

function M._v5.workspace_instruction_directory(root)
  return workspace_runtime:instruction_directory(root)
end

function M._v5.workspace_instruction_file_path(root, safe_name)
  return workspace_runtime:instruction_file_path(root, safe_name)
end

function M._v5.read_workspace_instruction_file(root, safe_name)
  return workspace_runtime:read_instruction_file(root, safe_name)
end

function M._v5.write_workspace_instruction_file(root, safe_name, instruction)
  return workspace_runtime:write_instruction_file(root, safe_name, instruction)
end

function M._v5.delete_workspace_instruction_file(root, safe_name)
  return workspace_runtime:delete_instruction_file(root, safe_name)
end

function M._v5.workspace_instruction_file_records(root)
  return workspace_runtime:instruction_file_records(root)
end

function M._v5.workspace_instruction_ignore_status(root)
  return workspace_runtime:workspace_instruction_ignore_status(root)
end

function M._v5.normalize_record(record, safe_name, root)
  return workspace_runtime:normalize_record(record, safe_name, root)
end

local function read_workspace_state()
  return workspace_runtime:read_state()
end

function M._v5.apply_codex_session_meta(workspace, meta)
  return workspace_runtime:apply_codex_session_meta(workspace, meta)
end

function M._v5.resolve_workspace_resume_session(workspace)
  return workspace_runtime:resolve_workspace_resume_session(workspace)
end

function M._v5.persist_workspace_session_meta(workspace, meta)
  return workspace_runtime:persist_workspace_session_meta(workspace, meta)
end

function M._v5.schedule_workspace_session_capture(workspace, min_mtime)
  return workspace_runtime:schedule_workspace_session_capture(workspace, min_mtime)
end

M._sync_workspace_activity = function(codex_status)
  return workspace_runtime:sync_activity(codex_status)
end

M._sync_workspace_mode = function(mode)
  return workspace_runtime:sync_mode(mode)
end

local function workspace_entries_for_project(root)
  return workspace_runtime:entries_for_project(root)
end

function M._v5.entry_for_name(root, name)
  return workspace_runtime:entry_for_name(root, name)
end

function M._v5.names_for_project(root)
  return workspace_runtime:names_for_project(root)
end

function M._v5.reconcile_project(root)
  return workspace_runtime:reconcile_project(root)
end

local function workspace_manager_project_root()
  return workspace_runtime:project_root()
end

M._stop_workspace_manager_refresh_timer = function()
  return workspace_manager_controller:stop_refresh_timer()
end

M._start_workspace_manager_refresh_timer = function()
  return workspace_manager_controller:start_refresh_timer()
end

close_workspace_manager = function()
  return workspace_manager_controller:close()
end

function M._v5.fuzzy_workspace_score(value, query)
  return workspace_manager_mod.fuzzy_workspace_score(value, query)
end

function M._v5.fuzzy_workspace_filter(entries, query)
  return workspace_manager_mod.fuzzy_workspace_filter(entries, query)
end

render_workspace_manager = function()
  return workspace_manager_controller:render()
end

local function workspace_manager_max_height()
  if terminal:valid_win() then
    local ok, height = pcall(vim.api.nvim_win_get_height, state.win)
    if ok and type(height) == "number" and height > 0 then
      return height
    end
  end

  local popup_config = terminal:popup_config()
  return type(popup_config) == "table" and popup_config.height or nil
end

function M._v5.render_workspace_manager_search()
  return workspace_manager_controller:render_search()
end

function M._v5.update_workspace_manager_query(query)
  return workspace_manager_controller:update_query(query)
end

function M._v5.append_workspace_manager_query(input)
  return workspace_manager_controller:append_query(input)
end

function M._v5.delete_workspace_manager_query_char()
  return workspace_manager_controller:delete_query_char()
end

function M._v5.clear_workspace_manager_query()
  return workspace_manager_controller:clear_query()
end

function M._v5.open_workspace_manager_search_input()
  return workspace_manager_controller:open_search_input()
end

local function rename_saved_workspace(entry, new_name)
  return workspace_runtime:rename_saved_workspace(entry, new_name)
end

local function delete_saved_workspace(entry)
  return workspace_runtime:delete_saved_workspace(entry)
end

function M._v5.close_saved_workspace_window(entry)
  return workspace_runtime:close_saved_workspace_window(entry)
end

function M._v5.close_all_saved_workspace_windows(root)
  return workspace_runtime:close_all_saved_workspace_windows(root)
end

function M._v5.saved_workspace_instruction_request(entry)
  return workspace_runtime:saved_workspace_instruction_request(entry)
end

function M._v5.update_saved_workspace_instruction(entry, instruction)
  return workspace_runtime:update_saved_workspace_instruction(entry, instruction)
end

local function edit_saved_workspace_instruction(entry)
  if type(workspace_create_controller) ~= "table" then
    notify("Codux workspace instruction editor is not available", vim.log.levels.ERROR)
    return false
  end

  local request, request_error = M._v5.saved_workspace_instruction_request(entry)
  if not request then
    notify(request_error or "workspace not found", vim.log.levels.ERROR)
    return false
  end

  return workspace_create_controller:open_instruction_editor(request, {
    on_save = function(saved_request)
      local ok, write_error = M._v5.update_saved_workspace_instruction(entry, saved_request.resolved_instruction)
      if not ok then
        notify(write_error or "Failed to save Codux workspace instruction", vim.log.levels.ERROR)
        return
      end
      notify("Saved Codux workspace instruction for " .. tostring(entry.name or entry.safe_name))
    end,
    on_cancel = function()
      render_workspace_manager()
    end,
  })
end

workspace_manager_controller = workspace_manager_mod.new({
  state = state,
  notify = notify,
  trim = trim,
  ui = ui,
  workspace_ui = workspace_ui,
  is_valid_win = is_valid_win,
  is_loaded_buf = is_loaded_buf,
  window_buffer = window_buffer,
  buffer_filetype = buffer_filetype,
  workspace_manager_max_height = workspace_manager_max_height,
  workspace_entries_for_project = workspace_entries_for_project,
  project_root = workspace_manager_project_root,
  workspaces_enabled = workspaces_enabled,
  restore_workspaces = function(opts)
    return M.restore_workspaces(opts)
  end,
  prompt_merged_workspaces = function(root)
    return workspace_runtime:prompt_merged_workspaces(root)
  end,
  open_saved_workspace = function(name, project_root)
    return M.open_saved_workspace(name, project_root)
  end,
  rename_saved_workspace = rename_saved_workspace,
  edit_saved_workspace_instruction = edit_saved_workspace_instruction,
  delete_saved_workspace = delete_saved_workspace,
  close_saved_workspace_window = function(entry)
    return M._v5.close_saved_workspace_window(entry)
  end,
  close_all_saved_workspace_windows = function(root)
    return M._v5.close_all_saved_workspace_windows(root)
  end,
  doctor = function()
    return M.doctor()
  end,
  single_line_prompt = M._v5.single_line_prompt,
  set_buffer_keymap = M._v5.set_buffer_keymap,
  bind_close_keys = M._v5.bind_close_keys,
  namespace = state.workspace_manager_ns,
})

function M._v5.parse_create_args(args)
  return workspace_runtime_mod.parse_create_args(args)
end

function M.open(opts)
  return terminal:open(opts)
end

local function restart_with_command(command, focus, permission_profile, initial_prompt)
  return terminal:restart_with_command(command, focus, permission_profile, initial_prompt)
end

local function start_hidden_with_command(command, permission_profile, initial_prompt)
  return terminal:start_hidden_with_command(command, permission_profile, initial_prompt)
end

local function restart_hidden_with_command(command, permission_profile, initial_prompt)
  return terminal:restart_hidden_with_command(command, permission_profile, initial_prompt)
end

function M.open_workspace_auto(initial_prompt)
  notify("Starting Codex autopilot with approve-for-me permissions")
  return restart_with_command(config.workspace_auto_cmd, true, "auto", initial_prompt)
end

function M.open_danger_full_access(initial_prompt)
  notify("Starting Codex with no approvals and no sandbox", vim.log.levels.WARN)
  return restart_with_command(config.danger_full_access_cmd, true, "danger", initial_prompt)
end

function M.open_workspace_session(workspace, initial_prompt, opts)
  opts = opts or {}
  workspace = type(workspace) == "table" and workspace or nil
  local profile = workspace and workspace.permission_profile or opts.permission_profile or "default"
  local command = config.codex_cmd
  if profile == "auto" then
    command = config.workspace_auto_cmd
  elseif profile == "danger" then
    command = config.danger_full_access_cmd
  else
    profile = "default"
  end

  local developer_instructions = workspace and workspace.resolved_instruction or nil
  command = M._v5.command_with_developer_instructions(command, developer_instructions)

  local resume_session_id = workspace and M._v5.normalize_codex_session_id(workspace.codex_session_id) or nil
  if resume_session_id and (type(initial_prompt) ~= "string" or initial_prompt == "") then
    command = M._v5.command_with_args(command, { "resume", resume_session_id })
  end

  local visible = opts.visible == true
  return terminal:start_terminal(visible, initial_prompt, command, workspace, profile, {
    hidden = not visible,
    capture_workspace_session = workspace ~= nil,
  })
end

function M.open_hidden(initial_prompt)
  return start_hidden_with_command(config.codex_cmd, "default", initial_prompt)
end

function M.open_workspace_auto_hidden(initial_prompt)
  return restart_hidden_with_command(config.workspace_auto_cmd, "auto", initial_prompt)
end

function M.open_danger_full_access_hidden(initial_prompt)
  return restart_hidden_with_command(config.danger_full_access_cmd, "danger", initial_prompt)
end

function M.open_workspace_auto_hidden_with_notice()
  notify("Starting Codex autopilot with approve-for-me permissions")
  return M.open_workspace_auto_hidden()
end

function M.open_danger_full_access_hidden_with_notice()
  notify("Starting Codex with no approvals and no sandbox", vim.log.levels.WARN)
  return M.open_danger_full_access_hidden()
end

function M.create_workspace(name, opts)
  return workspace_runtime:create_workspace(name, opts)
end

function M.create_mission(mission, objective, opts)
  return workspace_runtime:create_mission(mission, objective, opts)
end

function M.update_mission_objective(root, mission, objective)
  return workspace_runtime:update_mission_objective(root or workspace_manager_project_root(), mission, objective)
end

function M.delete_mission(root, mission)
  return workspace_runtime:delete_mission(root or workspace_manager_project_root(), mission)
end

function M.open_workspace(name)
  return M.create_workspace(name)
end

function M.open_saved_workspace(name, project_root)
  return workspace_runtime:open_saved_workspace(name, project_root)
end

function M.select_workspace(name)
  return workspace_runtime:select_workspace(name)
end

function M.rename_workspace(old_name, new_name)
  return workspace_runtime:rename_workspace(old_name, new_name)
end

function M.delete_workspace(name)
  return workspace_runtime:delete_workspace(name)
end

function M.close_all_workspace_windows(project_root)
  local root = project_root or workspace_manager_project_root()
  local choice = vim.fn.confirm("Close all Codux workspaces for this project?", "&Yes\n&No", 2)
  if choice ~= 1 then
    return false
  end
  return workspace_runtime:close_all_saved_workspace_windows(root)
end

function M.ignore_workspace_files(project_root)
  local ok, message = workspace_runtime:ensure_workspace_instruction_gitignore(project_root or workspace_manager_project_root())
  notify(message, ok and vim.log.levels.INFO or vim.log.levels.WARN)
  return ok
end

function M.restore_workspaces(opts)
  return workspace_runtime:restore_workspaces(opts)
end

workspace_create_controller = workspace_create_mod.new({
  notify = notify,
  trim = trim,
  ui = ui,
  workspace_ui = workspace_ui,
  is_loaded_buf = is_loaded_buf,
  is_valid_win = is_valid_win,
  set_buffer_keymap = M._v5.set_buffer_keymap,
  bind_close_keys = M._v5.bind_close_keys,
  single_line_prompt = M._v5.single_line_prompt,
  has_tmux_session = function()
    return current_tmux_session() ~= nil
  end,
  create_workspace = function(name, opts)
    return M.create_workspace(name, opts)
  end,
  namespace = state.workspace_manager_ns,
})

function M._v5.workspace_create_preview_lines(request)
  return workspace_create_controller:preview_lines(request)
end

function M._v5.workspace_create_preview_config(line_count)
  return workspace_create_controller:create_preview_config(line_count)
end

function M._v5.workspace_create_footer_segments()
  return workspace_create_controller:create_footer_segments()
end

function M._v5.workspace_create_footer_line()
  return workspace_create_controller:create_footer_line()
end

function M._v5.render_workspace_create_footer(bufnr, width)
  return workspace_create_controller:render_create_footer(bufnr, width)
end

function M._v5.open_workspace_create_footer(win)
  return workspace_create_controller:open_create_footer(win)
end

function M._v5.workspace_instruction_editor_config(line_count)
  return workspace_create_controller:instruction_editor_config(line_count)
end

function M._v5.workspace_instruction_mode_label(mode)
  return workspace_create_mod.instruction_mode_label(mode)
end

function M._v5.update_workspace_instruction_mode_footer(win)
  return workspace_create_controller:update_instruction_mode_footer(win)
end

function M._v5.disable_workspace_instruction_completion(bufnr)
  return workspace_create_controller:disable_instruction_completion(bufnr)
end

function M._v5.open_workspace_instruction_editor(request, opts)
  return workspace_create_controller:open_instruction_editor(request, opts)
end

function M._v5.open_workspace_create_preview(request)
  return workspace_create_controller:open_create_preview(request)
end

function M._v5.open_custom_workspace_instruction_prompt(name)
  return workspace_create_controller:open_custom_instruction_prompt(name)
end

function M.open_workspace_prompt()
  return workspace_create_controller:open_prompt()
end

function M.open_workspaces()
  return workspace_manager_controller:open()
end

mission_controller = mission_control_mod.new({
  state = state,
  mission = mission_mod,
  ui = ui,
  workspace_ui = workspace_ui,
  notify = notify,
  create_mission = function(mission)
    return M.create_mission(mission)
  end,
  workspace_entries_for_project = workspace_entries_for_project,
  open_saved_workspace = function(name, project_root)
    return M.open_saved_workspace(name, project_root)
  end,
  update_mission_objective = function(root, mission, objective)
    return M.update_mission_objective(root, mission, objective)
  end,
  delete_mission = function(root, mission)
    return M.delete_mission(root, mission)
  end,
  project_root = workspace_manager_project_root,
  set_buffer_keymap = M._v5.set_buffer_keymap,
  bind_close_keys = M._v5.bind_close_keys,
  namespace = state.workspace_manager_ns,
})

function M.open_mission_prompt()
  return mission_controller:open_prompt()
end

function M.open_missions()
  return mission_controller:open_dashboard()
end

function M.open_mission_dashboard()
  return M.open_missions()
end

function M.edit_mission(name)
  name = trim(name)
  if name == "" then
    return M.open_missions()
  end

  local root = workspace_manager_project_root()
  local mission, error_message = workspace_runtime:mission_for_project(root, name)
  if not mission then
    notify(error_message or "mission not found", vim.log.levels.ERROR)
    return false
  end

  return mission_controller:open_objective_editor(mission.name, mission.objective, {
    on_save = function(_, objective)
      local ok, update_error = M.update_mission_objective(root, mission.mission_id, objective)
      if not ok then
        notify(update_error or "Failed to update Codux mission", vim.log.levels.ERROR)
        return false
      end
      notify("Updated Codux mission objective for " .. tostring(mission.name))
      return true
    end,
  })
end

function M.delete_mission_by_name(name)
  name = trim(name)
  if name == "" then
    return M.open_missions()
  end

  local root = workspace_manager_project_root()
  local mission, error_message = workspace_runtime:mission_for_project(root, name)
  if not mission then
    notify(error_message or "mission not found", vim.log.levels.ERROR)
    return false
  end

  local choice = vim.fn.confirm(
    "Delete Codux mission " .. tostring(mission.name) .. " and all role workspaces?",
    "&Yes\n&No",
    2
  )
  if choice ~= 1 then
    return false
  end

  local ok, delete_error = M.delete_mission(root, mission.mission_id)
  if not ok then
    notify(delete_error or "Failed to delete Codux mission", vim.log.levels.ERROR)
    return false
  end
  notify("Deleted Codux mission " .. tostring(mission.name))
  return true
end

function M.close()
  return terminal:close()
end

function M.toggle()
  return terminal:toggle()
end

function M.exit()
  return terminal:exit()
end

function M.toggle_plan_mode()
  return terminal:toggle_plan_mode()
end

local function send_to_codex(message)
  return terminal:send_to_codex(message)
end

prompt_actions = prompt_actions_mod.new({
  get_config = function()
    return config
  end,
  notify = notify,
  send_to_codex = send_to_codex,
  exit = function()
    return M.exit()
  end,
  context = context_util,
  current_filetype = current_filetype,
  current_buffer = function()
    return vim.api.nvim_get_current_buf()
  end,
  buffer_lines = buffer_lines,
  mode = function()
    return vim.fn.mode()
  end,
  getpos = function(mark)
    return vim.fn.getpos(mark)
  end,
  visualmode = function()
    return vim.fn.visualmode()
  end,
})

M._workspace_target_signature = function(path, target_type, branch)
  return workspace_runtime_mod.workspace_target_signature(path, target_type, branch)
end

M._workspace_target_sync_allowed = function(event)
  return workspace_runtime:target_sync_allowed(event, current_filetype)
end

M._sync_workspace_target = function(event)
  return workspace_runtime:sync_target(event, current_filetype)
end

M._schedule_workspace_target_sync = function(event)
  return workspace_runtime:schedule_target_sync(event, M._sync_workspace_target)
end

function M.attach_workspace(workspace)
  return workspace_runtime:attach_workspace(workspace, M._schedule_workspace_target_sync)
end

function M.send_file_review()
  return prompt_actions:send_file_review()
end

function M.send_file_fix()
  return prompt_actions:send_file_fix()
end

function M.send_selection(opts)
  return prompt_actions:send_selection(opts)
end

function M.send_diagnostics()
  return prompt_actions:send_diagnostics()
end

function M.send_git_diff()
  return prompt_actions:send_git_diff()
end

function M.doctor()
  local lines = health_mod.doctor_lines({
    config = config,
    tmux_cmd = tmux_cmd,
    current_tmux_session = current_tmux_session,
    workspace_state_file = workspace_state_file,
    workspace_instruction_directory = M._v5.workspace_instruction_directory,
    workspace_instruction_ignore_status = M._v5.workspace_instruction_ignore_status,
    project_root = workspace_manager_project_root,
    read_workspace_state = read_workspace_state,
    workspace_entries_for_project = workspace_entries_for_project,
  })
  notify(table.concat(lines, "\n"))
  return lines
end

function M.health()
  vim.cmd("checkhealth codux")
end

function M.health_info()
  local terminal_info = terminal:health_info()
  return {
    config = config,
    popup_visible = terminal_info.popup_visible,
    terminal_running = terminal_info.terminal_running,
    terminal_buffer = terminal_info.terminal_buffer,
    terminal_job_id = terminal_info.terminal_job_id,
    mode = terminal_info.mode,
    permission_profile = terminal_info.permission_profile,
    last_permission_profile = terminal_info.last_permission_profile,
    codex_working = terminal_info.codex_working,
    working_indicator_visible = terminal_info.working_indicator_visible,
    token_usage = {
      five_hour_percent = state.token_usage.five_hour_percent,
      weekly_percent = state.token_usage.weekly_percent,
      in_flight = state.token_usage.in_flight,
      last_error = state.token_usage.last_error,
    },
    workspace = state.workspace,
    workspace_state_file = workspace_state_file(),
    workspace_instruction_directory = M._v5.workspace_instruction_directory(workspace_manager_project_root()),
    workspace_instruction_ignore_status = M._v5.workspace_instruction_ignore_status(workspace_manager_project_root()),
  }
end

function M._v5.filter_completion(values, arglead)
  local matches = {}
  arglead = arglead or ""
  for _, value in ipairs(values) do
    if arglead == "" or tostring(value):find(arglead, 1, true) == 1 then
      table.insert(matches, value)
    end
  end
  return matches
end

function M._v5.complete_workspace_names(arglead)
  return M._v5.filter_completion(M._v5.names_for_project(workspace_manager_project_root()), arglead)
end

function M._v5.complete_mission_names(arglead)
  return M._v5.filter_completion(workspace_runtime:mission_names_for_project(workspace_manager_project_root()), arglead)
end

function M._v5.complete_create(arglead, _cmdline, _cursorpos)
  return M._v5.filter_completion({ "--custom" }, arglead)
end

local function create_commands()
  local function open_workspace_instruction_from_args(opts)
    if #opts.fargs == 0 then
      M.open_workspace_prompt()
      return
    end

    local name, _custom_requested, error_message = M._v5.parse_create_args(opts.fargs)
    if error_message then
      notify(error_message, vim.log.levels.ERROR)
      return
    end
    M._v5.open_custom_workspace_instruction_prompt(name)
  end

  vim.api.nvim_create_user_command("Codux", function()
    M.open()
  end, { force = true, desc = "Open or focus the Codex popup" })

  vim.api.nvim_create_user_command("CoduxOpen", function()
    M.open()
  end, { force = true, desc = "Open or focus the Codex popup" })

  vim.api.nvim_create_user_command("CoduxOpenAuto", function()
    M.open_workspace_auto()
  end, { force = true, desc = "Open Codex autopilot with approve-for-me permissions" })

  vim.api.nvim_create_user_command("CoduxOpenDanger", function()
    M.open_danger_full_access()
  end, { force = true, desc = "Open Codex danger zone with no sandbox" })

  vim.api.nvim_create_user_command(
    "CoduxWorkspace",
    open_workspace_instruction_from_args,
    { force = true, nargs = "*", complete = M._v5.complete_create, desc = "Create a named Codux tmux workspace" }
  )

  vim.api.nvim_create_user_command(
    "CoduxWorkspaceCreate",
    open_workspace_instruction_from_args,
    { force = true, nargs = "*", complete = M._v5.complete_create, desc = "Create a named Codux tmux workspace" }
  )

  vim.api.nvim_create_user_command("CoduxWorkspaceOpen", function(opts)
    M.open_saved_workspace(opts.args, workspace_manager_project_root())
  end, { force = true, nargs = 1, complete = M._v5.complete_workspace_names, desc = "Open a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceSelect", function(opts)
    M.select_workspace(opts.args)
  end, { force = true, nargs = 1, complete = M._v5.complete_workspace_names, desc = "Select a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceDelete", function(opts)
    M.delete_workspace(opts.args)
  end, { force = true, nargs = 1, complete = M._v5.complete_workspace_names, desc = "Delete a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceRename", function(opts)
    local old_name = opts.fargs[1]
    local new_name = opts.fargs[2]
    if type(old_name) ~= "string" or old_name == "" or type(new_name) ~= "string" or new_name == "" then
      notify("Usage: CoduxWorkspaceRename <old> <new>", vim.log.levels.ERROR)
      return
    end
    M.rename_workspace(old_name, new_name)
  end, { force = true, nargs = "+", complete = M._v5.complete_workspace_names, desc = "Rename a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceRestore", function()
    M.restore_workspaces()
  end, { force = true, desc = "Restore Codux workspace status from tmux" })

  vim.api.nvim_create_user_command("CoduxWorkspaceCloseAll", function()
    M.close_all_workspace_windows()
  end, { force = true, desc = "Close all current-project Codux workspaces" })

  vim.api.nvim_create_user_command("CoduxWorkspaceIgnore", function()
    M.ignore_workspace_files()
  end, { force = true, desc = "Add Codux workspace files to the current project's .gitignore" })

  vim.api.nvim_create_user_command("CoduxWorkspaces", function()
    M.open_workspaces()
  end, { force = true, desc = "Show current Codux workspaces" })

  vim.api.nvim_create_user_command("CoduxMissionCreate", function(opts)
    if type(opts.args) == "string" and opts.args ~= "" then
      mission_controller:open_objective_editor(opts.args)
      return
    end
    M.open_mission_prompt()
  end, { force = true, nargs = "?", desc = "Create a Codux Mission Control crew" })

  vim.api.nvim_create_user_command("CoduxMissions", function()
    M.open_missions()
  end, { force = true, desc = "Show Codux missions" })

  vim.api.nvim_create_user_command("CoduxMissionDashboard", function()
    M.open_mission_dashboard()
  end, { force = true, desc = "Show the Codux mission dashboard" })

  vim.api.nvim_create_user_command("CoduxMissionEdit", function(opts)
    M.edit_mission(opts.args)
  end, {
    force = true,
    nargs = "?",
    complete = M._v5.complete_mission_names,
    desc = "Edit a Codux mission objective",
  })

  vim.api.nvim_create_user_command("CoduxMissionDelete", function(opts)
    M.delete_mission_by_name(opts.args)
  end, {
    force = true,
    nargs = "?",
    complete = M._v5.complete_mission_names,
    desc = "Delete a Codux mission and its role workspaces",
  })

  vim.api.nvim_create_user_command("CoduxToggle", function()
    M.toggle()
  end, { force = true, desc = "Toggle the Codex popup" })

  vim.api.nvim_create_user_command("CoduxClose", function()
    M.close()
  end, { force = true, desc = "Hide the Codex popup without stopping Codex" })

  vim.api.nvim_create_user_command("CoduxExit", function()
    M.exit()
  end, { force = true, desc = "Stop Codex and close the popup" })

  vim.api.nvim_create_user_command("CoduxReview", function()
    M.send_file_review()
  end, { force = true, desc = "Send current file or explorer node to Codex for review" })

  vim.api.nvim_create_user_command("CoduxReviewSelection", function(opts)
    M.send_selection(opts)
  end, { force = true, range = true, desc = "Send selected code to Codex for review" })

  vim.api.nvim_create_user_command("CoduxDiagnostics", function()
    M.send_diagnostics()
  end, { force = true, desc = "Send diagnostics, lists, and headless health output to Codex" })

  vim.api.nvim_create_user_command("CoduxDiff", function()
    M.send_git_diff()
  end, { force = true, desc = "Send Git changes to Codex for review" })

  vim.api.nvim_create_user_command("CoduxTogglePlan", function()
    M.toggle_plan_mode()
  end, { force = true, desc = "Toggle Codex plan mode" })

  vim.api.nvim_create_user_command("CoduxHealth", function()
    M.health()
  end, { force = true, desc = "Run codux.nvim health checks" })

  vim.api.nvim_create_user_command("CoduxDoctor", function()
    M.doctor()
  end, { force = true, desc = "Run codux.nvim troubleshooting checks" })
end

local function mapping_id(mode, lhs)
  return tostring(mode) .. "\0" .. tostring(lhs)
end

local function remove_installed_mappings()
  for id, mapping in pairs(state.installed_mappings or {}) do
    local mode = mapping.mode
    local lhs = mapping.lhs
    if type(mode) == "string" and type(lhs) == "string" and lhs ~= "" then
      local current = vim.fn.maparg(lhs, mode, false, true)
      if type(current) == "table" and current.desc == mapping.desc then
        pcall(vim.keymap.del, mode, lhs)
      end
    end
    state.installed_mappings[id] = nil
  end
end

local function set_mapping(mode, lhs, rhs, desc)
  if type(lhs) == "string" and lhs ~= "" then
    vim.keymap.set(mode, lhs, rhs, { desc = desc })
    if type(mode) == "string" then
      state.installed_mappings[mapping_id(mode, lhs)] = {
        mode = mode,
        lhs = lhs,
        desc = desc,
      }
    end
  end
end

which_key_controller = which_key_mod.new({
  get_mode = function()
    return state.mode
  end,
  get_mappings = function()
    return type(config.mappings) == "table" and config.mappings or {}
  end,
  token_usage_label = token_usage_label,
  mode_display_label = M._v5.mode_display_label,
  valid_terminal_buffer = valid_buf,
  terminal_buffer = function()
    return state.buf
  end,
  is_valid_win = is_valid_win,
  is_loaded_buf = is_loaded_buf,
  set_mapping = set_mapping,
  set_buffer_keymap = M._v5.set_buffer_keymap,
  toggle_plan_mode = M.toggle_plan_mode,
})

refresh_which_key_header = function()
  return which_key_controller:refresh_header()
end

update_terminal_mode_mapping = function()
  return which_key_controller:update_terminal_mode_mapping()
end

refresh_which_key = function()
  return which_key_controller:refresh()
end

M._install_workspace_target_autocmds = function()
  pcall(vim.api.nvim_clear_autocmds, {
    group = augroup,
    event = { "BufEnter", "BufWinEnter", "WinEnter", "DirChanged", "CursorMoved" },
  })
  pcall(vim.api.nvim_create_autocmd, { "BufEnter", "BufWinEnter", "WinEnter", "DirChanged" }, {
    group = augroup,
    callback = function(args)
      M._schedule_workspace_target_sync(args.event)
    end,
  })
  pcall(vim.api.nvim_create_autocmd, "CursorMoved", {
    group = augroup,
    callback = function(args)
      if is_explorer_filetype(current_filetype()) then
        M._schedule_workspace_target_sync(args.event)
      end
    end,
  })
end

function M.setup(opts)
  stop_token_monitor_timer()
  remove_installed_mappings()
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  create_commands()

  local mappings = type(config.mappings) == "table" and config.mappings or {}
  refresh_which_key()
  set_mapping("n", mappings.open, M.open, "open codex")
  set_mapping("n", mappings.open_auto, M.open_workspace_auto_hidden_with_notice, "codex autopilot")
  set_mapping("n", mappings.open_danger, M.open_danger_full_access_hidden_with_notice, "codex danger zone")
  set_mapping("n", mappings.review_file, M.send_file_review, "send file/folder to codex")
  set_mapping("n", mappings.review_selection, M.send_selection, "send selection to codex")
  set_mapping("v", mappings.review_selection, M.send_selection, "send selection to codex")
  set_mapping("n", mappings.diagnostics, M.send_diagnostics, "send diagnostics to codex")
  set_mapping("n", mappings.diff, M.send_git_diff, "send git diff to codex")
  set_mapping("n", mappings.workspace, M.open_workspace_prompt, "create codux workspace")
  set_mapping("n", mappings.workspaces, M.open_workspaces, "current codux workspaces")
  set_mapping("n", mappings.mission, M.open_mission_prompt, "create codux mission")
  set_mapping("n", mappings.missions, M.open_missions, "current codux missions")
  local action_desc = which_key_controller:mode_action_desc()
  if action_desc then
    set_mapping("n", mappings.mode, M.toggle_plan_mode, action_desc)
  end
  M._install_workspace_target_autocmds()

  pcall(vim.api.nvim_clear_autocmds, { group = augroup, event = "VimLeavePre" })
  pcall(vim.api.nvim_create_autocmd, "VimLeavePre", {
    group = augroup,
    callback = function()
      stop_token_monitor_timer()
    end,
  })

  which_key_controller:install_header_hook()
end

return M
