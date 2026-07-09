local terminal_mod = require("codux.terminal")
local ui = require("codux.ui")

local M = {}

local permission_profiles = {
  {
    profile = "default",
    selector_label = "Default",
    keyed_label = "default",
    key = "d",
    desc = "Open Codex Default",
  },
  {
    profile = "auto",
    selector_label = "Autopilot",
    keyed_label = "auto",
    key = "a",
    desc = "Open Codex Auto",
  },
  {
    profile = "danger",
    agent_provider = "codex",
    selector_label = "Full Access",
    keyed_label = "full",
    key = "f",
    desc = "Open Codex Full Access",
  },
  {
    profile = "default",
    agent_provider = "grok",
    selector_label = "Grok",
    keyed_label = "grok",
    key = "g",
    desc = "Open Grok",
  },
  {
    profile = "auto",
    agent_provider = "grok",
    selector_label = "Grok Autopilot",
    keyed_label = "grok auto",
    key = "G",
    desc = "Open Grok Auto",
  },
  {
    profile = "danger",
    agent_provider = "grok",
    selector_label = "Grok Full Access",
    keyed_label = "grok full",
    key = "!",
    desc = "Open Grok Full Access",
  },
}

permission_profiles[1].agent_provider = "codex"
permission_profiles[2].agent_provider = "codex"

local function filter_completion(values, arglead)
  local matches = {}
  arglead = arglead or ""
  for _, value in ipairs(type(values) == "table" and values or {}) do
    if arglead == "" or tostring(value):find(arglead, 1, true) == 1 then
      table.insert(matches, value)
    end
  end
  return matches
end

function M.install(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local project_root = type(deps.project_root) == "function" and deps.project_root or function()
    return nil
  end
  local names_for_project = type(deps.names_for_project) == "function" and deps.names_for_project or function()
    return {}
  end
  local mission_names_for_project = type(deps.mission_names_for_project) == "function" and deps.mission_names_for_project
    or function()
      return {}
    end

  api.mode_display_label = terminal_mod.mode_display_label
  api.strip_terminal_control_sequences = terminal_mod.strip_terminal_control_sequences
  api.detect_terminal_mode_from_lines = terminal_mod.detect_terminal_mode_from_lines
  api.output_looks_like_question = terminal_mod.output_looks_like_question

  function api.permission_profile_choices()
    local choices = {}
    for _, spec in ipairs(permission_profiles) do
      table.insert(choices, { label = spec.selector_label, profile = spec.profile, agent_provider = spec.agent_provider })
    end
    return choices
  end

  function api.keyed_permission_profile_choices()
    local choices = {}
    for _, spec in ipairs(permission_profiles) do
      table.insert(choices, {
        key = spec.key,
        label = spec.keyed_label,
        profile = spec.profile,
        agent_provider = spec.agent_provider,
        desc = spec.desc,
      })
    end
    return choices
  end

  function api.should_select_permission_profile(job_id)
    return job_id == nil
  end

  function api.open_permission_profile_choice(choice, opts)
    opts = type(opts) == "table" and opts or {}
    if type(choice) ~= "table" then
      return false
    end

    if type(opts.open_provider) == "function" and type(choice.agent_provider) == "string" then
      return opts.open_provider(choice.agent_provider, choice.profile, opts.initial_prompt, opts.open_opts)
    end

    local openers = {
      default = opts.open_default,
      auto = opts.open_auto,
      danger = opts.open_danger,
    }
    local opener = openers[choice.profile]
    if type(opener) == "function" then
      return opener(opts.initial_prompt, opts.open_opts)
    end
    return false
  end

  function api.select_permission_profile_open(opts)
    opts = type(opts) == "table" and opts or {}
    local selector = opts.selector or (vim.ui and vim.ui.select)
    if type(selector) ~= "function" then
      if type(opts.open_default) == "function" then
        return opts.open_default(opts.initial_prompt, opts.open_opts)
      end
      return false
    end

    return selector(api.permission_profile_choices(), {
      prompt = "Codux agent profile:",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      return api.open_permission_profile_choice(choice, opts)
    end)
  end

  function api.select_keyed_permission_profile_open(opts)
    opts = type(opts) == "table" and opts or {}
    local menu = opts.menu or ui.key_choice_menu
    if type(menu) ~= "function" then
      if type(opts.open_default) == "function" then
        return opts.open_default(opts.initial_prompt, opts.open_opts)
      end
      return false
    end

    return menu({
      title = " Codux agent profile ",
      choices = api.keyed_permission_profile_choices(),
      filetype = "codux-open-profile",
      cancel_desc = "Cancel Codux Open",
      create_error = "Failed to create Codux open menu",
      open_error = "Failed to open Codux open menu",
    }, function(choice)
      return api.open_permission_profile_choice(choice, opts)
    end)
  end

  api.filter_completion = filter_completion

  function api.complete_workspace_names(arglead)
    return api.filter_completion(names_for_project(project_root()), arglead)
  end

  function api.complete_mission_names(arglead)
    return api.filter_completion(mission_names_for_project(project_root()), arglead)
  end

  function api.complete_create(arglead, _cmdline, _cursorpos)
    return api.filter_completion({ "--custom", "--codex", "--grok" }, arglead)
  end

  return api
end

return M
