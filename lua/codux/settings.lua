local grok_config = require("codux.grok_config")
local json = require("codux.json")
local providers = require("codux.providers")

local M = {}

-- Test-only override for the settings file path.
local path_override = nil

function M.set_path_for_tests(path)
  if type(path) == "string" and path ~= "" then
    path_override = path
  else
    path_override = nil
  end
end

function M.settings_file()
  if type(path_override) == "string" and path_override ~= "" then
    return path_override
  end
  if type(vim.fn.stdpath) == "function" then
    return vim.fn.stdpath("data") .. "/codux/settings.json"
  end
  return "codux-settings.json"
end

function M.read()
  local path = M.settings_file()
  if type(vim.fn.filereadable) ~= "function" or vim.fn.filereadable(path) ~= 1 then
    return {}
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return {}
  end

  local decoded = json.decode(table.concat(lines, "\n"))
  if type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

function M.write(data)
  data = type(data) == "table" and data or {}
  local path = M.settings_file()
  local directory = vim.fn.fnamemodify(path, ":h")
  if directory ~= "" and directory ~= "." then
    local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, directory, "p")
    if not mkdir_ok or (mkdir_result ~= 1 and not (type(vim.fn.isdirectory) == "function" and vim.fn.isdirectory(directory) == 1)) then
      return false, "Failed to create Codux settings directory"
    end
  end

  local encoded = json.encode(data)
  if type(encoded) ~= "string" then
    return false, "Failed to encode Codux settings"
  end

  local ok, result = pcall(vim.fn.writefile, { encoded }, path)
  if not ok or result ~= 0 then
    return false, "Failed to write Codux settings"
  end

  if type(vim.fn.setfperm) == "function" then
    pcall(vim.fn.setfperm, path, "rw-------")
  end
  return true
end

function M.get_default_agent_provider()
  local data = M.read()
  return providers.normalize_provider(data.default_agent_provider)
end

function M.set_default_agent_provider(provider)
  provider = providers.normalize_provider(provider)
  if not provider then
    return false, "Unknown agent provider"
  end

  local data = M.read()
  data.default_agent_provider = provider
  local ok, err = M.write(data)
  if not ok then
    return false, err
  end
  return true
end

--- Whether setup/env already chose the provider so the saved preference should not apply.
function M.should_apply_persisted_default(opts, env)
  opts = type(opts) == "table" and opts or {}
  if opts.default_agent_provider ~= nil then
    return false
  end
  env = env or (type(vim) == "table" and vim.env) or {}
  local env_value = env.CODUX_AGENT_PROVIDER
  if type(env_value) == "string" and env_value:match("%S") then
    return false
  end
  return true
end

function M.get_grok_theme()
  local data = M.read()
  return grok_config.normalize_theme(data.grok_theme)
end

function M.set_grok_theme(theme)
  theme = grok_config.normalize_theme(theme)
  if not theme then
    return false, "Unknown Grok theme"
  end

  local data = M.read()
  data.grok_theme = theme
  local ok, err = M.write(data)
  if not ok then
    return false, err
  end
  return true
end

local function setup_grok_theme_from_opts(opts)
  opts = type(opts) == "table" and opts or {}
  local providers_opts = type(opts.providers) == "table" and opts.providers or {}
  local grok_opts = type(providers_opts.grok) == "table" and providers_opts.grok or {}
  return grok_config.normalize_theme(grok_opts.theme)
end

--- Resolve preferred Grok theme and seed/sync stores.
--- Precedence: setup providers.grok.theme → CODUX_GROK_THEME → settings → ~/.grok/config.toml
function M.resolve_and_sync_grok_theme(opts, env)
  opts = type(opts) == "table" and opts or {}
  env = env or (type(vim) == "table" and vim.env) or {}

  local from_setup = setup_grok_theme_from_opts(opts)
  local from_env = grok_config.normalize_theme(env.CODUX_GROK_THEME)
  local from_settings = M.get_grok_theme()
  local from_grok = grok_config.normalize_theme(grok_config.read_ui_theme())

  local theme = from_setup or from_env or from_settings or from_grok
  if not theme then
    return nil
  end

  -- Persist in Codux settings when missing or when setup/env explicitly wins.
  if from_settings ~= theme then
    M.set_grok_theme(theme)
  end

  local ok, err = grok_config.write_ui_theme(theme)
  if not ok then
    return theme, err
  end
  return theme
end

function M.ensure_grok_theme_applied()
  local theme = M.get_grok_theme()
  if not theme then
    return true
  end
  return grok_config.write_ui_theme(theme)
end

return M
