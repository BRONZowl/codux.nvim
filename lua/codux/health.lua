local M = {}

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

local function command_display(command)
  if type(command) == "string" then
    return command
  end

  if type(command) ~= "table" then
    return tostring(command)
  end

  local parts = {}
  for _, part in ipairs(command) do
    local value = tostring(part)
    if value:find("%s") then
      value = vim.fn.shellescape(value)
    end
    table.insert(parts, value)
  end

  return table.concat(parts, " ")
end

local function command_executable(command)
  if type(command) == "table" then
    return command[1]
  end

  if type(command) == "string" then
    return command:match("^%s*(%S+)")
  end

  return nil
end

local function command_error(command)
  if type(command) == "string" then
    if command:match("^%s*$") then
      return "configured Codex command must not be empty"
    end
    return nil
  end

  if type(command) ~= "table" then
    return "configured Codex command must be a string or list"
  end

  if type(command[1]) ~= "string" or command[1] == "" then
    return "configured Codex command list must start with an executable"
  end

  return nil
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
  local codex_cmd = info.config and info.config.codex_cmd
  local config_error = command_error(codex_cmd)
  if config_error then
    health_error(config_error)
    return
  end

  health_ok("configured Codex command: " .. command_display(codex_cmd))

  local executable_name = command_executable(codex_cmd)
  if type(executable_name) == "string" and executable_name ~= "" and executable(executable_name) then
    health_ok("Codex executable found: " .. executable_name)
  else
    health_warn("Codex executable not found: " .. tostring(executable_name or "unknown"))
  end

  if info.popup_visible then
    health_ok("Codex popup is visible")
  else
    health_ok("Codex popup is hidden (normal when idle)")
  end

  if info.terminal_running then
    health_ok("Codex terminal job is running")
  else
    health_ok("Codex terminal job is not running (starts on demand)")
  end
end

return M
