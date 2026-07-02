local M = {}
M.__index = M

local command_util = require("codux.command")

local function noop() end

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function strip_trailing_slashes(value)
  value = tostring(value or "")
  while #value > 1 and value:sub(-1) == "/" do
    value = value:sub(1, -2)
  end
  return value
end

local function path_join(...)
  local parts = {}
  for _, value in ipairs({ ... }) do
    value = tostring(value or "")
    if value ~= "" then
      table.insert(parts, value)
    end
  end
  return table.concat(parts, "/"):gsub("/+", "/")
end

local function normalize_absolute_path(base, path)
  path = tostring(path or "")
  if path == "" then
    return nil
  end
  if path:sub(1, 1) ~= "/" then
    path = path_join(base, path)
  end

  local stack = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #stack > 0 then
        table.remove(stack)
      end
    elseif part ~= "." and part ~= "" then
      table.insert(stack, part)
    end
  end

  return "/" .. table.concat(stack, "/")
end

local function normalize_relative_directory(value)
  value = trim(value)
  value = value:gsub("^%./+", "")
  value = value:gsub("/+$", "")
  return value
end

local function starts_with_path(path, root)
  path = strip_trailing_slashes(path)
  root = strip_trailing_slashes(root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function relative_path_escapes_root(value)
  value = normalize_relative_directory(value)
  return value == ".." or value:sub(1, 3) == "../" or value:find("/%.%./") ~= nil or value:sub(-3) == "/.."
end

local function normalize_codex_mode(mode)
  if mode == "execute" or mode == "plan" then
    return mode
  end

  return nil
end

local function inactive_like_status(status)
  return status == "inactive"
end

local function prepend_command(command, args)
  local result = { command }
  for _, arg in ipairs(args or {}) do
    table.insert(result, arg)
  end
  return result
end

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

function M.target_path_exists(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  if path:match("^term://") or path:match("^codux://") then
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

function M:git_output(root, ...)
  local args = { "git", "-C", root }
  for _, arg in ipairs({ ... }) do
    table.insert(args, arg)
  end
  local output, code = self.system(args)
  if code ~= 0 then
    return nil, code
  end
  return trim(output), code
end

function M:git_common_dir(root)
  local output = self:git_output(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
  if output and output ~= "" then
    return strip_trailing_slashes(output)
  end

  output = self:git_output(root, "rev-parse", "--git-common-dir")
  if output and output ~= "" then
    return strip_trailing_slashes(normalize_absolute_path(root, output))
  end

  return nil
end

function M:git_current_ref(root)
  local branch = self:git_output(root, "branch", "--show-current")
  if branch and branch ~= "" then
    return branch
  end

  local head = self:git_output(root, "rev-parse", "--short", "HEAD")
  if head and head ~= "" then
    return head
  end

  return "HEAD"
end

function M:git_checkout_clean(root)
  local output, code = self.system({ "git", "-C", root, "status", "--porcelain" })
  if code ~= 0 then
    return false, "not inside a Git repository"
  end
  if trim(output) ~= "" then
    return false, "current branch must be clean before creating a Codux workspace"
  end
  return true, nil
end

function M:git_branch_exists(root, branch)
  local _, code = self.system({ "git", "-C", root, "show-ref", "--verify", "--quiet", "refs/heads/" .. tostring(branch or "") })
  return code == 0
end

function M:resolve_worktree_branch(root, safe_name)
  local prefix = self:worktree_config().branch_prefix
  local prefix_namespace = prefix:match("^(.-)/+$")
  if not prefix_namespace or prefix_namespace == "" then
    local branch = prefix .. tostring(safe_name or "")
    if self:git_branch_exists(root, branch) then
      return nil, "branch already exists: " .. branch
    end
    return branch, nil
  end

  for index = 0, 99 do
    local namespace = index == 0 and prefix_namespace or (prefix_namespace .. tostring(index))
    if not self:git_branch_exists(root, namespace) then
      local branch = namespace .. "/" .. tostring(safe_name or "")
      if self:git_branch_exists(root, branch) then
        return nil, "branch already exists: " .. branch
      end
      return branch, nil
    end
  end

  return nil, "no available branch namespace for " .. prefix_namespace .. "/"
end

function M:worktree_path(base_root, safe_name)
  local config = self:worktree_config()
  local directory = config.directory
  if directory:sub(1, 1) ~= "/" then
    directory = normalize_absolute_path(base_root, directory)
  end
  return normalize_absolute_path(directory, safe_name)
end

function M:worktree_branch(safe_name)
  return self:worktree_config().branch_prefix .. tostring(safe_name or "")
end

function M:renamed_worktree_branch(existing, safe_name)
  existing = type(existing) == "table" and existing or {}
  local branch = existing.worktree_branch
  if type(branch) == "string" then
    local namespace = branch:match("^(.*)/[^/]+$")
    if namespace and namespace ~= "" then
      return namespace .. "/" .. tostring(safe_name or "")
    end
  end
  return self:worktree_branch(safe_name)
end

function M:target_in_worktree(path, target_type, base_root, worktree_root)
  if type(path) ~= "string" or path == "" then
    return worktree_root, "directory"
  end

  local normalized_base = strip_trailing_slashes(base_root)
  local normalized_path = strip_trailing_slashes(path)
  if starts_with_path(normalized_path, normalized_base) then
    local suffix = normalized_path:sub(#normalized_base + 1)
    if suffix:sub(1, 1) == "/" then
      suffix = suffix:sub(2)
    end
    if suffix == "" then
      return worktree_root, "directory"
    end
    return normalize_absolute_path(worktree_root, suffix), target_type == "directory" and "directory" or "file"
  end

  return worktree_root, "directory"
end

function M:create_git_worktree(base_root, worktree_path, branch, base_ref)
  local output, code = self.system({ "git", "-C", base_root, "worktree", "add", "-b", branch, worktree_path, base_ref })
  if code ~= 0 then
    local detail = trim(output)
    local message = "Failed to create Git worktree " .. tostring(worktree_path)
    if detail ~= "" then
      message = message .. ": " .. detail
    end
    return false, message
  end
  return true, nil
end

function M:remove_git_worktree(base_root, worktree_path)
  local _, code = self.system({ "git", "-C", base_root, "worktree", "remove", "--force", worktree_path })
  return code == 0
end

function M:delete_git_branch(base_root, branch)
  local _, code = self.system({ "git", "-C", base_root, "branch", "-D", branch })
  return code == 0
end

function M:move_git_worktree(base_root, old_path, new_path)
  local _, code = self.system({ "git", "-C", base_root, "worktree", "move", old_path, new_path })
  return code == 0
end

function M:rename_git_branch(base_root, old_branch, new_branch)
  local _, code = self.system({ "git", "-C", base_root, "branch", "-m", old_branch, new_branch })
  return code == 0
end

function M:workspace_branch_merged(entry)
  entry = type(entry) == "table" and entry or {}
  if entry.workspace_kind ~= "worktree" then
    return false
  end
  local branch = entry.worktree_branch
  local base = entry.worktree_base
  local root = entry.project_root or entry.worktree_path
  if type(branch) ~= "string" or branch == "" or type(base) ~= "string" or base == "" or type(root) ~= "string" then
    return false
  end
  local _, code = self.system({ "git", "-C", root, "merge-base", "--is-ancestor", branch, base })
  return code == 0
end

function M:prompt_merged_workspaces(root)
  local entries, error_message = self:entries_for_project(root)
  if error_message then
    return false
  end

  self.state.merged_workspace_cleanup_declined = type(self.state.merged_workspace_cleanup_declined) == "table"
      and self.state.merged_workspace_cleanup_declined
    or {}

  for _, entry in ipairs(entries) do
    local key = tostring(entry.project_root or "") .. "\0" .. tostring(entry.safe_name or "")
    if not self.state.merged_workspace_cleanup_declined[key] and self:workspace_branch_merged(entry) then
      local choice = vim.fn.confirm(
        "Codux workspace " .. tostring(entry.name or entry.safe_name) .. " has been merged. Delete workspace/worktree?",
        "&Yes\n&No",
        2
      )
      if choice == 1 then
        return self:delete_saved_workspace(entry)
      end
      self.state.merged_workspace_cleanup_declined[key] = true
    end
  end

  return true
end

function M:cleanup_created_worktree(base_root, worktree_path, branch)
  if type(worktree_path) == "string" and worktree_path ~= "" then
    self:remove_git_worktree(base_root, worktree_path)
  end
  if type(branch) == "string" and branch ~= "" then
    self:delete_git_branch(base_root, branch)
  end
end

function M:workspace_instruction_relative_dir(root)
  local config = self:instruction_files_config()
  if type(config) ~= "table" or config.enabled == false then
    return nil
  end
  if type(root) ~= "string" or root == "" then
    return nil
  end

  local configured = normalize_relative_directory(config.directory)
  if configured == "" then
    return nil
  end
  if relative_path_escapes_root(configured) then
    return nil
  end
  if configured:match("^/") or configured:match("^~") then
    local directory = self:instruction_directory(root)
    if type(directory) ~= "string" or directory == "" or not starts_with_path(directory, root) or directory == root then
      return nil
    end
    return normalize_relative_directory(directory:sub(#strip_trailing_slashes(root) + 2))
  end

  return configured
end

function M:workspace_instruction_ignore_rule(root)
  local relative_dir = self:workspace_instruction_relative_dir(root)
  if not relative_dir then
    return nil
  end

  if relative_dir == ".agents" or relative_dir:sub(1, 8) == ".agents/" then
    return ".agents/"
  end

  return relative_dir .. "/"
end

function M:workspace_instruction_ignore_status(root)
  local relative_dir = self:workspace_instruction_relative_dir(root)
  if not relative_dir then
    return {
      status = "skipped",
      reason = "workspace instruction files are disabled or outside the project",
    }
  end

  local marker = relative_dir .. "/.codux-ignore-check"
  local _, code = self.system({ "git", "-C", root, "check-ignore", "--quiet", "--", marker })
  if code == 0 then
    return {
      status = "ignored",
      relative_dir = relative_dir,
      marker = marker,
      rule = self:workspace_instruction_ignore_rule(root),
    }
  end
  if code == 1 then
    return {
      status = "not_ignored",
      relative_dir = relative_dir,
      marker = marker,
      rule = self:workspace_instruction_ignore_rule(root),
    }
  end

  return {
    status = "unknown",
    relative_dir = relative_dir,
    marker = marker,
    rule = self:workspace_instruction_ignore_rule(root),
  }
end

function M:workspace_instruction_ignore_warning(root)
  local status = self:workspace_instruction_ignore_status(root)
  if status.status ~= "not_ignored" then
    return nil
  end

  return "Codux workspace instructions are not ignored by Git. Add "
    .. tostring(status.rule or status.relative_dir .. "/")
    .. " to .gitignore or run :CoduxWorkspaceIgnore."
end

function M:warn_workspace_instruction_ignore(root)
  local warning = self:workspace_instruction_ignore_warning(root)
  if not warning then
    return false
  end

  self.state.workspace_instruction_ignore_warnings = type(self.state.workspace_instruction_ignore_warnings) == "table"
      and self.state.workspace_instruction_ignore_warnings
    or {}
  local relative_dir = self:workspace_instruction_relative_dir(root) or ""
  local key = tostring(root or "") .. "\n" .. relative_dir
  if self.state.workspace_instruction_ignore_warnings[key] then
    return false
  end

  self.state.workspace_instruction_ignore_warnings[key] = true
  self.notify(warning, vim.log.levels.WARN)
  return true
end

function M:ensure_workspace_instruction_gitignore(root)
  root = type(root) == "string" and root ~= "" and root or self:target_context().root
  if type(root) ~= "string" or root == "" then
    return false, "project root not detected"
  end

  local status = self:workspace_instruction_ignore_status(root)
  if status.status == "skipped" then
    return false, "workspace instruction files are disabled or outside the project"
  end
  if status.status == "unknown" then
    return false, "not inside a Git repository or unable to check .gitignore"
  end

  local rule = status.rule or self:workspace_instruction_ignore_rule(root)
  if type(rule) ~= "string" or rule == "" then
    return false, "workspace instruction ignore rule could not be determined"
  end

  local path = root .. "/.gitignore"
  local lines = {}
  if vim.fn.filereadable(path) == 1 then
    local ok, read_lines = pcall(vim.fn.readfile, path)
    if not ok or type(read_lines) ~= "table" then
      return false, "Failed to read .gitignore"
    end
    lines = read_lines
  end

  for _, line in ipairs(lines) do
    if trim(line) == rule then
      return true, "Codux workspace instructions are already ignored by Git"
    end
  end

  if #lines > 0 and lines[#lines] ~= "" then
    table.insert(lines, "")
  end
  table.insert(lines, "# Codux workspace instructions")
  table.insert(lines, rule)

  local ok, result = pcall(vim.fn.writefile, lines, path)
  if not ok or result ~= 0 then
    return false, "Failed to update .gitignore"
  end

  return true, "Added " .. rule .. " to .gitignore"
end

function M:path_directory(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:match("^term://") then
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
  if self.store and type(self.store.instruction_files_config) == "function" then
    return self.store:instruction_files_config()
  end
  local workspaces = self:workspace_config()
  if workspaces.enabled == false or workspaces.instruction_files == false then
    return { enabled = false }
  end
  local defaults = self.defaults.workspaces or {}
  local default_instruction_files = defaults.instruction_files or { enabled = true, directory = ".agents/codux" }
  local value = type(workspaces.instruction_files) == "table" and workspaces.instruction_files or default_instruction_files
  local directory = type(value.directory) == "string" and trim(value.directory) or ""
  if directory == "" then
    directory = default_instruction_files.directory or ".agents/codux"
  end
  return {
    enabled = value.enabled ~= false,
    directory = directory,
  }
end

function M:instruction_directory(root)
  if self.store and type(self.store.instruction_directory) == "function" then
    return self.store:instruction_directory(root)
  end
  local file_config = self:instruction_files_config()
  if file_config.enabled == false or type(root) ~= "string" or root == "" then
    return nil
  end
  local directory = vim.fn.expand(file_config.directory)
  if directory == "" then
    return nil
  end
  if directory:match("^/") then
    return directory
  end
  return root .. "/" .. directory
end

function M:instruction_file_path(root, safe_name)
  return self.store:instruction_file_path(root, safe_name)
end

function M:read_instruction_file(root, safe_name)
  return self.store:read_instruction_file(root, safe_name)
end

function M:write_instruction_file(root, safe_name, instruction)
  return self.store:write_instruction_file(root, safe_name, instruction)
end

function M:delete_instruction_file(root, safe_name)
  return self.store:delete_instruction_file(root, safe_name)
end

function M:instruction_file_records(root)
  return self.store:instruction_file_records(root)
end

function M:normalize_record(record, safe_name, root)
  return self.store:normalize_record(record, safe_name, root)
end

function M:apply_codex_session_meta(workspace, meta)
  return self.store.apply_codex_session_meta(workspace, meta)
end

function M:resolve_workspace_resume_session(workspace)
  return self.store:resolve_workspace_resume_session(workspace)
end

function M:codex_home()
  return self.store:codex_home()
end

function M:codex_session_files()
  return self.store:codex_session_files()
end

function M:read_codex_session_meta(path)
  return self.store:read_codex_session_meta(path)
end

function M:codex_session_for_id(session_id)
  return self.store:codex_session_for_id(session_id)
end

function M:latest_codex_session_for_cwd(cwd, min_mtime)
  return self.store:latest_codex_session_for_cwd(cwd, min_mtime)
end

function M:persist_workspace_session_meta(workspace, meta)
  if type(workspace) ~= "table" or type(meta) ~= "table" then
    return false
  end

  local root = workspace.project_root
  local safe_name = workspace.safe_name
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

  local session_id = self.store.normalize_session_id(meta.session_id)
  if not session_id then
    return false
  end
  if meta.cwd ~= root then
    return false
  end

  record.codex_session_id = session_id
  record.codex_session_path = meta.path
  record.codex_session_captured_at = self:timestamp()
  project.updated_at = record.codex_session_captured_at

  local write_ok = self:write_state(state_data)
  if not write_ok then
    return false
  end

  workspace.codex_session_id = record.codex_session_id
  workspace.codex_session_path = record.codex_session_path
  workspace.codex_session_captured_at = record.codex_session_captured_at
  if
    self.state.workspace == workspace
    or (self.state.workspace and self.state.workspace.safe_name == safe_name and self.state.workspace.project_root == root)
  then
    self.state.workspace.codex_session_id = record.codex_session_id
    self.state.workspace.codex_session_path = record.codex_session_path
    self.state.workspace.codex_session_captured_at = record.codex_session_captured_at
  end
  if self.state.workspace_manager_project_root == root then
    self.render_workspace_manager()
  end

  return true
end

function M:schedule_workspace_session_capture(workspace, min_mtime)
  if type(workspace) ~= "table" then
    return
  end

  min_mtime = tonumber(min_mtime) or 0
  local attempts = 0

  local function capture()
    attempts = attempts + 1
    local meta = nil
    local session_id = self.store.normalize_session_id(workspace.codex_session_id)
    if session_id then
      meta = self:codex_session_for_id(session_id)
    end
    if not meta then
      meta = self:latest_codex_session_for_cwd(workspace.project_root, min_mtime)
    end
    if meta and self:persist_workspace_session_meta(workspace, meta) then
      return
    end
    if attempts < 12 then
      vim.defer_fn(capture, 500)
    end
  end

  vim.defer_fn(capture, 500)
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
  local state_data, state_error = self:read_state()
  if state_error then
    return {}, state_error
  end

  local current_common_dir = self:git_common_dir(root)
  local session = self:current_tmux_session()
  local entries = {}
  local seen = {}

  if type(state_data.projects) == "table" then
    for project_root, project in pairs(state_data.projects) do
      local workspaces = type(project) == "table" and project.workspaces or nil
      if type(workspaces) == "table" then
        for safe_name, record in pairs(workspaces) do
          if type(record) == "table" then
            local record_root = record.project_root or project_root
            local include = record_root == root
              or (
                current_common_dir ~= nil
                and record.workspace_kind == "worktree"
                and record.git_common_dir == current_common_dir
              )
            if include then
              local entry_safe_name = record.safe_name or safe_name
              local window_name = record.tmux_window or record.window_name or entry_safe_name
              local window_id = session and self:tmux_window_id(session, window_name) or nil
              local status = self:dashboard_workspace_status(record, window_id)
              local codex_mode = not inactive_like_status(status) and self:normalize_codex_mode(record.codex_mode) or nil
              seen[tostring(record_root) .. "\0" .. tostring(entry_safe_name)] = true
              table.insert(entries, {
                name = record.name or entry_safe_name,
                safe_name = entry_safe_name,
                project_root = record_root,
                target_path = record.target_path,
                target_type = record.target_type,
                git_branch = record.git_branch or "",
                workspace_kind = record.workspace_kind,
                git_common_dir = record.git_common_dir,
                worktree_path = record.worktree_path,
                worktree_branch = record.worktree_branch,
                worktree_base = record.worktree_base,
                window_name = window_name,
                tmux_target = M.tmux_target(session, window_name) or record.tmux_target,
                codex_status = record.codex_status or "idle",
                codex_mode = codex_mode,
                permission_profile = record.permission_profile or "default",
                codex_session_captured_at = record.codex_session_captured_at,
                created_at = record.created_at,
                last_opened_at = record.last_opened_at,
                last_activity_at = record.last_activity_at,
                last_target_at = record.last_target_at,
                last_reconciled_at = record.last_reconciled_at,
                window_id = window_id,
                status = status,
              })
            end
          end
        end
      end
    end
  end

  for safe_name, record in pairs(self:instruction_file_records(root)) do
    if type(record) == "table" then
      local entry_safe_name = record.safe_name or safe_name
      if not seen[tostring(root) .. "\0" .. tostring(entry_safe_name)] then
        local window_name = M.workspace_window_name(entry_safe_name)
        local window_id = session and self:tmux_window_id(session, window_name) or nil
        local status = self:dashboard_workspace_status({ status = "inactive", codex_status = "idle" }, window_id)
        table.insert(entries, {
          name = record.name or entry_safe_name,
          safe_name = entry_safe_name,
          project_root = record.project_root or root,
          git_branch = "",
          window_name = window_name,
          tmux_target = M.tmux_target(session, window_name),
          codex_status = "idle",
          permission_profile = record.permission_profile or "default",
          codex_session_captured_at = record.codex_session_captured_at,
          created_at = record.created_at,
          last_opened_at = record.last_opened_at,
          last_activity_at = record.last_activity_at,
          last_target_at = record.last_target_at,
          window_id = window_id,
          status = status,
          instruction_file = record.instruction_file,
          instruction_file_only = true,
        })
      end
    end
  end

  table.sort(entries, function(left, right)
    return tostring(left.name):lower() < tostring(right.name):lower()
  end)

  return entries, nil
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
  local display_name, safe_name_or_error = M.sanitize_workspace_name(name)
  if not display_name then
    return nil, safe_name_or_error
  end

  local entries, error_message = self:entries_for_project(root)
  if error_message then
    return nil, error_message
  end

  for _, entry in ipairs(entries) do
    if entry.safe_name == safe_name_or_error or entry.name == name then
      return entry, nil
    end
  end

  return nil, "workspace not found"
end

function M:names_for_project(root)
  local entries, error_message = self:entries_for_project(root)
  if error_message then
    return {}
  end

  local names = {}
  for _, entry in ipairs(entries) do
    table.insert(names, entry.name or entry.safe_name)
  end
  table.sort(names, function(left, right)
    return tostring(left):lower() < tostring(right):lower()
  end)
  return names
end

function M:reconcile_project(root)
  local summary = {
    total = 0,
    active = 0,
    question = 0,
    idle = 0,
    inactive = 0,
    changed = 0,
  }

  local state_data, state_error = self:read_state()
  if state_error then
    return summary, state_error
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  if type(workspaces) ~= "table" then
    return summary, nil
  end

  local session = nil
  if vim.fn.executable(self:tmux_cmd()) == 1 then
    session = self:current_tmux_session()
  end

  local reconciled_at = self:timestamp()
  for safe_name, record in pairs(workspaces) do
    if type(record) == "table" then
      summary.total = summary.total + 1
      local window_name = record.tmux_window or record.window_name or safe_name
      local window_id = session and self:tmux_window_id(session, window_name) or nil
      local status = self:dashboard_workspace_status(record, window_id)
      if status == "active" then
        summary.active = summary.active + 1
      elseif status == "question" then
        summary.question = summary.question + 1
      elseif status == "idle" then
        summary.idle = summary.idle + 1
      else
        summary.inactive = summary.inactive + 1
      end

      local stale_activity = inactive_like_status(status)
        and (record.codex_status == "working" or record.codex_status == "question" or record.codex_mode ~= nil)
      if record.status ~= status or stale_activity then
        summary.changed = summary.changed + 1
      end
      record.status = status
      if inactive_like_status(status) then
        record.codex_status = "idle"
        record.codex_mode = nil
      end
      record.tmux_window = window_name
      record.tmux_target = M.tmux_target(session, window_name) or record.tmux_target
      record.last_reconciled_at = reconciled_at
    end
  end

  project.updated_at = reconciled_at
  local write_ok, write_error = self:write_state(state_data)
  if not write_ok then
    return summary, write_error
  end

  return summary, nil
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
  local worktree_renamed = false
  local branch_renamed = false
  local old_worktree_path = existing.worktree_path or existing.project_root or root
  local new_worktree_path = nil
  local old_branch = existing.worktree_branch
  local new_branch = nil
  if existing.workspace_kind == "worktree" then
    new_worktree_path = normalize_absolute_path(normalize_absolute_path(old_worktree_path, ".."), safe_name_or_error)
    new_branch = self:renamed_worktree_branch(existing, safe_name_or_error)
    if M.target_path_exists(new_worktree_path) then
      self.notify("worktree path already exists", vim.log.levels.ERROR)
      return false
    end
    if old_branch ~= new_branch and self:git_branch_exists(root, new_branch) then
      self.notify("branch already exists: " .. new_branch, vim.log.levels.ERROR)
      return false
    end
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
    if type(existing.target_path) == "string" and starts_with_path(existing.target_path, old_worktree_path) then
      existing.target_path = normalize_absolute_path(new_worktree_path, existing.target_path:sub(#strip_trailing_slashes(old_worktree_path) + 2))
    end
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
    self.notify(write_error, vim.log.levels.ERROR)
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
    if entry.window_id and not self:kill_tmux_window(entry.window_id) then
      self.notify("Failed to close tmux window " .. tostring(entry.window_name), vim.log.levels.ERROR)
      return false
    end

    local delete_instruction_ok, delete_instruction_error = self:delete_instruction_file(root, entry.safe_name)
    if not delete_instruction_ok then
      self.notify(delete_instruction_error, vim.log.levels.ERROR)
      self.render_workspace_manager()
      return false
    end

    if not self:remove_git_worktree(root, worktree_path) then
      self.notify("Failed to remove Git worktree " .. tostring(worktree_path), vim.log.levels.ERROR)
      self.render_workspace_manager()
      return false
    end
    if type(worktree_branch) == "string" and worktree_branch ~= "" and not self:delete_git_branch(root, worktree_branch) then
      self.notify("Failed to delete Git branch " .. tostring(worktree_branch), vim.log.levels.ERROR)
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
      self.notify(write_error, vim.log.levels.ERROR)
      return false
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

function M:shell_env_assignment(name, value)
  return name .. "=" .. vim.fn.shellescape(tostring(value or ""))
end

function M:lua_string(value)
  return string.format("%q", tostring(value or ""))
end

function M:bootstrap_lua(workspace)
  local root = workspace.project_root or "."
  local target_path = workspace.target_path or ""
  local target_type = workspace.target_type or ""
  local profile = workspace.permission_profile or "default"
  local name = workspace.name or workspace.safe_name or ""
  local safe_name = workspace.safe_name or ""
  local branch = workspace.git_branch or ""
  local workspace_kind = workspace.workspace_kind or ""
  local git_common_dir = workspace.git_common_dir or ""
  local worktree_path = workspace.worktree_path or ""
  local worktree_branch = workspace.worktree_branch or ""
  local worktree_base = workspace.worktree_base or ""
  local window_name = workspace.window_name or ""
  local custom_instruction = workspace.custom_instruction or ""
  local resolved_instruction = workspace.resolved_instruction or ""
  local initial_prompt = workspace.initial_prompt or ""
  local open_visible = workspace.open_visible == true
  local codex_session_id = workspace.codex_session_id or ""
  local codex_session_path = workspace.codex_session_path or ""
  local codex_session_captured_at = workspace.codex_session_captured_at or ""
  local codex_status = initial_prompt ~= "" and "working" or "idle"
  local status = initial_prompt ~= "" and "active" or "idle"
  local show_codux = open_visible or initial_prompt ~= ""

  return table.concat({
    "local root=" .. self:lua_string(root),
    "local target=" .. self:lua_string(target_path),
    "local target_type=" .. self:lua_string(target_type),
    "local profile=" .. self:lua_string(profile),
    "local prompt=" .. self:lua_string(initial_prompt),
    "local show_codux=" .. tostring(show_codux),
    "local workspace={name=" .. self:lua_string(name) .. ",safe_name=" .. self:lua_string(safe_name) .. ",project_root=root,target_path=target,target_type=target_type,git_branch=" .. self:lua_string(branch) .. ",workspace_kind=" .. self:lua_string(workspace_kind) .. ",git_common_dir=" .. self:lua_string(git_common_dir) .. ",worktree_path=" .. self:lua_string(worktree_path) .. ",worktree_branch=" .. self:lua_string(worktree_branch) .. ",worktree_base=" .. self:lua_string(worktree_base) .. ",window_name=" .. self:lua_string(window_name) .. ",custom_instruction=" .. self:lua_string(custom_instruction) .. ",resolved_instruction=" .. self:lua_string(resolved_instruction) .. ",permission_profile=profile,codex_status=" .. self:lua_string(codex_status) .. ",status=" .. self:lua_string(status) .. ",codex_session_id=" .. self:lua_string(codex_session_id) .. ",codex_session_path=" .. self:lua_string(codex_session_path) .. ",codex_session_captured_at=" .. self:lua_string(codex_session_captured_at) .. ",open_visible=" .. tostring(open_visible) .. "}",
    "vim.defer_fn(function()",
    "pcall(vim.cmd,'cd '..vim.fn.fnameescape(root))",
    "local target_win=vim.api.nvim_get_current_win()",
    "if vim.fn.exists(':Neotree')==2 then",
    "local tree_dir=(target_type=='directory' and target~='' and target) or root",
    "local cmd='Neotree source=filesystem action=show position=left dir='..vim.fn.fnameescape(tree_dir)",
    "if target~='' and target_type~='directory' then cmd=cmd..' reveal_file='..vim.fn.fnameescape(target)..' reveal_force_cwd' end",
    "pcall(vim.cmd,cmd)",
    "end",
    "if target~='' and target_type~='directory' then if vim.api.nvim_win_is_valid(target_win) then pcall(vim.api.nvim_set_current_win,target_win) else pcall(vim.cmd,'edit '..vim.fn.fnameescape(target)) end end",
    "local ok_attach,codux_attach=pcall(require,'codux')",
    "if ok_attach and type(codux_attach.attach_workspace)=='function' then codux_attach.attach_workspace(workspace) end",
    "vim.defer_fn(function()",
    "local ok,codux=pcall(require,'codux')",
    "if ok and type(codux.open_workspace_session)=='function' then codux.open_workspace_session(workspace,prompt,{visible=show_codux}) end",
    "end,300)",
    "end,300)",
  }, " ")
end

function M:nvim_command(workspace)
  local config = self.get_config()
  local env = {
    self:shell_env_assignment("CODEX_CMD", self.command_util.shell(config.codex_cmd)),
    self:shell_env_assignment("CODEX_WORKSPACE_AUTO_CMD", self.command_util.shell(config.workspace_auto_cmd)),
    self:shell_env_assignment("CODEX_DANGER_FULL_ACCESS_CMD", self.command_util.shell(config.danger_full_access_cmd)),
  }
  local nvim_target = "."
  if workspace.target_type ~= "directory" and type(workspace.target_path) == "string" and workspace.target_path ~= "" then
    nvim_target = workspace.target_path
  end

  local parts = {
    "cd",
    vim.fn.shellescape(workspace.project_root or "."),
    "&&",
    "env",
    table.concat(env, " "),
    vim.fn.shellescape(self:nvim_cmd()),
    vim.fn.shellescape(nvim_target),
    "-c",
    vim.fn.shellescape("lua " .. self:bootstrap_lua(workspace)),
  }

  return table.concat(parts, " ")
end

function M:ensure_tmux_window(session, root, window_name, command)
  local existing = self:tmux_window_id(session, window_name)
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
  opts = opts or {}
  if not self:workspaces_enabled() then
    return nil, "Codux workspaces are disabled"
  end

  if vim.fn.executable(self:tmux_cmd()) ~= 1 then
    return nil, "tmux not found on PATH"
  end

  local display_name, safe_name_or_error = M.sanitize_workspace_name(name)
  if not display_name then
    return nil, safe_name_or_error
  end

  local session = self:current_tmux_session()
  if not session then
    return nil, "no tmux session running"
  end

  local context = self:target_context()
  local base_root = context.root
  local root = opts.project_root or base_root
  local creating_worktree = not opts.allow_existing and not opts.require_existing
  local created_worktree_path = nil
  local created_worktree_branch = nil
  local worktree_base = nil
  local git_common_dir = nil

  if creating_worktree then
    local clean, clean_error = self:git_checkout_clean(base_root)
    if not clean then
      return nil, clean_error
    end

    local branch_error = nil
    created_worktree_branch, branch_error = self:resolve_worktree_branch(base_root, safe_name_or_error)
    if not created_worktree_branch then
      return nil, branch_error
    end
    created_worktree_path = self:worktree_path(base_root, safe_name_or_error)
    worktree_base = self:git_current_ref(base_root)
    git_common_dir = self:git_common_dir(base_root)
    if not git_common_dir then
      return nil, "not inside a Git repository"
    end
    if M.target_path_exists(created_worktree_path) then
      return nil, "worktree path already exists"
    end
    local worktree_ok, worktree_error =
      self:create_git_worktree(base_root, created_worktree_path, created_worktree_branch, worktree_base)
    if not worktree_ok then
      return nil, worktree_error
    end

    root = created_worktree_path
  end

  self:warn_workspace_instruction_ignore(root)
  local custom_instruction = type(opts.custom_instruction) == "string" and trim(opts.custom_instruction) or nil
  if custom_instruction == "" then
    custom_instruction = nil
  end
  local resolved_instruction = type(opts.resolved_instruction) == "string" and trim(opts.resolved_instruction) or nil
  if resolved_instruction == "" then
    resolved_instruction = nil
  end

  local state_data, state_error = self:read_state()
  if state_error then
    self.notify(state_error .. "; starting with empty workspace state", vim.log.levels.WARN)
  end

  local project = self:project_state(state_data, root)
  local existing = project.workspaces[safe_name_or_error]
  local file_instruction = self:read_instruction_file(root, safe_name_or_error)
  if type(existing) == "table" and not opts.allow_existing then
    if creating_worktree then
      self:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
    end
    return nil, "workspace already exists"
  end
  if type(existing) == "table" and existing.name ~= display_name and not opts.allow_existing then
    if creating_worktree then
      self:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
    end
    return nil, "workspace already exists"
  end
  if type(existing) ~= "table" and file_instruction and not opts.allow_existing then
    if creating_worktree then
      self:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
    end
    return nil, "workspace already exists"
  end
  if opts.require_existing and type(existing) ~= "table" and not file_instruction then
    return nil, "workspace not found"
  end

  local fallback_target_path = context.path
  local fallback_target_type = context.target and context.target.type or nil
  if creating_worktree then
    fallback_target_path, fallback_target_type =
      self:target_in_worktree(context.path, fallback_target_type, base_root, root)
  end

  local fallback = {
    name = display_name,
    safe_name = safe_name_or_error,
    project_root = root,
    target_path = fallback_target_path,
    target_type = fallback_target_type,
    git_branch = creating_worktree and created_worktree_branch or context.branch,
    workspace_kind = creating_worktree and "worktree" or nil,
    git_common_dir = git_common_dir,
    worktree_path = created_worktree_path,
    worktree_branch = created_worktree_branch,
    worktree_base = worktree_base,
    window_name = M.workspace_window_name(safe_name_or_error),
    custom_instruction = custom_instruction,
    resolved_instruction = resolved_instruction,
    permission_profile = self:permission_profile(),
    codex_status = "idle",
    status = "idle",
  }
  local workspace = self:workspace_from_state(existing, fallback)
  workspace.project_root = workspace.project_root or root
  workspace.target_path, workspace.target_type =
    M.normalize_workspace_target(workspace.target_path, workspace.target_type, workspace.project_root)
  if custom_instruction then
    workspace.custom_instruction = custom_instruction
  end
  workspace.session = session
  workspace.safe_name = workspace.safe_name or safe_name_or_error
  workspace.window_name = M.workspace_window_name(workspace.safe_name)
  workspace.tmux_target = M.tmux_target(session, workspace.window_name)
  local saved_workspace = type(existing) == "table" or (opts.require_existing and file_instruction ~= nil)
  workspace.open_visible = not saved_workspace

  if not resolved_instruction and file_instruction then
    resolved_instruction = file_instruction
  end
  if not resolved_instruction and type(workspace.resolved_instruction) == "string" and trim(workspace.resolved_instruction) ~= "" then
    resolved_instruction = workspace.resolved_instruction
  end
  if resolved_instruction then
    workspace.resolved_instruction = resolved_instruction
  end
  if saved_workspace then
    self:resolve_workspace_resume_session(workspace)
  end

  local window_id, created =
    self:ensure_tmux_window(session, workspace.project_root, workspace.window_name, self:nvim_command(workspace))
  if not window_id then
    if creating_worktree then
      self:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
    end
    return nil, "Failed to create tmux window " .. workspace.window_name
  end

  local wrote_new_instruction_file = file_instruction == nil
    and type(workspace.resolved_instruction) == "string"
    and trim(workspace.resolved_instruction) ~= ""
  local instruction_ok, instruction_error =
    self:write_instruction_file(workspace.project_root, workspace.safe_name, workspace.resolved_instruction)
  if not instruction_ok then
    if created then
      self:kill_tmux_window(window_id)
    end
    if creating_worktree then
      self:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
    end
    return nil, instruction_error
  end

  workspace.window_id = window_id
  if created and not workspace.initial_prompt then
    workspace.codex_status = "idle"
  end
  workspace.status = self:dashboard_workspace_status(workspace, window_id)
  if created and workspace.initial_prompt then
    workspace.status = "active"
    workspace.codex_status = "working"
  elseif workspace.status ~= "active" then
    if workspace.status == "question" then
      workspace.codex_status = "question"
    else
      workspace.codex_status = "idle"
    end
  end
  if inactive_like_status(workspace.status) then
    workspace.codex_mode = nil
  end
  workspace.initial_prompt = nil
  project.workspaces[workspace.safe_name] = self:state_record(workspace, existing)
  project.updated_at = self:timestamp()

  local write_ok, write_error = self:write_state(state_data)
  if not write_ok then
    if created then
      self:kill_tmux_window(window_id)
    end
    if wrote_new_instruction_file then
      self:delete_instruction_file(workspace.project_root, workspace.safe_name)
    end
    if creating_worktree then
      self:cleanup_created_worktree(base_root, created_worktree_path, created_worktree_branch)
    end
    return nil, write_error
  end

  return workspace, nil
end

function M:create_workspace(name, opts)
  opts = opts or {}
  local workspace, error_message = self:prepare_workspace(name, {
    custom_instruction = opts.custom_instruction,
    resolved_instruction = opts.resolved_instruction,
  })
  if not workspace then
    self.notify(error_message or "Failed to prepare Codux workspace", vim.log.levels.ERROR)
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

function M:open_saved_workspace(name, project_root)
  local workspace, error_message = self:prepare_workspace(name, {
    allow_existing = true,
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
  if type(self.state.workspace) ~= "table" or type(self.state.workspace.safe_name) ~= "string" then
    return false
  end

  local filetype = current_filetype()
  if
    filetype == "codux"
    or filetype == "codux-workspaces"
    or filetype == "codux-workspaces-footer"
    or filetype == "codux-workspace-create"
    or filetype == "codux-workspace-create-footer"
    or filetype == "codux-workspace-instruction"
  then
    return false
  end

  if event == "CursorMoved" and not self.is_explorer_filetype(filetype) then
    return false
  end

  return true
end

function M:sync_target(event, current_filetype)
  if not self:target_sync_allowed(event, current_filetype) then
    return false
  end

  local workspace = self.state.workspace
  local root = workspace.project_root
  local safe_name = workspace.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false
  end

  local context = self:target_context()
  local path = context.path
  if type(path) ~= "string" or path == "" or path:match("^term://") or path:match("^codux://") then
    return false
  end

  local target_type = context.target and context.target.type or (vim.fn.isdirectory(path) == 1 and "directory" or "file")
  local branch = context.branch or ""
  path, target_type = M.normalize_workspace_target(path, target_type, root)
  local signature = M.workspace_target_signature(path, target_type, branch)
  if signature == self.state.workspace_target_signature then
    return true
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

  record.target_path = path
  record.target_type = target_type
  record.git_branch = branch
  record.last_target_at = self:timestamp()
  project.updated_at = record.last_target_at

  local write_ok = self:write_state(state_data)
  if not write_ok then
    return false
  end

  workspace.target_path = path
  workspace.target_type = target_type
  workspace.git_branch = branch
  self.state.workspace_target_signature = signature

  if self.state.workspace_manager_project_root == root then
    self.render_workspace_manager()
  end

  return true
end

function M:schedule_target_sync(event, sync_fn)
  if self.state.workspace_target_update_pending then
    return
  end

  self.state.workspace_target_update_pending = true
  vim.defer_fn(function()
    self.state.workspace_target_update_pending = false
    sync_fn(event)
  end, 150)
end

function M:attach_workspace(workspace, schedule_sync)
  if type(workspace) ~= "table" then
    return false
  end

  local attached = self:workspace_from_state(workspace, workspace)
  if type(attached.safe_name) ~= "string" or attached.safe_name == "" then
    return false
  end
  if type(attached.project_root) ~= "string" or attached.project_root == "" then
    return false
  end

  self.state.workspace = attached
  self.state.workspace_target_signature =
    M.workspace_target_signature(attached.target_path, attached.target_type, attached.git_branch)
  schedule_sync("attach")
  return true
end

return M
