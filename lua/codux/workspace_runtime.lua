local M = {}
M.__index = M

local command_util = require("codux.command")
local text_util = require("codux.text")
local workspace_git = require("codux.workspace_git")
local workspace_instructions = require("codux.workspace_instructions")
local workspace_launch = require("codux.workspace_launch")
local workspace_lifecycle = require("codux.workspace_lifecycle")
local workspace_prepare = require("codux.workspace_prepare")
local workspace_remote = require("codux.workspace_remote")
local workspace_registry = require("codux.workspace_registry")
local workspace_sessions = require("codux.workspace_sessions")
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
  opts = type(opts) == "table" and opts or {}
  local workspace, ensure_error = self:ensure_workspace_remote(entry, {
    attempts = opts.remote_attempts or 1,
    sleep_ms = opts.remote_sleep_ms or 100,
  })
  if not workspace then
    return nil, ensure_error or "workspace is inactive"
  end

  local server = workspace.nvim_server or self:workspace_server_path(workspace.project_root, workspace.safe_name or workspace.name)
  local output, remote_error = self:remote_luaeval(
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

  local session = self:current_tmux_session()
  if not session then
    return nil, "no tmux session running"
  end

  local preview_session = opts.preview_session or self:workspace_preview_session_name(workspace)
  self:kill_tmux_session(preview_session)
  local _, create_code = self:tmux_system({ "new-session", "-d", "-t", session, "-s", preview_session })
  if create_code ~= 0 then
    return nil, "failed to create Codux preview session"
  end

  local window_name = workspace.tmux_window or workspace.window_name or M.workspace_window_name(workspace.safe_name or workspace.name)
  local _, select_code = self:tmux_system({ "select-window", "-t", preview_session .. ":" .. window_name })
  if select_code ~= 0 then
    self:kill_tmux_session(preview_session)
    return nil, "failed to select Codux workspace preview window"
  end

  return {
    command = { "env", "-u", "TMUX", self:tmux_cmd(), "attach-session", "-t", preview_session },
    preview_session = preview_session,
    workspace = workspace,
    window_name = window_name,
    window_id = workspace.window_id,
  }, nil
end

function M:close_workspace_interactive_preview(preview)
  local session_name = type(preview) == "table" and preview.preview_session or preview
  return self:kill_tmux_session(session_name)
end

function M:ensure_workspace_remote(entry, opts)
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

  local window_name = entry.tmux_window or entry.window_name or M.workspace_window_name(safe_name)
  local attempts = math.max(1, tonumber(opts.attempts) or 1)
  local sleep_ms = math.max(1, tonumber(opts.sleep_ms) or 100)
  local last_error = "workspace is inactive"

  for attempt = 1, attempts do
    local session = self:current_tmux_session()
    if not session then
      last_error = "workspace is inactive"
    else
      local window_id = self:tmux_window_id(session, window_name)
      if not window_id then
        last_error = "workspace is inactive"
      elseif self:status_for_window(window_id) == "active" then
        entry.window_id = window_id
        entry.nvim_server = entry.nvim_server or self:workspace_server_path(root, safe_name)
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

function M:remote_workspace_call(entry, lua_expression, opts)
  opts = type(opts) == "table" and opts or {}
  local workspace = type(opts.workspace) == "table" and opts.workspace or nil
  local ensure_error = nil
  if not workspace then
    workspace, ensure_error = self:ensure_workspace_remote(entry, {
      attempts = opts.remote_attempts,
      sleep_ms = opts.remote_sleep_ms,
    })
  end
  if not workspace then
    return false, ensure_error or opts.missing_error or "workspace not found"
  end

  local server = workspace.nvim_server or self:workspace_server_path(workspace.project_root, workspace.safe_name or workspace.name)
  local output, remote_error = self:remote_luaeval(server, lua_expression, {
    attempts = opts.attempts or 15,
    sleep_ms = opts.sleep_ms or 120,
  })
  if output == "ok" then
    return true, nil, workspace
  end

  return false, remote_error or output or opts.error_message or "workspace command failed", workspace
end

function M:send_prompt_to_workspace(entry, prompt, opts)
  opts = type(opts) == "table" and opts or {}
  prompt = tostring(prompt or "")
  if trim(prompt) == "" then
    return false, "Prompt is required"
  end

  local plan_ok, plan_error, workspace = self:ensure_workspace_plan_mode(entry, {
    attempts = opts.plan_attempts or opts.attempts,
    sleep_ms = opts.plan_sleep_ms or opts.sleep_ms,
    remote_attempts = opts.remote_attempts,
    remote_sleep_ms = opts.remote_sleep_ms,
  })
  if not plan_ok then
    return false, plan_error or "Failed to switch workspace to plan mode"
  end

  return self:remote_workspace_call(entry, "require('codux')._v5.remote_send_to_codex(" .. self:lua_string(prompt) .. ")", {
    attempts = opts.attempts,
    sleep_ms = opts.sleep_ms,
    remote_attempts = opts.remote_attempts,
    remote_sleep_ms = opts.remote_sleep_ms,
    workspace = workspace,
    error_message = "Failed to send prompt",
  })
end

function M:select_workspace_question_option(entry, option, opts)
  opts = type(opts) == "table" and opts or {}
  option = trim(option)
  if option == "" then
    return false, "Option number is required"
  end
  if not option:match("^[1-4]$") then
    return false, "Option number must be 1, 2, 3, or 4"
  end

  return self:remote_workspace_call(
    entry,
    "require('codux')._v5.remote_select_codex_question_option("
      .. self:lua_string(option)
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

function M:submit_workspace_question_note(entry, note, opts)
  opts = type(opts) == "table" and opts or {}
  note = tostring(note or "")
  if trim(note) == "" then
    return false, "Note is required"
  end

  return self:remote_workspace_call(
    entry,
    "require('codux')._v5.remote_submit_codex_question_note(" .. self:lua_string(note) .. ")",
    {
      attempts = opts.attempts,
      sleep_ms = opts.sleep_ms,
      remote_attempts = opts.remote_attempts,
      remote_sleep_ms = opts.remote_sleep_ms,
      error_message = "Failed to send question note",
    }
  )
end

function M:interrupt_workspace(entry, opts)
  opts = type(opts) == "table" and opts or {}
  return self:remote_workspace_call(entry, "require('codux')._v5.remote_interrupt_codex_session()", {
    attempts = opts.attempts,
    sleep_ms = opts.sleep_ms,
    remote_attempts = opts.remote_attempts,
    remote_sleep_ms = opts.remote_sleep_ms,
    error_message = "Failed to interrupt workspace",
  })
end

function M:switch_workspace_mode(entry, opts)
  opts = type(opts) == "table" and opts or {}
  return self:remote_workspace_call(entry, "require('codux')._v5.remote_switch_codex_mode()", {
    attempts = opts.attempts,
    sleep_ms = opts.sleep_ms,
    remote_attempts = opts.remote_attempts,
    remote_sleep_ms = opts.remote_sleep_ms,
    error_message = "Failed to switch workspace mode",
  })
end

function M:ensure_workspace_plan_mode(entry, opts)
  opts = type(opts) == "table" and opts or {}
  return self:remote_workspace_call(entry, "require('codux')._v5.remote_ensure_plan_mode()", {
    attempts = opts.attempts or 60,
    sleep_ms = opts.sleep_ms or 250,
    remote_attempts = opts.remote_attempts or 60,
    remote_sleep_ms = opts.remote_sleep_ms or 250,
    error_message = "Failed to switch workspace to plan mode",
  })
end

function M:verify_workspace_launch(workspace, opts)
  opts = type(opts) == "table" and opts or {}
  workspace = type(workspace) == "table" and workspace or {}
  local safe_name = workspace.safe_name or workspace.name
  local root = workspace.project_root
  local server = workspace.nvim_server or self:workspace_server_path(root, safe_name)
  local window_name = workspace.tmux_window or workspace.window_name or M.workspace_window_name(safe_name)
  local attempts = math.max(1, tonumber(opts.attempts) or 24)
  local sleep_ms = math.max(1, tonumber(opts.sleep_ms) or 500)
  local require_codex = opts.require_codex == true
  local last_error = "workspace did not become ready"

  for attempt = 1, attempts do
    local session = self:current_tmux_session()
    if not session then
      last_error = "no tmux session running"
    else
      local window_id = self:tmux_window_id(session, window_name)
      if not window_id then
        last_error = "workspace tmux window disappeared"
      elseif self:status_for_window(window_id) ~= "active" then
        last_error = "workspace Neovim process is not running"
      else
        workspace.window_id = window_id
        local output, remote_error = self:remote_luaeval(
          server,
          "require('codux')._v5.remote_workspace_status()",
          { attempts = 1 }
        )
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
  if codex_status ~= "working" and codex_status ~= "question" and codex_status ~= "idle" then
    return false
  end
  if type(self.state.workspace) ~= "table" then
    return false
  end

  local root = self.state.workspace.project_root
  local safe_name = self.state.workspace.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false
  end

  local state_data, state_error = self:read_state()
  if state_error then
    return false
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  local record = type(workspaces) == "table" and workspaces[safe_name] or nil
  if type(record) ~= "table" then
    return false
  end

  local session = self:current_tmux_session()
  local window_name = record.tmux_window or record.window_name or self.state.workspace.window_name or safe_name
  local window_id = session and self:tmux_window_id(session, window_name) or nil
  local dashboard_status = self:dashboard_workspace_status(record, window_id)
  if inactive_like_status(dashboard_status) then
    if
      record.codex_status == "idle"
      and record.status == dashboard_status
      and record.codex_mode == nil
      and record.tmux_window == window_name
    then
      self.state.workspace.codex_status = "idle"
      self.state.workspace.status = dashboard_status
      self.state.workspace.codex_mode = nil
      return true
    end

    record.codex_status = "idle"
    record.status = dashboard_status
    record.codex_mode = nil
    record.tmux_window = window_name
    record.tmux_target = M.tmux_target(session, window_name) or record.tmux_target
    record.last_activity_at = self:timestamp()
    project.updated_at = record.last_activity_at

    local write_ok = self:write_state(state_data)
    if not write_ok then
      return false
    end

    self.state.workspace.codex_status = "idle"
    self.state.workspace.status = dashboard_status
    self.state.workspace.codex_mode = nil
    if self.state.workspace_manager_project_root == root then
      self.render_workspace_manager()
    end

    return true
  end

  local workspace_status = codex_status == "working" and "active"
    or codex_status == "question" and "question"
    or "idle"
  if record.codex_status == codex_status and record.status == workspace_status then
    self.state.workspace.codex_status = codex_status
    self.state.workspace.status = workspace_status
    return true
  end

  record.codex_status = codex_status
  record.status = workspace_status
  record.last_activity_at = self:timestamp()
  project.updated_at = record.last_activity_at

  local write_ok = self:write_state(state_data)
  if not write_ok then
    return false
  end

  self.state.workspace.codex_status = codex_status
  self.state.workspace.status = record.status
  if self.state.workspace_manager_project_root == root then
    self.render_workspace_manager()
  end

  return true
end

function M:sync_mode(mode)
  mode = self:normalize_codex_mode(mode)
  if type(self.state.workspace) ~= "table" then
    return false
  end

  local root = self.state.workspace.project_root
  local safe_name = self.state.workspace.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false
  end

  local state_data, state_error = self:read_state()
  if state_error then
    return false
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  local record = type(workspaces) == "table" and workspaces[safe_name] or nil
  if type(record) ~= "table" then
    return false
  end

  if record.codex_mode == mode then
    self.state.workspace.codex_mode = mode
    return true
  end

  record.codex_mode = mode
  project.updated_at = self:timestamp()

  local write_ok = self:write_state(state_data)
  if not write_ok then
    return false
  end

  self.state.workspace.codex_mode = mode
  if self.state.workspace_manager_project_root == root then
    self.render_workspace_manager()
  end

  return true
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

function M:saved_workspace_instruction_request(entry)
  entry = type(entry) == "table" and entry or {}
  local root = entry.project_root or self.state.workspace_manager_project_root
  local safe_name = entry.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return nil, "workspace not found"
  end

  local instruction = self:read_instruction_file(root, safe_name)
  if type(instruction) ~= "string" or trim(instruction) == "" then
    local state_data = self:read_state()
    local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
    local workspaces = type(project) == "table" and project.workspaces or nil
    local record = type(workspaces) == "table" and workspaces[safe_name] or nil
    if type(record) == "table" and type(record.resolved_instruction) == "string" then
      instruction = record.resolved_instruction
    elseif type(entry.resolved_instruction) == "string" then
      instruction = entry.resolved_instruction
    end
  end

  return {
    name = entry.name or safe_name,
    safe_name = safe_name,
    project_root = root,
    custom_instruction = instruction,
    resolved_instruction = instruction,
  }, nil
end

function M:update_saved_workspace_instruction(entry, instruction)
  entry = type(entry) == "table" and entry or {}
  instruction = type(instruction) == "string" and trim(instruction) or ""
  if instruction == "" then
    return false, "Workspace instruction is required"
  end

  local root = entry.project_root or self.state.workspace_manager_project_root
  local safe_name = entry.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false, "workspace not found"
  end

  local instruction_ok, instruction_error = self:write_instruction_file(root, safe_name, instruction)
  if not instruction_ok then
    return false, instruction_error
  end

  local state_data, state_error = self:read_state()
  if state_error then
    return false, state_error
  end

  local project = self:project_state(state_data, root)
  local record = project.workspaces[safe_name]
  if type(record) == "table" then
    record.custom_instruction = instruction
    record.resolved_instruction = instruction
    project.updated_at = self:timestamp()

    local write_ok, write_error = self:write_state(state_data)
    if not write_ok then
      return false, write_error
    end
  end

  if self.state.workspace and self.state.workspace.project_root == root and self.state.workspace.safe_name == safe_name then
    self.state.workspace.custom_instruction = instruction
    self.state.workspace.resolved_instruction = instruction
  end
  if self.state.workspace_manager_project_root == root then
    self.render_workspace_manager()
  end

  return true, nil
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
  local display_name, safe_name_or_error = M.sanitize_workspace_name(new_name)
  if not display_name then
    self.notify(safe_name_or_error, vim.log.levels.ERROR)
    return false
  end

  local root = entry.project_root or self.state.workspace_manager_project_root
  local state_data, state_error = self:read_state()
  if state_error then
    self.notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = self:project_state(state_data, root)
  local existing = project.workspaces[entry.safe_name]
  if type(existing) ~= "table" then
    self.notify("workspace not found", vim.log.levels.ERROR)
    return false
  end
  if safe_name_or_error ~= entry.safe_name and project.workspaces[safe_name_or_error] ~= nil then
    self.notify("workspace already exists", vim.log.levels.ERROR)
    return false
  end

  local new_window_name = M.workspace_window_name(safe_name_or_error)
  local old_window_name = existing.tmux_window or existing.window_name or entry.window_name or entry.safe_name
  local previous_project = vim.deepcopy(project)
  local previous_next_project = nil
  local worktree_renamed = false
  local branch_renamed = false
  local old_worktree_path = existing.worktree_path or existing.project_root or root
  local new_worktree_path = nil
  local old_branch = existing.worktree_branch
  local new_branch = nil
  if existing.workspace_kind == "worktree" then
    new_worktree_path = workspace_lifecycle.renamed_worktree_path(old_worktree_path, safe_name_or_error)
    new_branch = self:renamed_worktree_branch(existing, safe_name_or_error)
    if M.target_path_exists(new_worktree_path) then
      self.notify("worktree path already exists", vim.log.levels.ERROR)
      return false
    end
    if old_branch ~= new_branch and self:git_branch_exists(root, new_branch) then
      self.notify("branch already exists: " .. new_branch, vim.log.levels.ERROR)
      return false
    end
    previous_next_project = state_data.projects[new_worktree_path] and vim.deepcopy(state_data.projects[new_worktree_path]) or nil
    if not self:move_git_worktree(root, old_worktree_path, new_worktree_path) then
      self.notify("Failed to move Git worktree " .. tostring(old_worktree_path), vim.log.levels.ERROR)
      return false
    end
    worktree_renamed = true
    if old_branch ~= new_branch then
      if not self:rename_git_branch(new_worktree_path, old_branch, new_branch) then
        self:move_git_worktree(new_worktree_path, new_worktree_path, old_worktree_path)
        self.notify("Failed to rename Git branch " .. tostring(old_branch), vim.log.levels.ERROR)
        return false
      end
      branch_renamed = true
    end
  end
  if not self:rename_tmux_window(entry.window_id, new_window_name) then
    if existing.workspace_kind == "worktree" then
      if branch_renamed then
        self:rename_git_branch(new_worktree_path, new_branch, old_branch)
      end
      if worktree_renamed then
        self:move_git_worktree(new_worktree_path or root, new_worktree_path, old_worktree_path)
      end
    end
    self.notify("Failed to rename tmux window " .. tostring(entry.window_name), vim.log.levels.ERROR)
    return false
  end

  project.workspaces[entry.safe_name] = nil
  existing.name = display_name
  existing.safe_name = safe_name_or_error
  if existing.workspace_kind == "worktree" then
    existing.project_root = new_worktree_path
    existing.worktree_path = new_worktree_path
    existing.worktree_branch = new_branch
    existing.git_branch = new_branch
    existing.target_path =
      workspace_lifecycle.retarget_path_after_worktree_move(existing.target_path, old_worktree_path, new_worktree_path)
  end
  existing.tmux_window = new_window_name
  existing.tmux_target = entry.window_id and M.tmux_target(self:current_tmux_session(), new_window_name) or nil
  existing.status = self:dashboard_workspace_status(existing, entry.window_id)
  existing.last_opened_at = self:timestamp()
  if existing.workspace_kind == "worktree" then
    if next(project.workspaces) == nil and vim.empty_dict then
      project.workspaces = vim.empty_dict()
    end
    local next_project = self:project_state(state_data, new_worktree_path)
    next_project.workspaces[safe_name_or_error] = existing
    next_project.updated_at = self:timestamp()
  else
    project.workspaces[safe_name_or_error] = existing
  end
  project.updated_at = self:timestamp()

  local write_ok, write_error = self:write_state(state_data)
  if not write_ok then
    local rollback_errors = {}
    if entry.window_id and old_window_name ~= new_window_name and not self:rename_tmux_window(entry.window_id, old_window_name) then
      table.insert(rollback_errors, "failed to restore tmux window")
    end
    if branch_renamed and not self:rename_git_branch(new_worktree_path, new_branch, old_branch) then
      table.insert(rollback_errors, "failed to restore Git branch")
    end
    if worktree_renamed and not self:move_git_worktree(new_worktree_path or root, new_worktree_path, old_worktree_path) then
      table.insert(rollback_errors, "failed to restore Git worktree")
    end
    state_data.projects[root] = previous_project
    if new_worktree_path then
      state_data.projects[new_worktree_path] = previous_next_project
    end
    local message = write_error or "Failed to write Codux workspace state"
    if #rollback_errors > 0 then
      message = message .. "; " .. table.concat(rollback_errors, "; ")
    end
    self.notify(message, vim.log.levels.ERROR)
    return false
  end

  local instruction_root = existing.workspace_kind == "worktree" and new_worktree_path or root
  local old_instruction_path = self:instruction_file_path(instruction_root, entry.safe_name)
  local new_instruction_path = self:instruction_file_path(existing.workspace_kind == "worktree" and new_worktree_path or root, safe_name_or_error)
  if
    old_instruction_path
    and new_instruction_path
    and old_instruction_path ~= new_instruction_path
    and vim.fn.filereadable(old_instruction_path) == 1
    and vim.fn.filereadable(new_instruction_path) ~= 1
  then
    local rename_ok, rename_result = pcall(vim.fn.rename, old_instruction_path, new_instruction_path)
    if not rename_ok or rename_result ~= 0 then
      self.notify("Renamed workspace, but failed to move Codux instruction file", vim.log.levels.WARN)
    end
  end

  self.notify("Renamed Codux workspace to " .. display_name)
  self.close_workspace_manager()
  return true
end

function M:delete_saved_workspace(entry)
  entry = type(entry) == "table" and entry or {}
  local root = entry.project_root or self.state.workspace_manager_project_root
  local state_data, state_error = self:read_state()
  if state_error then
    self.notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = self:project_state(state_data, root)
  local existing = project.workspaces[entry.safe_name]
  local instruction_path = self:instruction_file_path(root, entry.safe_name)
  local has_instruction_file = instruction_path and vim.fn.filereadable(instruction_path) == 1
  if type(existing) ~= "table" and not has_instruction_file then
    self.notify("workspace not found", vim.log.levels.ERROR)
    self.render_workspace_manager()
    return false
  end

  if type(existing) == "table" and existing.workspace_kind == "worktree" then
    local worktree_path = existing.worktree_path or existing.project_root or root
    local worktree_branch = existing.worktree_branch
    local git_common_dir = existing.git_common_dir
    local previous_project = vim.deepcopy(project)
    if type(git_common_dir) ~= "string" or git_common_dir == "" then
      git_common_dir = self:git_common_dir(worktree_path)
    end
    if type(git_common_dir) ~= "string" or git_common_dir == "" then
      self.notify("Failed to resolve Git common directory for " .. tostring(worktree_path), vim.log.levels.ERROR)
      self.render_workspace_manager()
      return false
    end
    project.workspaces[entry.safe_name] = nil
    if next(project.workspaces) == nil and vim.empty_dict then
      project.workspaces = vim.empty_dict()
    end
    project.updated_at = self:timestamp()
    local write_ok, write_error = self:write_state(state_data)
    if not write_ok then
      state_data.projects[root] = previous_project
      self.notify(write_error, vim.log.levels.ERROR)
      return false
    end

    local function restore_state_after_delete(message)
      state_data.projects[root] = previous_project
      local restore_ok, restore_error = self:write_state(state_data)
      if not restore_ok then
        message = tostring(message or "Failed to delete Codux workspace")
          .. "; "
          .. tostring(restore_error or "failed to restore workspace state")
      end
      self.notify(message, vim.log.levels.ERROR)
      self.render_workspace_manager()
      return false
    end

    if entry.window_id and not self:kill_tmux_window(entry.window_id) then
      return restore_state_after_delete("Failed to close tmux window " .. tostring(entry.window_name))
    end

    local delete_instruction_ok, delete_instruction_error = self:delete_instruction_file(root, entry.safe_name)
    if not delete_instruction_ok then
      return restore_state_after_delete(delete_instruction_error)
    end

    local remove_ok, remove_error = self:remove_git_worktree_in_common_dir(git_common_dir, worktree_path)
    if not remove_ok then
      return restore_state_after_delete(remove_error or ("Failed to remove Git worktree " .. tostring(worktree_path)))
    end
    if type(worktree_branch) == "string" and worktree_branch ~= "" then
      local branch_ok, branch_error = self:delete_git_branch_in_common_dir(git_common_dir, worktree_branch)
      if not branch_ok then
        self.notify(
          (branch_error or ("Failed to delete Git branch " .. tostring(worktree_branch)))
            .. "; workspace state was removed but branch cleanup is incomplete",
          vim.log.levels.ERROR
        )
        self.render_workspace_manager()
        return false
      end
    end

    self.notify("Deleted Codux workspace " .. tostring(entry.name or entry.safe_name))
    self.close_workspace_manager()
    return true
  end

  local previous_project = vim.deepcopy(project)
  project.workspaces[entry.safe_name] = nil
  if next(project.workspaces) == nil and vim.empty_dict then
    project.workspaces = vim.empty_dict()
  end
  project.updated_at = self:timestamp()
  local write_ok, write_error = self:write_state(state_data)
  if not write_ok then
    self.notify(write_error, vim.log.levels.ERROR)
    return false
  end

  local delete_instruction_ok, delete_instruction_error = self:delete_instruction_file(root, entry.safe_name)
  if not delete_instruction_ok then
    if type(existing) == "table" then
      state_data.projects[root] = previous_project
      local restore_ok, restore_error = self:write_state(state_data)
      if not restore_ok then
        local message = (delete_instruction_error or "Failed to delete Codux workspace instruction file")
          .. "; "
          .. (restore_error or "failed to restore workspace state")
        self.notify(message, vim.log.levels.ERROR)
      else
        self.notify(delete_instruction_error, vim.log.levels.ERROR)
      end
    else
      self.notify(delete_instruction_error, vim.log.levels.ERROR)
    end
    self.render_workspace_manager()
    return false
  end

  self.notify("Deleted Codux workspace " .. tostring(entry.name or entry.safe_name))
  self.close_workspace_manager()
  self:kill_tmux_window_deferred(entry.window_id, entry.window_name)
  return true
end

function M:close_saved_workspace_window(entry)
  local root = entry.project_root or self.state.workspace_manager_project_root
  local state_data, state_error = self:read_state()
  if state_error then
    self.notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = self:project_state(state_data, root)
  local existing = project.workspaces[entry.safe_name]
  if type(existing) ~= "table" then
    self.notify("workspace not found", vim.log.levels.ERROR)
    self.render_workspace_manager()
    return false
  end

  local session = self:current_tmux_session()
  local window_name = existing.tmux_window or existing.window_name or entry.window_name or entry.safe_name
  local window_id = entry.window_id or (session and self:tmux_window_id(session, window_name)) or nil
  if window_id and not self:kill_tmux_window(window_id) then
    self.notify("Failed to close tmux window " .. tostring(window_name), vim.log.levels.ERROR)
    return false
  end

  existing.status = "inactive"
  existing.codex_status = "idle"
  existing.codex_mode = nil
  existing.tmux_window = window_name
  existing.tmux_target = nil
  existing.last_reconciled_at = self:timestamp()
  project.updated_at = existing.last_reconciled_at

  local write_ok, write_error = self:write_state(state_data)
  if not write_ok then
    self.notify(write_error, vim.log.levels.ERROR)
    return false
  end

  self.notify("Closed Codux workspace " .. tostring(existing.name or entry.name or entry.safe_name))
  self.render_workspace_manager()
  return true
end

function M:close_all_saved_workspace_windows(root)
  root = root or self.state.workspace_manager_project_root or self:project_root()
  local state_data, state_error = self:read_state()
  if state_error then
    self.notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  if type(workspaces) ~= "table" or next(workspaces) == nil then
    self.notify("No Codux workspaces to close", vim.log.levels.WARN)
    return false
  end

  local session = self:current_tmux_session()
  local closed = 0
  local failed = 0
  local now = self:timestamp()
  local close_results = {}

  for safe_name, record in pairs(workspaces) do
    if type(record) == "table" then
      local entry_safe_name = record.safe_name or safe_name
      local window_name = record.tmux_window or record.window_name or safe_name
      local window_id = session and self:tmux_window_id(session, window_name) or nil
      local close_failed = false
      if window_id then
        if self:kill_tmux_window(window_id) then
          closed = closed + 1
        else
          failed = failed + 1
          close_failed = true
        end
      end
      close_results[entry_safe_name] = not close_failed

      if not close_failed then
        record.status = "inactive"
        record.codex_status = "idle"
        record.codex_mode = nil
        record.tmux_target = nil
      end
      record.tmux_window = window_name
      record.last_reconciled_at = now
    end
  end

  project.updated_at = now
  local write_ok, write_error = self:write_state(state_data)
  if not write_ok then
    self.notify(write_error, vim.log.levels.ERROR)
    return false
  end

  if self.state.workspace and self.state.workspace.project_root == root then
    local current_safe_name = self.state.workspace.safe_name
    if close_results[current_safe_name] then
      self.state.workspace.status = "inactive"
      self.state.workspace.codex_status = "idle"
      self.state.workspace.codex_mode = nil
      self.state.workspace.tmux_target = nil
    end
  end

  if failed > 0 then
    self.notify("Closed " .. tostring(closed) .. " Codux workspaces; " .. tostring(failed) .. " failed", vim.log.levels.WARN)
  else
    self.notify("Closed " .. tostring(closed) .. " Codux workspaces")
  end
  if self.state.workspace_manager_project_root == root then
    self.render_workspace_manager()
  end

  return failed == 0
end

function M:mission_dirty_roles(name, opts)
  opts = type(opts) == "table" and opts or {}
  local root = opts.project_root or self:project_root()
  local mission, mission_error = self:mission_for_name(root, name)
  if not mission then
    return nil, mission_error or "mission not found"
  end

  local dirty = {}
  for _, entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    local path = entry.worktree_path or entry.project_root
    local label = entry.name or entry.safe_name or entry.mission_role or "unknown"
    if type(path) ~= "string" or path == "" then
      table.insert(dirty, { name = label, reason = "unknown" })
    else
      local output, code = self.system({ "git", "-C", path, "status", "--porcelain" })
      if code ~= 0 then
        table.insert(dirty, { name = label, reason = "unknown" })
      elseif trim(output) ~= "" then
        table.insert(dirty, { name = label, reason = "dirty" })
      end
    end
  end

  return dirty, nil
end

function M:close_mission(name, opts)
  opts = type(opts) == "table" and opts or {}
  local root = opts.project_root or self:project_root()
  local mission, mission_error = self:mission_for_name(root, name)
  if not mission then
    self.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  local state_data, state_error = self:read_state()
  if state_error then
    self.notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local session = self:current_tmux_session()
  local now = self:timestamp()
  local closed = 0
  local failed = 0
  local close_results = {}

  for _, entry in ipairs(vim.deepcopy(mission.roles)) do
    local entry_root = entry.project_root or root
    local safe_name = entry.safe_name
    local project = type(state_data.projects) == "table" and state_data.projects[entry_root] or nil
    local workspaces = type(project) == "table" and project.workspaces or nil
    local record = type(workspaces) == "table" and type(safe_name) == "string" and workspaces[safe_name] or nil
    if type(record) ~= "table" then
      failed = failed + 1
    else
      local window_name = record.tmux_window or record.window_name or entry.window_name or safe_name
      local window_id = entry.window_id or (session and self:tmux_window_id(session, window_name)) or nil
      local close_failed = false
      if window_id and not self:kill_tmux_window(window_id) then
        failed = failed + 1
        close_failed = true
      end

      if not close_failed then
        record.status = "inactive"
        record.codex_status = "idle"
        record.codex_mode = nil
        record.tmux_target = nil
        closed = closed + 1
        close_results[tostring(entry_root) .. "\0" .. tostring(safe_name)] = true
      end
      record.tmux_window = window_name
      record.last_reconciled_at = now
      project.updated_at = now
    end
  end

  local write_ok, write_error = self:write_state(state_data)
  if not write_ok then
    self.notify(write_error, vim.log.levels.ERROR)
    return false
  end

  if self.state.workspace then
    local key = tostring(self.state.workspace.project_root or "") .. "\0" .. tostring(self.state.workspace.safe_name or "")
    if close_results[key] then
      self.state.workspace.status = "inactive"
      self.state.workspace.codex_status = "idle"
      self.state.workspace.codex_mode = nil
      self.state.workspace.tmux_target = nil
    end
  end

  if failed > 0 then
    self.notify(
      "Closed "
        .. tostring(closed)
        .. " roles in Codux mission "
        .. tostring(mission.name or name)
        .. "; "
        .. tostring(failed)
        .. " failed",
      vim.log.levels.WARN
    )
  else
    self.notify("Closed Codux mission " .. tostring(mission.name or name) .. " with " .. tostring(closed) .. " roles")
  end

  if self.state.workspace_manager_project_root then
    self.render_workspace_manager()
  end

  return failed == 0
end

function M:start_mission(name, opts)
  opts = type(opts) == "table" and opts or {}
  local root = opts.project_root or self:project_root()
  local mission, mission_error = self:mission_for_name(root, name)
  if not mission then
    self.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  local started = 0
  local failed = 0
  local started_workspaces = {}
  for _, entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    local workspace_name = entry.name or entry.safe_name
    if type(workspace_name) ~= "string" or workspace_name == "" then
      failed = failed + 1
    else
      local workspace, workspace_error = self:prepare_workspace(workspace_name, {
        allow_existing = true,
        initial_mode = "plan",
        permission_profile = entry.permission_profile or "auto",
        require_existing = true,
        project_root = entry.project_root or root,
        restart_inactive = opts.restart_inactive == true,
      })
      if workspace then
        started = started + 1
        table.insert(started_workspaces, workspace)
        workspace.initial_mode = "plan"
        self:ensure_workspace_plan_mode(workspace)
      else
        failed = failed + 1
        local label = entry.mission_role or entry.name or entry.safe_name or "workspace"
        self.notify(
          "Failed to start Codux mission role " .. tostring(label) .. ": " .. tostring(workspace_error or "unknown error"),
          vim.log.levels.WARN
        )
      end
    end
  end

  if failed > 0 then
    self.notify(
      "Started "
        .. tostring(started)
        .. " roles in Codux mission "
        .. tostring(mission.name or name)
        .. "; "
        .. tostring(failed)
        .. " failed",
      vim.log.levels.WARN
    )
  else
    self.notify("Started Codux mission " .. tostring(mission.name or name) .. " with " .. tostring(started) .. " roles")
  end

  if self.state.workspace_manager_project_root then
    self.render_workspace_manager()
  end

  if opts.focus_first == true and failed == 0 and started_workspaces[1] then
    local workspace = started_workspaces[1]
    if not self:switch_tmux_window(workspace.window_id) then
      self.notify("Failed to switch to Codux mission role " .. tostring(workspace.mission_role or workspace.name), vim.log.levels.ERROR)
      return false
    end
  end

  return failed == 0
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

  local _, code = self:tmux_system(args)
  if code ~= 0 then
    return nil, false
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
  local workspace, error_message = self:prepare_workspace(name, {
    allow_existing = true,
    initial_mode = "plan",
    require_existing = true,
    project_root = project_root,
  })
  if not workspace then
    self.notify(error_message or "Failed to open Codux workspace", vim.log.levels.ERROR)
    return false
  end

  if not self:switch_tmux_window(workspace.window_id) then
    self.notify("Failed to switch to Codux workspace " .. workspace.name, vim.log.levels.ERROR)
    return false
  end

  local branch = workspace.git_branch ~= "" and " on " .. workspace.git_branch or ""
  self.notify("Opened Codux workspace " .. workspace.name .. branch)
  return true
end

function M:select_workspace(name)
  return self:open_saved_workspace(name, self:project_root())
end

function M:rename_workspace(old_name, new_name)
  local root = self:project_root()
  local entry, error_message = self:entry_for_name(root, old_name)
  if not entry then
    self.notify(error_message or "workspace not found", vim.log.levels.ERROR)
    return false
  end
  return self:rename_saved_workspace(entry, new_name)
end

function M:delete_workspace(name)
  local root = self:project_root()
  local entry, error_message = self:entry_for_name(root, name)
  if not entry then
    self.notify(error_message or "workspace not found", vim.log.levels.ERROR)
    return false
  end
  return self:delete_saved_workspace(entry)
end

function M:delete_mission(name, opts)
  opts = type(opts) == "table" and opts or {}
  local root = opts.project_root or self:project_root()
  local mission, mission_error = self:mission_for_name(root, name)
  if not mission then
    self.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  local deleted = 0
  for _, entry in ipairs(vim.deepcopy(mission.roles)) do
    if self:delete_saved_workspace(entry) then
      deleted = deleted + 1
    else
      self.notify(
        "Stopped deleting Codux mission "
          .. tostring(mission.name or name)
          .. " after "
          .. tostring(deleted)
          .. " roles",
        vim.log.levels.ERROR
      )
      return false
    end
  end

  self.notify("Deleted Codux mission " .. tostring(mission.name or name) .. " with " .. tostring(deleted) .. " roles")
  return true
end

function M:restore_workspaces(opts)
  opts = opts or {}
  local root = opts.project_root or self:project_root()
  local summary, error_message = self:reconcile_project(root)
  if error_message then
    self.notify(error_message, vim.log.levels.WARN)
    return false
  end

  if not opts.silent then
    self.notify(
      "Restored Codux workspaces: "
        .. tostring(summary.total)
        .. " total, "
        .. tostring(summary.active)
        .. " active, "
        .. tostring(summary.question)
        .. " question, "
        .. tostring(summary.idle)
        .. " idle, "
        .. tostring(summary.inactive)
        .. " inactive"
    )
  end

  if self.state.workspace_manager_project_root == root then
    self.render_workspace_manager()
  end

  return true
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
