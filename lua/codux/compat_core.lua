local terminal_mod = require("codux.terminal")
local ui = require("codux.ui")
local providers = require("codux.providers")

local M = {}

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
    return providers.permission_profile_choices()
  end

  function api.keyed_permission_profile_choices()
    return providers.keyed_permission_profile_choices()
  end

  function api.keyed_agent_provider_choices()
    return providers.provider_choices()
  end

  function api.keyed_permission_profile_choices_for_provider(provider)
    return providers.keyed_permission_profile_choices_for_provider(provider)
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

  function api.select_keyed_provider_profile(opts)
    opts = type(opts) == "table" and opts or {}
    local menu = opts.menu or ui.key_choice_menu
    if type(menu) ~= "function" then
      return false
    end

    local function select_profile(agent_provider)
      agent_provider = providers.normalize_provider(agent_provider) or providers.default_provider(opts.config)
      local provider_label = providers.provider_label(agent_provider)
      return menu({
        title = opts.profile_title or (" Codux " .. provider_label .. " profile "),
        choices = api.keyed_permission_profile_choices_for_provider(agent_provider),
        filetype = opts.profile_filetype or "codux-agent-profile",
        zindex = opts.profile_zindex,
        cancel_desc = opts.profile_cancel_desc or "Cancel Codux Profile",
        create_error = opts.profile_create_error or "Failed to create Codux profile menu",
        open_error = opts.profile_open_error or "Failed to open Codux profile menu",
      }, function(choice)
        if type(choice) ~= "table" then
          return false
        end
        choice.agent_provider = agent_provider
        if type(opts.on_select) == "function" then
          return opts.on_select(choice)
        end
        return choice
      end)
    end

    local forced_provider = providers.normalize_provider(opts.agent_provider)
    if forced_provider then
      return select_profile(forced_provider)
    end

    return menu({
      title = opts.provider_title or " Codux agent provider ",
      choices = api.keyed_agent_provider_choices(),
      filetype = opts.provider_filetype or "codux-agent-provider",
      zindex = opts.provider_zindex,
      cancel_desc = opts.provider_cancel_desc or "Cancel Codux Provider",
      create_error = opts.provider_create_error or "Failed to create Codux provider menu",
      open_error = opts.provider_open_error or "Failed to open Codux provider menu",
    }, function(choice)
      if type(choice) ~= "table" then
        return false
      end
      return select_profile(choice.agent_provider)
    end)
  end

  function api.select_keyed_provider_profile_open(opts)
    opts = type(opts) == "table" and opts or {}
    local menu = opts.menu or ui.key_choice_menu
    if type(menu) ~= "function" then
      if type(opts.open_default) == "function" then
        return opts.open_default(opts.initial_prompt, opts.open_opts)
      end
      return false
    end

    opts.menu = menu
    opts.on_select = function(choice)
      return api.open_permission_profile_choice(choice, opts)
    end
    return api.select_keyed_provider_profile(opts)
  end

  function api.select_default_agent_provider(opts)
    opts = type(opts) == "table" and opts or {}
    local menu = opts.menu or ui.key_choice_menu
    if type(menu) ~= "function" then
      return false
    end

    local forced = providers.normalize_provider(opts.agent_provider)
    if forced then
      if type(opts.on_select) == "function" then
        return opts.on_select({ agent_provider = forced })
      end
      return forced
    end

    return menu({
      title = opts.provider_title or " Codux agent provider ",
      choices = api.keyed_agent_provider_choices(),
      filetype = opts.provider_filetype or "codux-default-provider",
      zindex = opts.provider_zindex,
      cancel_desc = opts.provider_cancel_desc or "Cancel Codux Default Provider",
      create_error = opts.provider_create_error or "Failed to create Codux default provider menu",
      open_error = opts.provider_open_error or "Failed to open Codux default provider menu",
    }, function(choice)
      if type(choice) ~= "table" then
        return false
      end
      if type(opts.on_select) == "function" then
        return opts.on_select(choice)
      end
      return choice
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
