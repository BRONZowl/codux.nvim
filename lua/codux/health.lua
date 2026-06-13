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

function M.check()
  health_start("codux.nvim")

  if executable("codex") then
    health_ok("codex executable found")
  else
    health_warn("codex executable not found")
  end

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
  health_ok("configured Codex command: " .. info.config.codex_cmd)

  if info.popup_visible then
    health_ok("Codex popup is visible")
  else
    health_warn("Codex popup is hidden")
  end

  if info.terminal_running then
    health_ok("Codex terminal job is running")
  else
    health_warn("Codex terminal job is not running yet")
  end
end

return M
