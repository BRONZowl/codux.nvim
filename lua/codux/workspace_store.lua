local Store = {}
Store.__index = Store

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function empty_dict()
  return vim.empty_dict and vim.empty_dict() or {}
end

local function default_json_encode(value)
  if vim.json and type(vim.json.encode) == "function" then
    return vim.json.encode(value)
  end

  return vim.fn.json_encode(value)
end

local function default_json_decode(value)
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

local function default_workspace_window_name(safe_name)
  return tostring(safe_name or "")
end

function Store:workspace_config()
  if type(self.get_workspace_config) == "function" then
    local value = self.get_workspace_config()
    if type(value) == "table" then
      return value
    end
  end

  return {}
end

function Store:state_file()
  local value = self:workspace_config().state_file
  if type(value) == "string" and trim(value) ~= "" then
    return vim.fn.expand(value)
  end

  return vim.fn.stdpath("data") .. "/codux/workspaces.json"
end

function Store:instruction_files_config()
  local workspaces = self:workspace_config()
  if workspaces.enabled == false then
    return { enabled = false }
  end

  local value = workspaces.instruction_files
  if value == false then
    return { enabled = false }
  end
  if type(value) ~= "table" then
    value = self.default_instruction_files
  end

  local directory = type(value.directory) == "string" and trim(value.directory) or ""
  if directory == "" then
    directory = self.default_instruction_files.directory
  end

  return {
    enabled = value.enabled ~= false,
    directory = directory,
  }
end

function Store:instruction_directory(root)
  local file_config = self:instruction_files_config()
  if file_config.enabled == false then
    return nil
  end
  if type(root) ~= "string" or root == "" then
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

function Store:instruction_file_path(root, safe_name)
  local directory = self:instruction_directory(root)
  if not directory or type(safe_name) ~= "string" or trim(safe_name) == "" then
    return nil
  end

  return directory .. "/" .. safe_name .. ".md"
end

function Store:read_instruction_file(root, safe_name)
  local path = self:instruction_file_path(root, safe_name)
  if not path or vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end

  local instruction = trim(table.concat(lines, "\n"))
  if instruction == "" then
    return nil
  end

  return instruction
end

function Store:write_instruction_file(root, safe_name, instruction)
  instruction = type(instruction) == "string" and trim(instruction) or ""
  if instruction == "" then
    return true, nil
  end

  local path = self:instruction_file_path(root, safe_name)
  if not path then
    return true, nil
  end

  local directory = vim.fn.fnamemodify(path, ":h")
  if directory ~= "" then
    local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, directory, "p")
    if not mkdir_ok or mkdir_result ~= 1 then
      return false, "Failed to create Codux workspace instruction directory"
    end
  end

  local lines = vim.split(instruction, "\n", { plain = true })
  local ok, result = pcall(vim.fn.writefile, lines, path)
  if not ok or result ~= 0 then
    return false, "Failed to write Codux workspace instruction file"
  end

  return true, nil
end

function Store:delete_instruction_file(root, safe_name)
  local path = self:instruction_file_path(root, safe_name)
  if not path or vim.fn.filereadable(path) ~= 1 then
    return true, nil
  end

  local ok, result = pcall(vim.fn.delete, path)
  if not ok or result ~= 0 then
    return false, "Failed to delete Codux workspace instruction file"
  end

  return true, nil
end

function Store:instruction_file_records(root)
  local directory = self:instruction_directory(root)
  if not directory or vim.fn.isdirectory(directory) ~= 1 then
    return {}
  end

  local ok, files = pcall(vim.fn.globpath, directory, "*.md", false, true)
  if not ok or type(files) ~= "table" then
    return {}
  end

  local records = {}
  for _, path in ipairs(files) do
    local safe_name = vim.fn.fnamemodify(path, ":t:r")
    local display_name, sanitized_name = self.sanitize_workspace_name(safe_name)
    if type(safe_name) == "string" and display_name and sanitized_name == safe_name then
      local instruction = self:read_instruction_file(root, safe_name)
      if instruction then
        records[safe_name] = {
          name = display_name,
          safe_name = safe_name,
          project_root = root,
          resolved_instruction = instruction,
          status = "inactive",
          codex_status = "idle",
          instruction_file = path,
          instruction_file_only = true,
        }
      end
    end
  end

  return records
end

function Store:empty_state()
  return {
    version = 2,
    projects = empty_dict(),
  }
end

function Store.normalize_session_id(value)
  if type(value) ~= "string" then
    return nil
  end

  value = trim(value)
  if value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
    return value
  end

  return nil
end

function Store.normalize_codex_mode(value)
  if value == "execute" or value == "plan" then
    return value
  end

  return nil
end

local function inactive_like_status(status)
  return status == "inactive" or status == "missing"
end

function Store:normalize_record(record, safe_name, root)
  if type(record) ~= "table" then
    return nil
  end

  safe_name = type(record.safe_name) == "string" and record.safe_name ~= "" and record.safe_name or safe_name
  local name = type(record.name) == "string" and record.name ~= "" and record.name or safe_name
  local project_root = type(record.project_root) == "string" and record.project_root ~= "" and record.project_root or root
  local window_name = self.workspace_window_name(safe_name)
  local status = record.status
  if status ~= "active" and status ~= "question" and status ~= "idle" and status ~= "inactive" and status ~= "missing" then
    status = "inactive"
  end
  local codex_status = record.codex_status == "working" and "working"
    or record.codex_status == "question" and "question"
    or "idle"
  local codex_mode = not inactive_like_status(status) and Store.normalize_codex_mode(record.codex_mode) or nil

  return {
    name = name,
    safe_name = safe_name,
    project_root = project_root,
    target_path = record.target_path,
    target_type = record.target_type,
    git_branch = record.git_branch or "",
    workspace_kind = record.workspace_kind,
    git_common_dir = record.git_common_dir,
    worktree_path = record.worktree_path,
    worktree_branch = record.worktree_branch,
    worktree_base = record.worktree_base,
    worktree_base_commit = record.worktree_base_commit,
    mission_id = record.mission_id,
    mission_name = record.mission_name,
    mission_role = record.mission_role,
    mission_objective = record.mission_objective,
    tmux_window = window_name,
    tmux_target = record.tmux_target,
    custom_instruction = record.custom_instruction,
    resolved_instruction = record.resolved_instruction,
    permission_profile = record.permission_profile or "default",
    codex_session_id = Store.normalize_session_id(record.codex_session_id),
    codex_session_path = record.codex_session_path,
    codex_session_captured_at = record.codex_session_captured_at,
    status = status,
    codex_status = codex_status,
    codex_mode = codex_mode,
    created_at = record.created_at,
    last_opened_at = record.last_opened_at,
    last_activity_at = record.last_activity_at,
    last_target_at = record.last_target_at,
    last_reconciled_at = record.last_reconciled_at,
  }
end

function Store:normalize_state(state_data)
  if type(state_data) ~= "table" then
    return self:empty_state()
  end

  if type(state_data.projects) ~= "table" and type(state_data.workspaces) == "table" then
    local migrated = self:empty_state()
    for safe_name, record in pairs(state_data.workspaces) do
      if type(record) == "table" and type(record.project_root) == "string" and record.project_root ~= "" then
        local project = migrated.projects[record.project_root]
        if type(project) ~= "table" then
          project = {
            project_root = record.project_root,
            workspaces = empty_dict(),
          }
          migrated.projects[record.project_root] = project
        end
        project.workspaces[safe_name] = self:normalize_record(record, safe_name, record.project_root)
      end
    end
    return migrated
  end

  state_data.version = 2
  state_data.templates = nil
  state_data.hidden_templates = nil

  if type(state_data.projects) ~= "table" then
    state_data.projects = empty_dict()
  end

  for root, project in pairs(state_data.projects) do
    if type(project) == "table" then
      project.project_root = type(project.project_root) == "string" and project.project_root ~= "" and project.project_root or root
      if type(project.workspaces) ~= "table" then
        project.workspaces = empty_dict()
      else
        for safe_name, record in pairs(project.workspaces) do
          project.workspaces[safe_name] = self:normalize_record(record, safe_name, project.project_root)
        end
      end
    else
      state_data.projects[root] = {
        project_root = root,
        workspaces = empty_dict(),
      }
    end
  end

  return state_data
end

function Store:read_state()
  local path = self:state_file()
  if vim.fn.filereadable(path) ~= 1 then
    return self:empty_state(), nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return self:empty_state(), "Failed to read Codux workspace state"
  end

  local decoded = self.json_decode(table.concat(lines, "\n"))
  if type(decoded) ~= "table" then
    return self:empty_state(), "Failed to parse Codux workspace state"
  end

  return self:normalize_state(decoded), nil
end

function Store:write_state(state_data)
  local path = self:state_file()
  local directory = vim.fn.fnamemodify(path, ":h")
  if directory ~= "" then
    local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, directory, "p")
    if not mkdir_ok or mkdir_result ~= 1 then
      return false, "Failed to create Codux workspace state directory"
    end
  end

  local encoded = self.json_encode(self:normalize_state(state_data))
  local ok, result = pcall(vim.fn.writefile, { encoded }, path)
  if not ok or result ~= 0 then
    return false, "Failed to write Codux workspace state"
  end

  return true, nil
end

function Store.timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function Store:project_state(state_data, root)
  state_data.projects[root] = type(state_data.projects[root]) == "table" and state_data.projects[root] or empty_dict()
  local project = state_data.projects[root]
  project.project_root = root
  project.workspaces = type(project.workspaces) == "table" and project.workspaces or empty_dict()
  return project
end

function Store.workspace_from_state(record, fallback)
  record = type(record) == "table" and record or {}
  fallback = type(fallback) == "table" and fallback or {}
  local status = record.status or fallback.status or "inactive"
  local codex_mode = not inactive_like_status(status)
      and (Store.normalize_codex_mode(record.codex_mode) or Store.normalize_codex_mode(fallback.codex_mode))
    or nil

  return {
    name = record.name or fallback.name,
    safe_name = record.safe_name or fallback.safe_name,
    project_root = record.project_root or fallback.project_root,
    target_path = record.target_path or fallback.target_path,
    target_type = record.target_type or fallback.target_type,
    git_branch = record.git_branch or fallback.git_branch or "",
    workspace_kind = record.workspace_kind or fallback.workspace_kind,
    git_common_dir = record.git_common_dir or fallback.git_common_dir,
    worktree_path = record.worktree_path or fallback.worktree_path,
    worktree_branch = record.worktree_branch or fallback.worktree_branch,
    worktree_base = record.worktree_base or fallback.worktree_base,
    worktree_base_commit = record.worktree_base_commit or fallback.worktree_base_commit,
    mission_id = record.mission_id or fallback.mission_id,
    mission_name = record.mission_name or fallback.mission_name,
    mission_role = record.mission_role or fallback.mission_role,
    mission_objective = record.mission_objective or fallback.mission_objective,
    window_name = record.tmux_window or record.window_name or fallback.window_name,
    tmux_target = record.tmux_target or fallback.tmux_target,
    nvim_server = record.nvim_server or fallback.nvim_server,
    custom_instruction = record.custom_instruction or fallback.custom_instruction,
    resolved_instruction = record.resolved_instruction or fallback.resolved_instruction,
    initial_mode = record.initial_mode or fallback.initial_mode,
    permission_profile = record.permission_profile or fallback.permission_profile or "default",
    codex_session_id = Store.normalize_session_id(record.codex_session_id) or Store.normalize_session_id(fallback.codex_session_id),
    codex_session_path = record.codex_session_path or fallback.codex_session_path,
    codex_session_captured_at = record.codex_session_captured_at or fallback.codex_session_captured_at,
    codex_status = record.codex_status or fallback.codex_status or "idle",
    status = status,
    codex_mode = codex_mode,
    created_at = record.created_at or fallback.created_at,
  }
end

function Store:state_record(workspace, existing)
  existing = type(existing) == "table" and existing or {}
  local now = Store.timestamp()
  local status = workspace.status or existing.status or "idle"
  local codex_mode = nil
  if not inactive_like_status(status) then
    codex_mode = Store.normalize_codex_mode(workspace.codex_mode) or Store.normalize_codex_mode(existing.codex_mode)
  end

  return {
    name = workspace.name,
    safe_name = workspace.safe_name,
    project_root = workspace.project_root,
    target_path = workspace.target_path,
    target_type = workspace.target_type,
    git_branch = workspace.git_branch or "",
    workspace_kind = workspace.workspace_kind,
    git_common_dir = workspace.git_common_dir,
    worktree_path = workspace.worktree_path,
    worktree_branch = workspace.worktree_branch,
    worktree_base = workspace.worktree_base,
    worktree_base_commit = workspace.worktree_base_commit,
    mission_id = workspace.mission_id,
    mission_name = workspace.mission_name,
    mission_role = workspace.mission_role,
    mission_objective = workspace.mission_objective,
    tmux_window = workspace.window_name,
    tmux_target = workspace.tmux_target,
    nvim_server = workspace.nvim_server or existing.nvim_server,
    custom_instruction = workspace.custom_instruction,
    resolved_instruction = workspace.resolved_instruction,
    initial_mode = workspace.initial_mode or existing.initial_mode,
    permission_profile = workspace.permission_profile or "default",
    codex_session_id = Store.normalize_session_id(workspace.codex_session_id),
    codex_session_path = workspace.codex_session_path,
    codex_session_captured_at = workspace.codex_session_captured_at,
    status = status,
    codex_status = workspace.codex_status or existing.codex_status or "idle",
    codex_mode = codex_mode,
    created_at = existing.created_at or workspace.created_at or now,
    last_opened_at = now,
    last_reconciled_at = existing.last_reconciled_at,
  }
end

function Store.codex_home()
  local value = vim.env.CODEX_HOME
  if type(value) == "string" and trim(value) ~= "" then
    return vim.fn.expand(value)
  end

  return vim.fn.expand("~/.codex")
end

function Store:codex_session_files()
  local root = self:codex_home() .. "/sessions"
  if vim.fn.isdirectory(root) ~= 1 then
    return {}
  end

  local ok, files = pcall(vim.fn.globpath, root, "**/*.jsonl", false, true)
  if not ok or type(files) ~= "table" then
    return {}
  end

  return files
end

function Store:read_codex_session_meta(path)
  if type(path) ~= "string" or path == "" or vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path, "", 1)
  if not ok or type(lines) ~= "table" or type(lines[1]) ~= "string" then
    return nil
  end

  local decoded = self.json_decode(lines[1])
  if type(decoded) ~= "table" or decoded.type ~= "session_meta" or type(decoded.payload) ~= "table" then
    return nil
  end

  local payload = decoded.payload
  local session_id = Store.normalize_session_id(payload.session_id) or Store.normalize_session_id(payload.id)
  if not session_id then
    return nil
  end

  return {
    session_id = session_id,
    cwd = payload.cwd,
    timestamp = payload.timestamp,
    path = path,
    mtime = tonumber(vim.fn.getftime(path)) or 0,
  }
end

function Store:codex_session_for_id(session_id)
  session_id = Store.normalize_session_id(session_id)
  if not session_id then
    return nil
  end

  for _, path in ipairs(self:codex_session_files()) do
    local meta = self:read_codex_session_meta(path)
    if meta and meta.session_id == session_id then
      return meta
    end
  end

  return nil
end

function Store:latest_codex_session_for_cwd(cwd, min_mtime)
  if type(cwd) ~= "string" or cwd == "" then
    return nil
  end

  min_mtime = tonumber(min_mtime) or 0
  local latest = nil
  for _, path in ipairs(self:codex_session_files()) do
    local meta = self:read_codex_session_meta(path)
    if meta and meta.cwd == cwd and meta.mtime >= min_mtime and (not latest or meta.mtime > latest.mtime) then
      latest = meta
    end
  end

  return latest
end

function Store.apply_codex_session_meta(workspace, meta)
  if type(workspace) ~= "table" or type(meta) ~= "table" then
    return false
  end

  local session_id = Store.normalize_session_id(meta.session_id)
  if not session_id then
    return false
  end

  workspace.codex_session_id = session_id
  workspace.codex_session_path = meta.path
  workspace.codex_session_captured_at = Store.timestamp()
  return true
end

function Store:resolve_workspace_resume_session(workspace)
  if type(workspace) ~= "table" then
    return nil
  end

  local session_id = Store.normalize_session_id(workspace.codex_session_id)
  if session_id then
    local meta = self:codex_session_for_id(session_id)
    if meta and meta.cwd == workspace.project_root then
      Store.apply_codex_session_meta(workspace, meta)
      return meta
    end
    workspace.codex_session_id = nil
    workspace.codex_session_path = nil
    workspace.codex_session_captured_at = nil
  end

  local meta = self:latest_codex_session_for_cwd(workspace.project_root)
  if meta then
    Store.apply_codex_session_meta(workspace, meta)
    return meta
  end

  return nil
end

local M = {}

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local store = {
    get_workspace_config = opts.get_workspace_config,
    default_instruction_files = type(opts.default_instruction_files) == "table" and opts.default_instruction_files
      or { enabled = true, directory = ".agents/codux" },
    json_encode = type(opts.json_encode) == "function" and opts.json_encode or default_json_encode,
    json_decode = type(opts.json_decode) == "function" and opts.json_decode or default_json_decode,
    sanitize_workspace_name = type(opts.sanitize_workspace_name) == "function" and opts.sanitize_workspace_name
      or function(name)
        return trim(name), trim(name)
      end,
    workspace_window_name = type(opts.workspace_window_name) == "function" and opts.workspace_window_name
      or default_workspace_window_name,
  }

  return setmetatable(store, Store)
end

return M
