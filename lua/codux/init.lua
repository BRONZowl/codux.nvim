local M = {}
local autocmds_mod = require("codux.autocmds")
local command_util = require("codux.command")
local commands_mod = require("codux.commands")
local compat_mod = require("codux.compat")
local config_defaults = require("codux.config_defaults")
local context_mod = require("codux.context")
local health_mod = require("codux.health")
local json = require("codux.json")
local keymaps_mod = require("codux.keymaps")
local mission_mod = require("codux.mission")
local mission_setup_mod = require("codux.mission_setup")
local prompt_actions_setup_mod = require("codux.prompt_actions_setup")
local providers = require("codux.providers")
local state_mod = require("codux.state")
local text_util = require("codux.text")
local terminal_mod = require("codux.terminal")
local token_monitor_setup_mod = require("codux.token_monitor_setup")
local ui = require("codux.ui")
local which_key_setup_mod = require("codux.which_key_setup")
local workspace_create_mod = require("codux.workspace_create")
local workspace_manager_setup_mod = require("codux.workspace_manager_setup")
local workspace_runtime_mod = require("codux.workspace_runtime")
local workspace_store_mod = require("codux.workspace_store")
local workspace_ui = require("codux.workspace_ui")

local defaults = config_defaults.defaults()
local config = vim.deepcopy(defaults)
local state = state_mod.initial()

local augroup = vim.api.nvim_create_augroup("codux.nvim", { clear = true })
local refresh_which_key
local update_terminal_mode_mapping
local refresh_which_key_header
local refresh_token_usage
local start_token_monitor_timer
local stop_token_monitor_timer
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
  return text_util.trim(value)
end

compat_mod.install(M._v5, {
  project_root = function()
    return workspace_manager_project_root()
  end,
  names_for_project = function(root)
    return workspace_runtime:names_for_project(root)
  end,
  mission_names_for_project = function(root)
    return workspace_runtime:mission_names_for_project(root)
  end,
})

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

compat_mod.install_ui(M._v5, {
  ui = ui,
  notify = notify,
})

compat_mod.install_terminal(M._v5, {
  terminal = terminal,
  command_util = command_util,
})

local token_monitor_setup = token_monitor_setup_mod.new({
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
  get_agent_provider = function()
    return state.agent_provider
  end,
  command_util = command_util,
  on_update = function()
    if type(refresh_which_key_header) == "function" then
      refresh_which_key_header()
    end
  end,
})

local function token_usage_label()
  return token_monitor_setup.token_usage_label()
end

local function mission_token_usage_label()
  return token_monitor_setup.mission_token_usage_label()
end

refresh_token_usage = function(force)
  return token_monitor_setup.refresh_token_usage(force)
end

local function refresh_mission_token_usage(force)
  return token_monitor_setup.refresh_mission_token_usage(force)
end

local function token_usage_refresh_ms()
  return token_monitor_setup.token_usage_refresh_ms()
end

start_token_monitor_timer = function()
  return token_monitor_setup.start()
end

stop_token_monitor_timer = function()
  return token_monitor_setup.stop()
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

compat_mod.install_workspace_static(M._v5)

local workspace_store = workspace_store_mod.new({
  get_workspace_config = workspace_config,
  default_instruction_files = defaults.workspaces.instruction_files,
  json_encode = json.encode,
  json_decode = json.decode,
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

compat_mod.install_workspace_runtime(M._v5, {
  runtime = workspace_runtime,
  store = workspace_store,
})

local function workspace_state_file()
  return workspace_runtime:state_file()
end

local function read_workspace_state()
  return workspace_runtime:read_state()
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

local function rename_saved_workspace(entry, new_name)
  return workspace_runtime:rename_saved_workspace(entry, new_name)
end

local function delete_saved_workspace(entry)
  return workspace_runtime:delete_saved_workspace(entry)
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

workspace_manager_controller = workspace_manager_setup_mod.new({
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
  switch_workspace_profile = function(entry, agent_provider, permission_profile, opts)
    return workspace_runtime:update_workspace_profile(entry, agent_provider, permission_profile, opts)
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

compat_mod.install_workspace_manager(M._v5, {
  controller = workspace_manager_controller,
  runtime = workspace_runtime,
})

local function restart_with_command(command, focus, permission_profile, initial_prompt, opts)
  return terminal:restart_with_command(command, focus, permission_profile, initial_prompt, opts)
end

local function start_hidden_with_command(command, permission_profile, initial_prompt)
  return terminal:start_hidden_with_command(command, permission_profile, initial_prompt)
end

local function restart_hidden_with_command(command, permission_profile, initial_prompt)
  return terminal:restart_hidden_with_command(command, permission_profile, initial_prompt)
end

function M.open_workspace_auto(initial_prompt, opts)
  opts = type(opts) == "table" and opts or {}
  local agent_provider = providers.normalize_provider(opts.agent_provider) or providers.default_provider(config)
  notify("Starting " .. providers.provider_label(agent_provider) .. " autopilot with approve-for-me permissions")
  return restart_with_command(providers.command(config, agent_provider, "auto"), true, "auto", initial_prompt, {
    initial_mode = opts.initial_mode,
    agent_provider = agent_provider,
  })
end

function M.open_danger_full_access(initial_prompt, opts)
  opts = type(opts) == "table" and opts or {}
  local agent_provider = providers.normalize_provider(opts.agent_provider) or providers.default_provider(config)
  notify("Starting " .. providers.provider_label(agent_provider) .. " with no approvals and no sandbox", vim.log.levels.WARN)
  return restart_with_command(providers.command(config, agent_provider, "danger"), true, "danger", initial_prompt, {
    initial_mode = opts.initial_mode,
    agent_provider = agent_provider,
  })
end

function M.open_default(initial_prompt, opts)
  opts = type(opts) == "table" and opts or {}
  local agent_provider = providers.normalize_provider(opts.agent_provider) or providers.default_provider(config)
  return terminal:open({
    initial_prompt = initial_prompt,
    initial_mode = opts.initial_mode,
    agent_provider = agent_provider,
  })
end

function M.open_provider(agent_provider, profile, initial_prompt, opts)
  opts = type(opts) == "table" and opts or {}
  agent_provider = providers.normalize_provider(agent_provider) or providers.default_provider(config)
  profile = providers.normalize_profile(profile) or "default"
  opts.agent_provider = agent_provider
  if profile == "auto" then
    return M.open_workspace_auto(initial_prompt, opts)
  end
  if profile == "danger" then
    return M.open_danger_full_access(initial_prompt, opts)
  end
  return M.open_default(initial_prompt, opts)
end

function M.open_grok(initial_prompt, opts)
  return M.open_provider("grok", "default", initial_prompt, opts)
end

function M.open_grok_auto(initial_prompt, opts)
  return M.open_provider("grok", "auto", initial_prompt, opts)
end

function M.open_grok_danger(initial_prompt, opts)
  return M.open_provider("grok", "danger", initial_prompt, opts)
end

function M.open(opts)
  opts = type(opts) == "table" and opts or {}
  if not M._v5.should_select_permission_profile(state.job_id) then
    return terminal:open(opts)
  end

  return M._v5.select_permission_profile_open({
    initial_prompt = opts.initial_prompt,
    open_opts = opts.open_opts,
    open_default = M.open_default,
    open_auto = M.open_workspace_auto,
    open_danger = M.open_danger_full_access,
    open_provider = M.open_provider,
  })
end

function M.open_with_keyed_profile_menu(opts)
  opts = type(opts) == "table" and opts or {}
  if not M._v5.should_select_permission_profile(state.job_id) then
    return terminal:open(opts)
  end

  return M._v5.select_keyed_permission_profile_open({
    initial_prompt = opts.initial_prompt,
    open_opts = opts.open_opts,
    open_default = M.open_default,
    open_auto = M.open_workspace_auto,
    open_danger = M.open_danger_full_access,
    open_provider = M.open_provider,
  })
end

function M.open_with_profile_menu(opts)
  return M.open_with_keyed_profile_menu(opts)
end

compat_mod.install_prompt_open(M._v5, {
  state = state,
  terminal = terminal,
  open_with_keyed_profile_menu = function(opts)
    return M.open_with_keyed_profile_menu(opts)
  end,
})

function M.open_workspace_session(workspace, initial_prompt, opts)
  opts = opts or {}
  workspace = type(workspace) == "table" and workspace or nil
  local command, agent_provider, profile = providers.workspace_command(config, workspace, initial_prompt, opts)

  local visible = opts.visible == true
  return terminal:start_terminal(visible, initial_prompt, command, workspace, profile, {
    hidden = not visible,
    capture_workspace_session = workspace ~= nil,
    initial_mode = workspace and workspace.initial_mode,
    agent_provider = agent_provider,
    suppress_startup_plan_warning = M._v5.suppress_startup_plan_warning_for_workspace(workspace),
  })
end

function M.open_hidden(initial_prompt)
  local agent_provider = providers.default_provider(config)
  return terminal:start_terminal(false, initial_prompt, providers.command(config, agent_provider, "default"), nil, "default", {
    hidden = true,
    agent_provider = agent_provider,
  })
end

function M.open_workspace_auto_hidden(initial_prompt)
  local agent_provider = providers.default_provider(config)
  terminal:exit()
  return terminal:start_terminal(false, initial_prompt, providers.command(config, agent_provider, "auto"), nil, "auto", {
    hidden = true,
    agent_provider = agent_provider,
  })
end

function M.open_danger_full_access_hidden(initial_prompt)
  local agent_provider = providers.default_provider(config)
  terminal:exit()
  return terminal:start_terminal(false, initial_prompt, providers.command(config, agent_provider, "danger"), nil, "danger", {
    hidden = true,
    agent_provider = agent_provider,
  })
end

function M.open_workspace_auto_hidden_with_notice()
  notify("Starting " .. providers.provider_label(providers.default_provider(config)) .. " autopilot with approve-for-me permissions")
  return M.open_workspace_auto_hidden()
end

function M.open_danger_full_access_hidden_with_notice()
  notify("Starting " .. providers.provider_label(providers.default_provider(config)) .. " with no approvals and no sandbox", vim.log.levels.WARN)
  return M.open_danger_full_access_hidden()
end

function M.create_workspace(name, opts)
  return workspace_runtime:create_workspace(name, opts)
end

function M.create_mission(mission, objective, opts)
  return workspace_runtime:create_mission(mission, objective, opts)
end

function M.start_mission(name, opts)
  return workspace_runtime:start_mission(name, opts)
end

function M.update_mission_objective(name, objective, opts)
  local ok, error_message = workspace_runtime:update_mission_objective(name, objective, opts)
  if not ok and error_message then
    notify(error_message, vim.log.levels.ERROR)
  end
  return ok
end

function M.update_mission_focus_packet(name, focus_packet, opts)
  local ok, error_message = workspace_runtime:update_mission_focus_packet(name, focus_packet, opts)
  if not ok and error_message then
    notify(error_message, vim.log.levels.ERROR)
  end
  return ok
end

function M.delete_mission(name, opts)
  return workspace_runtime:delete_mission(name, opts)
end

function M.close_mission(name, opts)
  return workspace_runtime:close_mission(name, opts)
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

function M.delete_workspace(name, opts)
  opts = type(opts) == "table" and opts or {}
  local root = workspace_runtime:project_root()
  local entry, error_message = workspace_runtime:entry_for_name(root, name)
  if not entry then
    notify(error_message or "workspace not found", vim.log.levels.ERROR)
    return false
  end
  if opts.confirm ~= false and not workspace_ui.confirm_delete_workspace(entry) then
    return false
  end
  return workspace_runtime:delete_saved_workspace(entry)
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

compat_mod.install_workspace_create(M._v5, {
  controller = workspace_create_controller,
})

function M.open_workspace_prompt(opts)
  return workspace_create_controller:open_prompt(opts)
end

function M.open_workspaces()
  return workspace_manager_controller:open()
end

mission_controller = mission_setup_mod.new({
  codux = M,
  state = state,
  mission = mission_mod,
  ui = ui,
  workspace_ui = workspace_ui,
  is_valid_win = is_valid_win,
  is_loaded_buf = is_loaded_buf,
  window_buffer = window_buffer,
  buffer_filetype = buffer_filetype,
  notify = notify,
  token_usage_label = mission_token_usage_label,
  refresh_token_usage = refresh_mission_token_usage,
  token_usage_refresh_ms = token_usage_refresh_ms,
  workspace_runtime = workspace_runtime,
  workspace_entries_for_project = workspace_entries_for_project,
  edit_saved_workspace_instruction = edit_saved_workspace_instruction,
  delete_saved_workspace = delete_saved_workspace,
  switch_workspace_profile = function(entry, agent_provider, permission_profile, opts)
    return workspace_runtime:update_workspace_profile(entry, agent_provider, permission_profile, opts)
  end,
  project_root = workspace_manager_project_root,
  set_buffer_keymap = M._v5.set_buffer_keymap,
  bind_close_keys = M._v5.bind_close_keys,
  namespace = state.workspace_manager_ns,
})

function M.open_mission_prompt(opts)
  return mission_controller:open_prompt(opts)
end

function M.open_grok_mission_prompt()
  return mission_controller:open_prompt({ agent_provider = "grok" })
end

function M.open_missions()
  return mission_controller:open_dashboard()
end

function M.open_mission_dashboard()
  return M.open_missions()
end

function M.edit_mission_objective(name)
  return mission_controller:open_saved_objective_editor(name, workspace_manager_project_root())
end

function M.edit_mission_focus_packet(name)
  return mission_controller:open_saved_focus_editor(name, workspace_manager_project_root())
end

function M.delete_saved_mission(name)
  return mission_controller:delete_saved_mission(name, workspace_manager_project_root())
end

function M.close_saved_mission(name)
  return mission_controller:close_saved_mission(name, workspace_manager_project_root())
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
  return M._v5.send_prompt_or_open_with_profile(message)
end

prompt_actions = prompt_actions_setup_mod.new({
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
    agent_provider = terminal_info.agent_provider,
    last_agent_provider = terminal_info.last_agent_provider,
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

local function create_commands()
  return commands_mod.create(M, {
    notify = notify,
    workspace_manager_project_root = workspace_manager_project_root,
    mission_controller = mission_controller,
  })
end

local function remove_installed_mappings()
  return keymaps_mod.remove_installed(state)
end

local function set_mapping(mode, lhs, rhs, desc)
  return keymaps_mod.set(state, mode, lhs, rhs, desc)
end

which_key_controller = which_key_setup_mod.new({
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
  return autocmds_mod.install_workspace_target_autocmds(augroup, {
    current_filetype = current_filetype,
    is_explorer_filetype = is_explorer_filetype,
    schedule_workspace_target_sync = M._schedule_workspace_target_sync,
  })
end

function M.setup(opts)
  stop_token_monitor_timer()
  remove_installed_mappings()
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  create_commands()

  local mappings = type(config.mappings) == "table" and config.mappings or {}
  refresh_which_key()
  keymaps_mod.install_defaults(state, mappings, M, which_key_controller:mode_action_desc())
  M._install_workspace_target_autocmds()

  autocmds_mod.install_shutdown_autocmd(augroup, stop_token_monitor_timer)

  which_key_controller:install_header_hook()
end

return M
