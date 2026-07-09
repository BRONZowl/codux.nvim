local command_util = require("codux.command")
local text_util = require("codux.text")

local M = {}

local PROVIDERS = {
  codex = true,
  grok = true,
}

local PROFILES = {
  default = true,
  auto = true,
  danger = true,
}

local function trim(value)
  return text_util.trim(value)
end

function M.normalize_provider(value)
  if type(value) ~= "string" then
    return nil
  end
  value = trim(value):lower()
  if PROVIDERS[value] then
    return value
  end
  return nil
end

function M.normalize_profile(value)
  if type(value) ~= "string" then
    return nil
  end
  value = trim(value):lower()
  if value == "workspace_auto" then
    value = "auto"
  elseif value == "full" or value == "full_access" then
    value = "danger"
  end
  if PROFILES[value] then
    return value
  end
  return nil
end

function M.default_provider(config)
  config = type(config) == "table" and config or {}
  return M.normalize_provider(config.default_agent_provider) or "codex"
end

function M.provider_label(provider)
  provider = M.normalize_provider(provider) or "codex"
  if provider == "grok" then
    return "Grok"
  end
  return "Codex"
end

function M.profile_label(profile)
  profile = M.normalize_profile(profile) or "default"
  if profile == "auto" then
    return "Autopilot"
  end
  if profile == "danger" then
    return "Full Access"
  end
  return "Default"
end

local function provider_config(config, provider)
  config = type(config) == "table" and config or {}
  local providers = type(config.providers) == "table" and config.providers or {}
  local provider_config = type(providers[provider]) == "table" and providers[provider] or {}
  if provider == "codex" then
    provider_config.default_cmd = config.codex_cmd or provider_config.default_cmd
    provider_config.auto_cmd = config.workspace_auto_cmd or provider_config.auto_cmd
    provider_config.danger_cmd = config.danger_full_access_cmd or provider_config.danger_cmd
  end
  return provider_config
end

function M.command(config, provider, profile)
  provider = M.normalize_provider(provider) or M.default_provider(config)
  profile = M.normalize_profile(profile) or "default"
  local provider_config = provider_config(config, provider)
  if profile == "auto" then
    return provider_config.auto_cmd or provider_config.default_cmd
  end
  if profile == "danger" then
    return provider_config.danger_cmd or provider_config.default_cmd
  end
  return provider_config.default_cmd
end

function M.executable(config, provider, profile)
  return command_util.executable(M.command(config, provider, profile))
end

function M.command_with_instructions(command, provider, instructions)
  instructions = type(instructions) == "string" and trim(instructions) or ""
  if instructions == "" then
    return command
  end
  provider = M.normalize_provider(provider) or "codex"
  if provider == "grok" then
    return command_util.with_args(command, { "--rules", instructions })
  end
  return command_util.with_developer_instructions(command, instructions)
end

function M.command_with_prompt(command, provider, prompt)
  provider = M.normalize_provider(provider) or "codex"
  if provider == "grok" then
    return command
  end
  return command_util.with_prompt(command, prompt)
end

function M.command_with_resume(command, provider, session_id)
  session_id = type(session_id) == "string" and trim(session_id) or ""
  if session_id == "" then
    return command
  end
  provider = M.normalize_provider(provider) or "codex"
  if provider == "grok" then
    return command_util.with_args(command, { "--resume", session_id })
  end
  return command_util.with_args(command, { "resume", session_id })
end

function M.command_with_session_id(command, provider, session_id)
  session_id = type(session_id) == "string" and trim(session_id) or ""
  if session_id == "" then
    return command
  end
  provider = M.normalize_provider(provider) or "codex"
  if provider == "grok" then
    return command_util.with_args(command, { "--session-id", session_id })
  end
  return command
end

function M.prompt_must_be_pasted(provider)
  return M.normalize_provider(provider) == "grok"
end

function M.token_usage_supported(provider)
  return (M.normalize_provider(provider) or "codex") == "codex"
end

function M.generate_session_id()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (template:gsub("[xy]", function(char)
    local value = char == "x" and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", value)
  end))
end

return M
