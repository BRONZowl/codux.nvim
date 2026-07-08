local M = {}
M.__index = M

local command_util = require("codux.command")
local mission_lifecycle = require("codux.mission_lifecycle")
local text_util = require("codux.text")
local workspace_git = require("codux.workspace_git")
local workspace_instructions = require("codux.workspace_instructions")
local workspace_launch = require("codux.workspace_launch")
local workspace_lifecycle_actions = require("codux.workspace_lifecycle_actions")
local workspace_prepare = require("codux.workspace_prepare")
local workspace_remote = require("codux.workspace_remote")
local workspace_remote_actions = require("codux.workspace_remote_actions")
local workspace_registry = require("codux.workspace_registry")
local workspace_residue = require("codux.workspace_residue")
local workspace_sessions = require("codux.workspace_sessions")
local workspace_sync = require("codux.workspace_sync")
local workspace_target = require("codux.workspace_target")
local workspace_worktree = require("codux.workspace_worktree")

local function noop() end

local function trim(value)
  return text_util.trim(value)
end

local normalize_codex_mode = workspace_git.normalize_codex_mode
local inactive_like_status = workspace_git.inactive_like_status
local prepend_command = workspace_git.prepend_command

local function default_current_buffer()
  return vim.api.nvim_get_current_buf()
end

local function default_alternate_buffer()
  return vim.fn.bufnr("#")
end

local function default_list_buffers()
  return vim.api.nvim_list_bufs()
end

function M.sanitize_workspace_name(name)
  local display_name = trim(name)
  if display_name == "" then
    return nil, "Workspace name is required"
  end

  local safe = display_name:lower():gsub("[^%w_.-]+", "-"):gsub("-+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if safe == "" then
    return nil, "Workspace name must contain letters, numbers, dots, dashes, or underscores"
  end

  return display_name, safe
end

function M.workspace_window_name(safe_name)
  safe_name = tostring(safe_name or "")
  if safe_name == "" then
    return safe_name
  end
  return safe_name
end

function M.tmux_target(session, window_name)
  if type(session) ~= "string" or session == "" or type(window_name) ~= "string" or window_name == "" then
    return nil
  end

  return session .. ":" .. window_name
end

function M.workspace_target_signature(path, target_type, branch)
  return table.concat({
    tostring(path or ""),
    tostring(target_type or ""),
    tostring(branch or ""),
  }, "\0")
end

function M.virtual_path(path)
  return type(path) == "string" and path:match("^[%w+.-]+://") ~= nil
end

function M.target_path_exists(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  if M.virtual_path(path) then
    return false
  end

  local dir_ok, is_dir = pcall(vim.fn.isdirectory, path)
  if dir_ok and is_dir == 1 then
    return true
  end

  local file_ok, is_file = pcall(vim.fn.filereadable, path)
  return file_ok and is_file == 1
end

function M.normalize_workspace_target(path, target_type, root)
  if M.target_path_exists(path) then
    return path, target_type == "directory" and "directory" or "file"
  end

  return root, "directory"
end

function M.parse_create_args(args)
  args = type(args) == "table" and args or {}
  local name = args[1]
  if type(name) ~= "string" or trim(name) == "" then
    return nil, false, "Workspace name is required"
  end
  if name:match("^%-%-") then
    return nil, false, "Workspace name is required"
  end

  local custom_requested = false
  local index = 2
  while index <= #args do
    local arg = args[index]
    if arg == "--custom" then
      custom_requested = true
      index = index + 1
    else
      return nil, false, "unknown workspace option: " .. tostring(arg)
    end
  end

  return name, custom_requested, nil
end

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local runtime = {
    state = type(opts.state) == "table" and opts.state or {},
    defaults = type(opts.defaults) == "table" and opts.defaults or {},
    get_config = type(opts.get_config) == "function" and opts.get_config or function()
      return {}
    end,
    notify = type(opts.notify) == "function" and opts.notify or noop,
    system = type(opts.system) == "function" and opts.system or function()
      return "", 1
    end,
    command_util = type(opts.command_util) == "table" and opts.command_util or command_util,
    store = opts.store,
    current_target = type(opts.current_target) == "function" and opts.current_target or function()
      return nil
    end,
    current_buffer_name = type(opts.current_buffer_name) == "function" and opts.current_buffer_name or function()
      return ""
    end,
    current_buffer = type(opts.current_buffer) == "function" and opts.current_buffer or default_current_buffer,
    alternate_buffer = type(opts.alternate_buffer) == "function" and opts.alternate_buffer or default_alternate_buffer,
    list_buffers = type(opts.list_buffers) == "function" and opts.list_buffers or default_list_buffers,
    is_loaded_buf = type(opts.is_loaded_buf) == "function" and opts.is_loaded_buf or function()
      return false
    end,
    git_root_for = type(opts.git_root_for) == "function" and opts.git_root_for or function()
      return nil
    end,
    git_branch_for = type(opts.git_branch_for) == "function" and opts.git_branch_for or function()
      return ""
    end,
    is_explorer_filetype = type(opts.is_explorer_filetype) == "function" and opts.is_explorer_filetype or function()
      return false
    end,
    terminal_running = type(opts.terminal_running) == "function" and opts.terminal_running or function()
      return false
    end,
    render_workspace_manager = type(opts.render_workspace_manager) == "function" and opts.render_workspace_manager
      or noop,
    close_workspace_manager = type(opts.close_workspace_manager) == "function" and opts.close_workspace_manager or noop,
  }

  return setmetatable(runtime, M)
end

function M:workspace_config()
  local config = self.get_config()
  if type(config) ~= "table" then
    config = {}
  end
  if config.workspaces == false then
    return { enabled = false }
  end
  if type(config.workspaces) ~= "table" then
    return self.defaults.workspaces or {}
  end
  return config.workspaces
end

function M:workspaces_enabled()
  return self:workspace_config().enabled ~= false
end

function M:worktree_config()
  local config = self:workspace_config().worktree
  local defaults = (self.defaults.workspaces or {}).worktree or {}
  if type(config) ~= "table" then
    config = defaults
  end

  local directory = type(config.directory) == "string" and trim(config.directory) or ""
  if directory == "" then
    directory = defaults.directory or "../codux-worktrees"
  end
  local branch_prefix = type(config.branch_prefix) == "string" and trim(config.branch_prefix) or ""
  if branch_prefix == "" then
    branch_prefix = defaults.branch_prefix or "dev/"
  end

  return {
    directory = directory,
    branch_prefix = branch_prefix,
  }
end

function M:tmux_cmd()
  local value = self:workspace_config().tmux_cmd
  if type(value) == "string" and trim(value) ~= "" then
    return value
  end
  local defaults = self.defaults.workspaces or {}
  return defaults.tmux_cmd or "tmux"
end

function M:nvim_cmd()
  local value = self:workspace_config().nvim_cmd
  if type(value) == "string" and trim(value) ~= "" then
    return value
  end
  if type(vim.v.progpath) == "string" and vim.v.progpath ~= "" then
    return vim.v.progpath
  end
  return "nvim"
end

function M:tmux_system(args)
  return self.system(prepend_command(self:tmux_cmd(), args))
end

function M:nvim_system(args)
  return self.system(prepend_command(self:nvim_cmd(), args))
end

function M:git_output(root, ...)
  return workspace_worktree.git_output(self, root, ...)
end

function M:git_common_dir(root)
  return workspace_worktree.git_common_dir(self, root)
end

function M:git_current_ref(root)
  return workspace_worktree.git_current_ref(self, root)
end

function M:git_rev_parse(root, ref)
  return workspace_worktree.git_rev_parse(self, root, ref)
end

function M:git_checkout_clean(root)
  return workspace_worktree.git_checkout_clean(self, root)
end

function M:git_branch_exists(root, branch)
  return workspace_worktree.git_branch_exists(self, root, branch)
end

function M:resolve_worktree_branch(root, safe_name)
  return workspace_worktree.resolve_worktree_branch(self, root, safe_name)
end

function M:worktree_path(base_root, safe_name)
  return workspace_worktree.worktree_path(self, base_root, safe_name)
end

function M:mission_worktree_path(base_root, safe_name)
  return workspace_worktree.mission_worktree_path(self, base_root, safe_name)
end

function M:worktree_directory(root)
  return workspace_worktree.worktree_directory(self, root)
end

function M:worktree_branch(safe_name)
  return workspace_worktree.worktree_branch(self, safe_name)
end

function M:renamed_worktree_branch(existing, safe_name)
  return workspace_worktree.renamed_worktree_branch(self, existing, safe_name)
end

function M:target_in_worktree(path, target_type, base_root, worktree_root)
  return workspace_worktree.target_in_worktree(self, path, target_type, base_root, worktree_root)
end

function M:create_git_worktree(base_root, worktree_path, branch, base_ref)
  return workspace_worktree.create_git_worktree(self, base_root, worktree_path, branch, base_ref)
end

function M:remove_git_worktree(base_root, worktree_path)
  return workspace_worktree.remove_git_worktree(self, base_root, worktree_path)
end

function M:remove_git_worktree_in_common_dir(git_common_dir, worktree_path)
  return workspace_worktree.remove_git_worktree_in_common_dir(self, git_common_dir, worktree_path)
end

function M:delete_git_branch(base_root, branch)
  return workspace_worktree.delete_git_branch(self, base_root, branch)
end

function M:delete_git_branch_in_common_dir(git_common_dir, branch)
  return workspace_worktree.delete_git_branch_in_common_dir(self, git_common_dir, branch)
end

function M:move_git_worktree(base_root, old_path, new_path)
  return workspace_worktree.move_git_worktree(self, base_root, old_path, new_path)
end

function M:rename_git_branch(base_root, old_branch, new_branch)
  return workspace_worktree.rename_git_branch(self, base_root, old_branch, new_branch)
end

function M:workspace_branch_merged(entry)
  return workspace_worktree.workspace_branch_merged(self, entry)
end

function M:workspace_branch_state(entry)
  return workspace_worktree.workspace_branch_state(self, entry)
end

function M:backfill_workspace_base_commit(entry)
  return workspace_worktree.backfill_workspace_base_commit(self, entry)
end

function M:prompt_merged_workspaces(root)
  return workspace_worktree.prompt_merged_workspaces(self, root)
end

function M:cleanup_created_worktree(base_root, worktree_path, branch)
  return workspace_worktree.cleanup_created_worktree(self, base_root, worktree_path, branch)
end

function M:mission_residue_for_project(root)
  return workspace_residue.inspect(self, root)
end

function M:cleanup_mission_residue(root)
  return workspace_residue.cleanup(self, root)
end

function M:prune_empty_project_buckets(state_data, directory)
  return workspace_residue.prune_empty_project_buckets(self, state_data, directory)
end

function M:workspace_instruction_relative_dir(root)
  return workspace_instructions.relative_dir(self, root)
end

function M:workspace_instruction_ignore_rule(root)
  return workspace_instructions.ignore_rule(self, root)
end

function M:workspace_instruction_ignore_status(root)
  return workspace_instructions.ignore_status(self, root)
end

function M:workspace_instruction_ignore_warning(root)
  return workspace_instructions.ignore_warning(self, root)
end

function M:warn_workspace_instruction_ignore(root)
  return workspace_instructions.warn_ignore(self, root)
end

function M:ensure_workspace_instruction_gitignore(root)
  return workspace_instructions.ensure_gitignore(self, root)
end

function M:path_directory(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if M.virtual_path(path) then
    return nil
  end

  if vim.fn.isdirectory(path) == 1 then
    return path
  end

  local directory = vim.fn.fnamemodify(path, ":h")
  if directory ~= "" then
    return directory
  end

  return nil
end

function M:buffer_target(bufnr)
  if not self.is_loaded_buf(bufnr) then
    return nil
  end

  local ok, path = pcall(vim.api.nvim_buf_get_name, bufnr)
  if not ok or self:path_directory(path) == nil then
    return nil
  end

  return {
    path = path,
    type = vim.fn.isdirectory(path) == 1 and "directory" or "file",
    source = "buffer",
  }
end

function M:fallback_buffer_target()
  local current = self.current_buffer()
  local alternate = self.alternate_buffer()
  local alternate_target = self:buffer_target(alternate)
  if alternate_target and alternate ~= current then
    return alternate_target
  end

  for _, bufnr in ipairs(self.list_buffers()) do
    if bufnr ~= current then
      local target = self:buffer_target(bufnr)
      if target then
        return target
      end
    end
  end

  return nil
end

function M:target_context()
  local target = self.current_target()
  local path = target and target.path or self.current_buffer_name()
  if self:path_directory(path) == nil then
    target = self:fallback_buffer_target()
    path = target and target.path or nil
  end
  local directory = self:path_directory(path) or vim.fn.getcwd()
  local root = self.git_root_for(path or directory)
  local branch = self.git_branch_for(path or directory)

  return {
    target = target,
    path = path,
    directory = directory,
    root = root or directory,
    branch = branch or "",
  }
end

function M:current_tmux_session()
  if type(vim) ~= "table" or type(vim.env) ~= "table" then
    return nil
  end
  if type(vim.env.TMUX) ~= "string" or vim.env.TMUX == "" then
    return nil
  end

  local output, code = self:tmux_system({ "display-message", "-p", "#S" })
  if code ~= 0 then
    return nil
  end

  local session = trim(output)
  if session == "" then
    return nil
  end

  return session
end

function M:tmux_window_id(session, window_name)
  local output, code = self:tmux_system({ "list-windows", "-t", session, "-F", "#{window_id}\t#{window_name}" })
  if code ~= 0 then
    return nil
  end

  for line in output:gmatch("[^\r\n]+") do
    local id, name = line:match("^([^\t]+)\t(.+)$")
    if name == window_name then
      return id
    end
  end

  return nil
end

function M:tmux_window_command(window_id)
  local commands = self:tmux_window_commands(window_id)
  return commands[1]
end

function M:tmux_window_commands(window_id)
  if type(window_id) ~= "string" or window_id == "" then
    return {}
  end

  local output, code = self:tmux_system({ "list-panes", "-t", window_id, "-F", "#{pane_current_command}" })
  if code ~= 0 then
    return {}
  end

  local commands = {}
  for line in output:gmatch("[^\r\n]+") do
    local command = trim(line)
    if command ~= "" then
      table.insert(commands, command)
    end
  end

  return commands
end

function M:kill_tmux_session(session_name)
  if type(session_name) ~= "string" or session_name == "" then
    return false
  end
  local _, code = self:tmux_system({ "kill-session", "-t", session_name })
  return code == 0
end

function M:status_for_window(window_id)
  if not window_id then
    return "inactive"
  end

  for _, command in ipairs(self:tmux_window_commands(window_id)) do
    local lower = type(command) == "string" and command:lower() or ""
    if lower == "nvim" or lower == "vim" or lower:find("nvim", 1, true) or lower:find("vim", 1, true) then
      return "active"
    end
  end

  return "inactive"
end

function M:dashboard_workspace_status(record, window_id)
  local window_status = self:status_for_window(window_id)
  if window_status ~= "active" then
    return "inactive"
  end

  record = type(record) == "table" and record or {}
  if record.codex_status == "working" then
    return "active"
  end
  if record.codex_status == "question" then
    return "question"
  end
  return "idle"
end

function M:workspace_server_dir()
  return workspace_remote.server_dir()
end

function M:workspace_server_path(root, safe_name)
  return workspace_remote.server_path(root, safe_name, self:workspace_server_dir())
end

function M:workspace_launch_server_path(root, safe_name)
  return workspace_remote.launch_server_path(root, safe_name, self:workspace_server_dir())
end

function M:remote_luaeval(server, lua_expression, opts)
  return workspace_remote.remote_luaeval(function(args)
    return self:nvim_system(args)
  end, server, lua_expression, opts)
end

function M:workspace_preview_session_name(entry)
  return workspace_remote.preview_session_name(entry)
end

function M:workspace_interactive_preview(entry, opts)
  return workspace_remote_actions.workspace_interactive_preview(self, entry, opts)
end

function M:close_workspace_interactive_preview(preview)
  return workspace_remote_actions.close_workspace_interactive_preview(self, preview)
end

function M:ensure_workspace_remote(entry, opts)
  return workspace_remote_actions.ensure_workspace_remote(self, entry, opts)
end

function M:remote_workspace_call(entry, lua_expression, opts)
  return workspace_remote_actions.remote_workspace_call(self, entry, lua_expression, opts)
end

function M:send_prompt_to_workspace(entry, prompt, opts)
  return workspace_remote_actions.send_prompt_to_workspace(self, entry, prompt, opts)
end

function M:select_workspace_question_option(entry, option, opts)
  return workspace_remote_actions.select_workspace_question_option(self, entry, option, opts)
end

function M:submit_workspace_question_note(entry, note, opts)
  return workspace_remote_actions.submit_workspace_question_note(self, entry, note, opts)
end

function M:interrupt_workspace(entry, opts)
  return workspace_remote_actions.interrupt_workspace(self, entry, opts)
end

function M:switch_workspace_mode(entry, opts)
  return workspace_remote_actions.switch_workspace_mode(self, entry, opts)
end

function M:ensure_workspace_plan_mode(entry, opts)
  return workspace_remote_actions.ensure_workspace_plan_mode(self, entry, opts)
end

function M:verify_workspace_launch(workspace, opts)
  return workspace_remote_actions.verify_workspace_launch(self, workspace, opts)
end

function M:normalize_codex_mode(mode)
  return normalize_codex_mode(mode)
end

function M:permission_profile()
  if self.terminal_running() then
    return self.state.permission_profile or "default"
  end
  return self.state.last_permission_profile or "default"
end

function M:state_file()
  return self.store:state_file()
end

function M:read_state()
  return self.store:read_state()
end

function M:write_state(state_data)
  return self.store:write_state(state_data)
end

function M:timestamp()
  return self.store.timestamp()
end

function M:project_state(state_data, root)
  return self.store:project_state(state_data, root)
end

function M:workspace_from_state(record, fallback)
  return self.store.workspace_from_state(record, fallback)
end

function M:state_record(workspace, existing)
  return self.store:state_record(workspace, existing)
end

function M:instruction_files_config()
  return workspace_instructions.files_config(self)
end

function M:instruction_directory(root)
  return workspace_instructions.directory(self, root)
end

function M:instruction_file_path(root, safe_name)
  return workspace_instructions.file_path(self, root, safe_name)
end

function M:read_instruction_file(root, safe_name)
  return workspace_instructions.read_file(self, root, safe_name)
end

function M:write_instruction_file(root, safe_name, instruction)
  return workspace_instructions.write_file(self, root, safe_name, instruction)
end

function M:delete_instruction_file(root, safe_name)
  return workspace_instructions.delete_file(self, root, safe_name)
end

function M:instruction_file_records(root)
  return workspace_instructions.file_records(self, root)
end

function M:normalize_record(record, safe_name, root)
  return self.store:normalize_record(record, safe_name, root)
end

function M:apply_codex_session_meta(workspace, meta)
  return workspace_sessions.apply_meta(self, workspace, meta)
end

function M:resolve_workspace_resume_session(workspace)
  return workspace_sessions.resolve_resume(self, workspace)
end

function M:codex_home()
  return workspace_sessions.codex_home(self)
end

function M:codex_session_files()
  return workspace_sessions.session_files(self)
end

function M:read_codex_session_meta(path)
  return workspace_sessions.read_meta(self, path)
end

function M:codex_session_for_id(session_id)
  return workspace_sessions.session_for_id(self, session_id)
end

function M:latest_codex_session_for_cwd(cwd, min_mtime)
  return workspace_sessions.latest_for_cwd(self, cwd, min_mtime)
end

function M:persist_workspace_session_meta(workspace, meta)
  return workspace_sessions.persist_meta(self, workspace, meta)
end

function M:schedule_workspace_session_capture(workspace, min_mtime)
  return workspace_sessions.schedule_capture(self, workspace, min_mtime)
end

function M:sync_activity(codex_status)
  return workspace_sync.sync_activity(self, codex_status)
end

function M:sync_mode(mode)
  return workspace_sync.sync_mode(self, mode)
end

function M:entries_for_project(root)
  return workspace_registry.entries_for_project(self, root)
end

function M:missions_for_project(root)
  return workspace_registry.missions_for_project(self, root)
end

function M:mission_for_name(root, name)
  return workspace_registry.mission_for_name(self, root, name)
end

function M:mission_names_for_project(root)
  return workspace_registry.mission_names_for_project(self, root)
end

function M:update_mission_objective(name, objective, opts)
  return workspace_registry.update_mission_objective(self, name, objective, opts)
end

function M:update_mission_focus_packet(name, focus_packet, opts)
  return workspace_registry.update_mission_focus_packet(self, name, focus_packet, opts)
end

function M:rename_mission_role(entry, new_name, opts)
  return workspace_lifecycle_actions.rename_mission_role(self, entry, new_name, opts)
end

function M:saved_workspace_instruction_request(entry)
  return workspace_lifecycle_actions.saved_workspace_instruction_request(self, entry)
end

function M:update_saved_workspace_instruction(entry, instruction)
  return workspace_lifecycle_actions.update_saved_workspace_instruction(self, entry, instruction)
end

function M:entry_for_name(root, name)
  return workspace_registry.entry_for_name(self, root, name)
end

function M:names_for_project(root)
  return workspace_registry.names_for_project(self, root)
end

function M:reconcile_project(root)
  return workspace_registry.reconcile_project(self, root)
end

function M:project_root()
  return self:target_context().root
end

function M:rename_tmux_window(window_id, new_window_name)
  if not window_id then
    return true
  end
  local _, code = self:tmux_system({ "rename-window", "-t", window_id, new_window_name })
  return code == 0
end

function M:kill_tmux_window(window_id)
  if not window_id then
    return true
  end
  local _, code = self:tmux_system({ "kill-window", "-t", window_id })
  return code == 0
end

function M:kill_tmux_window_deferred(window_id, window_name)
  if not window_id then
    return
  end

  vim.defer_fn(function()
    if not self:kill_tmux_window(window_id) then
      self.notify("Failed to kill tmux window " .. tostring(window_name), vim.log.levels.WARN)
    end
  end, 100)
end

function M:rename_saved_workspace(entry, new_name)
  return workspace_lifecycle_actions.rename_saved_workspace(self, entry, new_name)
end

function M:delete_saved_workspace(entry)
  return workspace_lifecycle_actions.delete_saved_workspace(self, entry)
end

function M:close_saved_workspace_window(entry)
  return workspace_lifecycle_actions.close_saved_workspace_window(self, entry)
end

function M:close_all_saved_workspace_windows(root)
  return workspace_lifecycle_actions.close_all_saved_workspace_windows(self, root)
end

function M:mission_dirty_roles(name, opts)
  return mission_lifecycle.dirty_roles(self, name, opts)
end

function M:close_mission(name, opts)
  return mission_lifecycle.close(self, name, opts)
end

function M:start_mission(name, opts)
  return mission_lifecycle.start(self, name, opts)
end

function M:shell_env_assignment(name, value)
  return workspace_launch.shell_env_assignment(name, value)
end

function M:lua_string(value)
  return workspace_launch.lua_string(value)
end

function M:bootstrap_lua(workspace)
  return workspace_launch.bootstrap_lua(workspace)
end

function M:write_launch_script(workspace)
  return workspace_launch.write_launch_script(self, workspace)
end

function M:delete_launch_script(path)
  return workspace_launch.delete_launch_script(path)
end

function M:nvim_command(workspace)
  return workspace_launch.nvim_command(self, workspace)
end

function M:ensure_tmux_window(session, root, window_name, command, opts)
  opts = type(opts) == "table" and opts or {}
  local existing = self:tmux_window_id(session, window_name)
  if existing then
    if opts.restart_inactive and inactive_like_status(self:status_for_window(existing)) then
      if not self:kill_tmux_window(existing) then
        return nil, false
      end
    else
      return existing, false
    end
  end

  if existing and opts.restart_inactive then
    existing = self:tmux_window_id(session, window_name)
  end
  if existing then
    return existing, false
  end

  local args = { "new-window", "-d", "-t", session .. ":", "-n", window_name, "-c", root }
  if type(command) == "string" and command ~= "" then
    table.insert(args, command)
  end

  local output, code = self:tmux_system(args)
  if code ~= 0 then
    return nil, false, trim(output)
  end

  return self:tmux_window_id(session, window_name), true
end

function M:switch_tmux_window(window_id)
  local _, code = self:tmux_system({ "select-window", "-t", window_id })
  return code == 0
end

function M:prepare_workspace(name, opts)
  return workspace_prepare.prepare(self, name, opts)
end

function M:create_workspace(name, opts)
  opts = opts or {}
  local workspace, error_message = self:prepare_workspace(name, {
    custom_instruction = opts.custom_instruction,
    resolved_instruction = opts.resolved_instruction,
    initial_prompt = opts.initial_prompt,
    initial_mode = "plan",
    permission_profile = opts.permission_profile,
    mission_id = opts.mission_id,
    mission_name = opts.mission_name,
    mission_role = opts.mission_role,
    mission_objective = opts.mission_objective,
    mission_focus_packet = opts.mission_focus_packet,
  })
  if not workspace then
    self.notify(error_message or "Failed to prepare Codux workspace", vim.log.levels.ERROR)
    return false
  end

  local branch = workspace.git_branch ~= "" and " on " .. workspace.git_branch or ""
  self.notify("Created Codux workspace " .. workspace.name .. branch)
  return true
end

function M:preflight_mission(mission)
  return workspace_prepare.preflight_mission(self, mission)
end

function M:create_mission(mission_or_name, objective, opts)
  return workspace_prepare.create_mission(self, mission_or_name, objective, opts)
end

function M:open_saved_workspace(name, project_root)
  return workspace_lifecycle_actions.open_saved_workspace(self, name, project_root)
end

function M:select_workspace(name)
  return workspace_lifecycle_actions.select_workspace(self, name)
end

function M:rename_workspace(old_name, new_name)
  return workspace_lifecycle_actions.rename_workspace(self, old_name, new_name)
end

function M:delete_workspace(name)
  return workspace_lifecycle_actions.delete_workspace(self, name)
end

function M:delete_mission(name, opts)
  return mission_lifecycle.delete(self, name, opts)
end

function M:restore_workspaces(opts)
  return workspace_lifecycle_actions.restore_workspaces(self, opts)
end

function M:target_sync_allowed(event, current_filetype)
  return workspace_target.sync_allowed(self, event, current_filetype)
end

function M:sync_target(event, current_filetype)
  return workspace_target.sync(self, event, current_filetype)
end

function M:schedule_target_sync(event, sync_fn)
  return workspace_target.schedule(self, event, sync_fn)
end

function M:attach_workspace(workspace, schedule_sync)
  return workspace_target.attach(self, workspace, schedule_sync)
end

return M
