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

local PROFILE_CHOICES = {
  {
    key = "d",
    agent_provider = "codex",
    profile = "default",
    selector_label = "Default",
    keyed_label = "default",
    profile_label = "Codex Default",
    desc = "Open Codex Default",
  },
  {
    key = "a",
    agent_provider = "codex",
    profile = "auto",
    selector_label = "Autopilot",
    keyed_label = "auto",
    profile_label = "Codex Auto",
    desc = "Open Codex Auto",
  },
  {
    key = "f",
    agent_provider = "codex",
    profile = "danger",
    selector_label = "Full Access",
    keyed_label = "full",
    profile_label = "Codex Full",
    desc = "Open Codex Full Access",
  },
  {
    key = "g",
    agent_provider = "grok",
    profile = "default",
    selector_label = "Grok",
    keyed_label = "grok",
    profile_label = "Grok Default",
    desc = "Open Grok",
  },
  {
    key = "G",
    agent_provider = "grok",
    profile = "auto",
    selector_label = "Grok Autopilot",
    keyed_label = "grok auto",
    profile_label = "Grok Auto",
    desc = "Open Grok Auto",
  },
  {
    key = "!",
    agent_provider = "grok",
    profile = "danger",
    selector_label = "Grok Full Access",
    keyed_label = "grok full",
    profile_label = "Grok Full",
    desc = "Open Grok Full Access",
  },
}

local PROVIDER_CHOICES = {
  { key = "g", agent_provider = "grok", label = "Grok", desc = "Use Grok" },
  { key = "c", agent_provider = "codex", label = "Codex", desc = "Use Codex" },
}

local PROVIDER_PROFILE_CHOICES = {
  {
    key = "d",
    profile = "default",
    keyed_label = "default",
    profile_label = "Default",
    desc_label = "Default",
  },
  {
    key = "a",
    profile = "auto",
    keyed_label = "auto",
    profile_label = "Auto",
    desc_label = "Auto",
  },
  {
    key = "f",
    profile = "danger",
    keyed_label = "full",
    profile_label = "Full",
    desc_label = "Full Access",
  },
}

local function copy_choice(choice, label_key)
  return {
    key = choice.key,
    label = choice[label_key or "label"] or choice.label,
    agent_provider = choice.agent_provider,
    profile = choice.profile,
    desc = choice.desc,
  }
end

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

function M.provider_choices()
  local choices = {}
  for _, choice in ipairs(PROVIDER_CHOICES) do
    table.insert(choices, copy_choice(choice))
  end
  return choices
end

function M.permission_profile_choices()
  local choices = {}
  for _, choice in ipairs(PROFILE_CHOICES) do
    table.insert(choices, {
      label = choice.selector_label,
      profile = choice.profile,
      agent_provider = choice.agent_provider,
    })
  end
  return choices
end

function M.keyed_permission_profile_choices(label_key)
  local choices = {}
  for _, choice in ipairs(PROFILE_CHOICES) do
    table.insert(choices, copy_choice(choice, label_key or "keyed_label"))
  end
  return choices
end

function M.keyed_permission_profile_choices_for_provider(provider, label_key)
  provider = M.normalize_provider(provider) or "codex"
  local provider_label = M.provider_label(provider)
  local choices = {}
  for _, choice in ipairs(PROVIDER_PROFILE_CHOICES) do
    table.insert(choices, {
      key = choice.key,
      label = choice[label_key or "keyed_label"] or choice.keyed_label,
      agent_provider = provider,
      profile = choice.profile,
      desc = "Open " .. provider_label .. " " .. choice.desc_label,
    })
  end
  return choices
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
  provider = M.normalize_provider(provider) or "codex"
  if provider == "grok" then
    if session_id == "" then
      return command_util.with_args(command, { "--resume" })
    end
    return command_util.with_args(command, { "--resume", session_id })
  end
  if session_id == "" then
    return command
  end
  return command_util.with_args(command, { "resume", session_id })
end

function M.workspace_command(config, workspace, initial_prompt, opts)
  opts = type(opts) == "table" and opts or {}
  workspace = type(workspace) == "table" and workspace or nil
  local profile = workspace and workspace.permission_profile or opts.permission_profile or "default"
  local agent_provider = M.normalize_provider(workspace and workspace.agent_provider)
    or M.normalize_provider(opts.agent_provider)
    or M.default_provider(config)
  profile = M.normalize_profile(profile) or "default"

  local command = M.command(config, agent_provider, profile)
  command = M.command_with_instructions(command, agent_provider, workspace and workspace.resolved_instruction or nil)

  local resume_session_id = workspace and (workspace.agent_session_id or workspace.codex_session_id) or nil
  local grok_session_id = workspace and type(workspace.agent_session_id) == "string" and trim(workspace.agent_session_id) or ""
  local has_initial_prompt = type(initial_prompt) == "string" and initial_prompt ~= ""
  if agent_provider == "grok" and workspace and workspace.resume_agent_session == true and grok_session_id ~= "" then
    command = M.command_with_resume(command, agent_provider, grok_session_id)
  elseif agent_provider ~= "grok" and resume_session_id and not has_initial_prompt then
    command = M.command_with_resume(command, agent_provider, resume_session_id)
  end

  return command, agent_provider, profile
end

function M.prompt_must_be_pasted(provider)
  return M.normalize_provider(provider) == "grok"
end

function M.token_usage_supported(provider)
  return (M.normalize_provider(provider) or "codex") == "codex"
end

return M
