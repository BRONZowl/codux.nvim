local M = {}
local command_util = require("codux.command")
local providers = require("codux.providers")

-- Lua patterns do not support `|` alternation; check each fragment separately.
local SECRET_KEY_PATTERNS = {
  "api[_%-]?key",
  "access[_%-]?token",
  "refresh[_%-]?token",
  "auth[_%-]?token",
  "oauth[_%-]?token",
  "client[_%-]?secret",
  "private[_%-]?key",
  "password",
  "passwd",
  "secret",
  "authorization",
  "bearer",
}

local function is_secret_key(key)
  if type(key) ~= "string" then
    return false
  end
  local normalized = key:lower():gsub("%s+", "")
  for _, pattern in ipairs(SECRET_KEY_PATTERNS) do
    if normalized:match(pattern) then
      return true
    end
  end
  return false
end

local function is_command_key(key)
  if type(key) ~= "string" then
    return false
  end
  return key == "codex_cmd"
    or key == "tmux_cmd"
    or key:match("_cmd$") ~= nil
    or key:match("_command$") ~= nil
end

local function redact_command_value(value)
  local executable = command_util.executable(value)
  if type(executable) == "string" and executable ~= "" then
    return executable
  end
  if value == nil then
    return nil
  end
  return "[redacted]"
end

--- Return a copy of plugin config safe for health/debug surfaces.
--- Strips secret-like keys and reduces command fields to executable names only.
function M.public_config(config)
  if type(config) ~= "table" then
    return {}
  end

  local function walk(value, key)
    if is_secret_key(key) then
      return nil, true
    end

    if is_command_key(key) then
      return redact_command_value(value), false
    end

    if type(value) ~= "table" then
      return value, false
    end

    local out = {}
    for child_key, child_value in pairs(value) do
      local redacted, drop = walk(child_value, child_key)
      if not drop then
        out[child_key] = redacted
      end
    end
    return out, false
  end

  local redacted = walk(config, nil)
  return type(redacted) == "table" and redacted or {}
end

local function health_start(name)
  if vim.health.start then
    vim.health.start(name)
  else
    vim.health.report_start(name)
  end
end

local function health_ok(message)
  if vim.health.ok then
    vim.health.ok(message)
  else
    vim.health.report_ok(message)
  end
end

local function health_warn(message)
  if vim.health.warn then
    vim.health.warn(message)
  else
    vim.health.report_warn(message)
  end
end

local function health_error(message)
  if vim.health.error then
    vim.health.error(message)
  else
    vim.health.report_error(message)
  end
end

local function executable(name)
  return vim.fn.executable(name) == 1
end

local function writable_existing_ancestor(path)
  local current = vim.fn.fnamemodify(path, ":h")
  local previous = nil
  while type(current) == "string" and current ~= "" and current ~= previous do
    if vim.fn.isdirectory(current) == 1 then
      if vim.fn.filewritable(current) == 2 then
        return current
      end
      return nil
    end
    previous = current
    current = vim.fn.fnamemodify(current, ":h")
  end
  return nil
end

function M.doctor_lines(deps)
  deps = type(deps) == "table" and deps or {}
  local lines = { "codux.nvim doctor", "" }
  local function add(status, message)
    table.insert(lines, status .. " " .. message)
  end

  local tmux = type(deps.tmux_cmd) == "function" and deps.tmux_cmd() or "tmux"
  if vim.fn.executable(tmux) == 1 then
    add("[ok]", "tmux found: " .. tmux)
  else
    add("[warn]", "tmux not found: " .. tmux)
  end

  local session = type(deps.current_tmux_session) == "function" and deps.current_tmux_session() or nil
  if session then
    add("[ok]", "tmux server reachable: " .. session)
  else
    add("[warn]", "tmux server not reachable or Neovim is outside tmux")
  end

  local config = type(deps.config) == "table" and deps.config or {}
  for _, provider in ipairs({ "codex", "grok" }) do
    local executable_name = providers.executable(config, provider, "default") or provider
    if vim.fn.executable(executable_name) == 1 then
      add("[ok]", provider .. " found: " .. executable_name)
    else
      add("[warn]", provider .. " command not found: " .. tostring(executable_name))
    end
  end

  local state_file = type(deps.workspace_state_file) == "function" and deps.workspace_state_file() or nil
  if type(state_file) == "string" and state_file ~= "" then
    local state_dir = vim.fn.fnamemodify(state_file, ":h")
    if vim.fn.filereadable(state_file) == 1 then
      add("[ok]", "workspace state readable")
    elseif vim.fn.isdirectory(state_dir) == 1 then
      add("[ok]", "workspace state will be created on first use")
    else
      add("[warn]", "workspace state directory missing: " .. state_dir)
    end

    if vim.fn.filewritable(state_file) == 1 or vim.fn.filewritable(state_dir) == 2 then
      add("[ok]", "workspace state writable")
    else
      add("[warn]", "workspace state not writable: " .. state_file)
    end
  else
    add("[warn]", "workspace state file not configured")
  end

  local instruction_dir = type(deps.workspace_instruction_directory) == "function"
      and deps.workspace_instruction_directory(vim.fn.getcwd())
    or nil
  if type(instruction_dir) == "string" and instruction_dir ~= "" then
    if vim.fn.isdirectory(instruction_dir) == 1 then
      add("[ok]", "workspace instruction directory readable: " .. instruction_dir)
    else
      add("[ok]", "workspace instruction directory will be created on first use: " .. instruction_dir)
    end
  end

  local root = type(deps.project_root) == "function" and deps.project_root() or nil
  if type(root) == "string" and root ~= "" then
    add("[ok]", "project root detected: " .. root)
  else
    add("[warn]", "project root not detected")
  end
  local ignore_status = type(deps.workspace_instruction_ignore_status) == "function"
      and deps.workspace_instruction_ignore_status(root)
    or nil
  if type(ignore_status) == "table" then
    if ignore_status.status == "ignored" then
      add("[ok]", "workspace instruction files ignored by Git")
    elseif ignore_status.status == "not_ignored" then
      add(
        "[warn]",
        "workspace instruction files are not ignored by Git; add "
          .. tostring(ignore_status.rule or ".agents/")
          .. " to .gitignore or run :CoduxWorkspaceIgnore"
      )
    end
  end

  local state_data = {}
  local state_error
  if type(deps.read_workspace_state) == "function" then
    state_data, state_error = deps.read_workspace_state()
    state_data = type(state_data) == "table" and state_data or {}
  end
  if state_error then
    add("[warn]", state_error)
  end

  local projects = type(state_data.projects) == "table" and state_data.projects or {}
  local project = projects[root]
  local workspaces = type(project) == "table" and project.workspaces or nil
  local workspace_count = 0
  local invalid_count = 0
  if type(workspaces) == "table" then
    for safe_name, record in pairs(workspaces) do
      if type(record) == "table" and type(record.name) == "string" and type(record.project_root) == "string" then
        workspace_count = workspace_count + 1
      else
        invalid_count = invalid_count + 1
        if type(safe_name) == "string" then
          workspace_count = workspace_count + 1
        end
      end
    end
  end
  add("[ok]", tostring(workspace_count) .. " workspaces loaded")
  if invalid_count > 0 then
    add("[warn]", tostring(invalid_count) .. " workspace records invalid")
  end

  if type(deps.workspace_entries_for_project) == "function" then
    local entries, entries_error = deps.workspace_entries_for_project(root)
    if entries_error then
      add("[warn]", "dashboard target resolution failed: " .. entries_error)
    else
      add("[ok]", "dashboard can resolve targets")
      local inactive = 0
      local missing = 0
      for _, entry in ipairs(entries) do
        if entry.status == "inactive" then
          inactive = inactive + 1
        elseif entry.status == "missing" then
          missing = missing + 1
        end
      end
      if inactive > 0 then
        add("[warn]", tostring(inactive) .. " workspace windows inactive")
      else
        add("[ok]", "no workspace windows inactive")
      end
      if missing > 0 then
        add("[warn]", tostring(missing) .. " workspace windows missing")
      else
        add("[ok]", "no workspace windows missing")
      end
    end
  end

  return lines
end

function M.check()
  health_start("codux.nvim")

  if vim.fn.exists("*termopen") == 1 then
    health_ok("Neovim terminal support available")
  else
    health_error("Neovim terminal support is not available")
  end

  if type(vim.api.nvim_open_win) == "function" then
    health_ok("Neovim floating window support available")
  else
    health_error("Neovim floating window support is not available")
  end

  local ok, codux = pcall(require, "codux")
  if not ok or type(codux.health_info) ~= "function" then
    health_error("codux module is not loaded")
    return
  end

  local info = codux.health_info()
  local workspace_config = info.config and info.config.workspaces
  if workspace_config ~= false then
    local tmux = type(workspace_config) == "table" and workspace_config.tmux_cmd or "tmux"
    if type(tmux) ~= "string" or tmux == "" then
      tmux = "tmux"
    end
    if executable(tmux) then
      health_ok("tmux executable found: " .. tmux)
    else
      health_warn("tmux executable not found: " .. tmux .. " (:CoduxWorkspace requires tmux)")
    end

    local state_file = info.workspace_state_file
    if type(state_file) == "string" and state_file ~= "" then
      health_ok("workspace state file: " .. state_file)
      local state_dir = vim.fn.fnamemodify(state_file, ":h")
      if vim.fn.isdirectory(state_dir) == 1 then
        health_ok("workspace state directory is available")
        if vim.fn.filewritable(state_dir) == 2 then
          health_ok("workspace state directory is writable")
        else
          health_warn("workspace state directory is not writable: " .. state_dir)
        end
      else
        health_warn("workspace state directory does not exist yet: " .. state_dir)
      end
      if vim.fn.filereadable(state_file) == 1 then
        health_ok("workspace state file is readable")
        if vim.fn.filewritable(state_file) == 1 then
          health_ok("workspace state file is writable")
        else
          health_warn("workspace state file is not writable: " .. state_file)
        end
      elseif vim.fn.filereadable(state_file) == 0 and vim.fn.isdirectory(state_dir) == 1 then
        health_ok("workspace state file will be created on first workspace use")
      end
    end

    local instruction_dir = info.workspace_instruction_directory
    if type(instruction_dir) == "string" and instruction_dir ~= "" then
      health_ok("workspace instruction directory: " .. instruction_dir)
      if vim.fn.isdirectory(instruction_dir) == 1 then
        if vim.fn.filewritable(instruction_dir) == 2 then
          health_ok("workspace instruction directory is writable")
        else
          health_warn("workspace instruction directory is not writable: " .. instruction_dir)
        end
      else
        local ancestor = writable_existing_ancestor(instruction_dir)
        if ancestor then
          health_ok("workspace instruction directory will be created on first workspace use")
        else
          local parent = vim.fn.fnamemodify(instruction_dir, ":h")
          health_warn("workspace instruction directory parent is not writable: " .. parent)
        end
      end
    end
    local ignore_status = info.workspace_instruction_ignore_status
    if type(ignore_status) == "table" then
      if ignore_status.status == "ignored" then
        health_ok("workspace instruction files ignored by Git")
      elseif ignore_status.status == "not_ignored" then
        health_warn(
          "workspace instruction files are not ignored by Git; add "
            .. tostring(ignore_status.rule or ".agents/")
            .. " to .gitignore or run :CoduxWorkspaceIgnore"
        )
      end
    end
  end

  local commands = {}
  for _, provider in ipairs({ "codex", "grok" }) do
    for _, profile in ipairs({ "default", "auto", "danger" }) do
      table.insert(commands, {
        provider = provider,
        profile = profile,
        label = providers.provider_label(provider) .. " " .. providers.profile_label(profile):lower(),
        value = providers.command(info.config, provider, profile),
      })
    end
  end

  local checked_executables = {}
  for _, entry in ipairs(commands) do
    local config_error = command_util.error(entry.value, "configured " .. entry.provider .. " command")
    if config_error then
      health_error(entry.label .. " command: " .. config_error)
      return
    end

    health_ok("configured " .. entry.label .. " command: " .. command_util.display(entry.value))

    local executable_name = command_util.executable(entry.value)
    if type(executable_name) == "string" and executable_name ~= "" and not checked_executables[executable_name] then
      checked_executables[executable_name] = true
      if executable(executable_name) then
        health_ok(providers.provider_label(entry.provider) .. " executable found: " .. executable_name)
      else
        health_warn(providers.provider_label(entry.provider) .. " executable not found: " .. tostring(executable_name or "unknown"))
      end
    end
  end

  if info.popup_visible then
    health_ok("Codux agent popup is visible")
  else
    health_ok("Codux agent popup is hidden (normal when idle)")
  end

  if info.terminal_running then
    health_ok(tostring(providers.provider_label(info.agent_provider)) .. " terminal job is running")
    health_ok("Agent mode: " .. tostring(info.mode or "unknown"))
    health_ok("Agent permission profile: " .. tostring(info.permission_profile or "default"))
    if type(info.workspace) == "table" then
      health_ok("Codux workspace: " .. tostring(info.workspace.name or "unknown"))
    end
  else
    health_ok("Agent terminal job is not running (starts on demand)")
  end
end

return M
