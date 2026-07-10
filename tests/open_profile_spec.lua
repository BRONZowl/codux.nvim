local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_nil = h.assert_nil

if type(vim.api) == "table" then
  local settings = require("codux.settings")
  local settings_path = vim.fn.tempname() .. "-codux-open-profile-settings.json"
  settings.set_path_for_tests(settings_path)

  local codux = require("codux")
  codux.setup({ token_monitor = false })

  assert_equal(codux._v5.should_select_permission_profile(nil), true)
  assert_false(codux._v5.should_select_permission_profile(12))

  local profile_choices = codux._v5.permission_profile_choices()
  assert_equal(profile_choices[1].profile, "default")
  assert_equal(profile_choices[1].label, "Default")
  assert_equal(profile_choices[2].profile, "auto")
  assert_equal(profile_choices[2].label, "Autopilot")
  assert_equal(profile_choices[3].profile, "danger")
  assert_equal(profile_choices[3].label, "Full Access")
  assert_equal(profile_choices[4].profile, "default")
  assert_equal(profile_choices[4].agent_provider, "grok")
  assert_equal(profile_choices[4].label, "Grok")

  local keyed_profile_choices = codux._v5.keyed_permission_profile_choices()
  assert_equal(keyed_profile_choices[1].key, "d")
  assert_equal(keyed_profile_choices[1].label, "default")
  assert_equal(keyed_profile_choices[1].profile, "default")
  assert_equal(keyed_profile_choices[2].key, "a")
  assert_equal(keyed_profile_choices[2].label, "auto")
  assert_equal(keyed_profile_choices[2].profile, "auto")
  assert_equal(keyed_profile_choices[3].key, "f")
  assert_equal(keyed_profile_choices[3].label, "full")
  assert_equal(keyed_profile_choices[3].profile, "danger")
  assert_equal(keyed_profile_choices[4].key, "g")
  assert_equal(keyed_profile_choices[4].label, "grok")
  assert_equal(keyed_profile_choices[4].profile, "default")
  assert_equal(keyed_profile_choices[4].agent_provider, "grok")

  local profile_calls = {}
  local function open_default(prompt)
    table.insert(profile_calls, "default:" .. tostring(prompt))
    return "default"
  end
  local function open_auto(prompt)
    table.insert(profile_calls, "auto:" .. tostring(prompt))
    return "auto"
  end
  local function open_danger(prompt)
    table.insert(profile_calls, "danger:" .. tostring(prompt))
    return "danger"
  end

  assert_equal(codux._v5.open_permission_profile_choice({
    profile = "default",
  }, {
    initial_prompt = "hello",
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "default")
  assert_equal(profile_calls[#profile_calls], "default:hello")

  assert_equal(codux._v5.open_permission_profile_choice({
    profile = "unknown",
  }, {
    initial_prompt = "hello",
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), false)
  assert_equal(#profile_calls, 1)

  local forwarded_prompt
  local forwarded_opts
  assert_equal(codux._v5.open_permission_profile_choice({
    profile = "default",
  }, {
    initial_prompt = "plan this",
    open_opts = { initial_mode = "plan" },
    open_default = function(prompt, open_opts)
      forwarded_prompt = prompt
      forwarded_opts = open_opts
      return "forwarded"
    end,
  }), "forwarded")
  assert_equal(forwarded_prompt, "plan this")
  assert_equal(forwarded_opts.initial_mode, "plan")

  assert_equal(codux._v5.select_permission_profile_open({
    initial_prompt = "hello",
    selector = function(items, opts, callback)
      assert_equal(opts.prompt, "Codux agent profile:")
      assert_equal(opts.format_item(items[2]), "Autopilot")
      return callback(items[1])
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "default")
  assert_equal(profile_calls[#profile_calls], "default:hello")

  assert_equal(codux._v5.select_permission_profile_open({
    initial_prompt = "hello",
    selector = function(items, _, callback)
      return callback(items[2])
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "auto")
  assert_equal(profile_calls[#profile_calls], "auto:hello")

  assert_equal(codux._v5.select_permission_profile_open({
    initial_prompt = "hello",
    selector = function(items, _, callback)
      return callback(items[3])
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "danger")
  assert_equal(profile_calls[#profile_calls], "danger:hello")

  assert_equal(codux._v5.select_permission_profile_open({
    selector = function(_, _, callback)
      return callback(nil)
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), false)
  assert_equal(#profile_calls, 4)

  assert_equal(codux._v5.select_keyed_permission_profile_open({
    initial_prompt = "hello",
    menu = function(opts, callback)
      assert_equal(opts.title, " Codux agent profile ")
      assert_equal(opts.filetype, "codux-open-profile")
      assert_equal(opts.choices[1].key, "d")
      assert_equal(opts.choices[2].key, "a")
      assert_equal(opts.choices[3].key, "f")
      return callback(opts.choices[1])
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "default")
  assert_equal(profile_calls[#profile_calls], "default:hello")

  assert_equal(codux._v5.select_keyed_permission_profile_open({
    initial_prompt = "hello",
    menu = function(opts, callback)
      return callback(opts.choices[2])
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "auto")
  assert_equal(profile_calls[#profile_calls], "auto:hello")

  assert_equal(codux._v5.select_keyed_permission_profile_open({
    initial_prompt = "hello",
    menu = function(opts, callback)
      return callback(opts.choices[3])
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "danger")
  assert_equal(profile_calls[#profile_calls], "danger:hello")

  assert_equal(codux._v5.select_keyed_permission_profile_open({
    menu = function(_, callback)
      return callback(nil)
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), false)
  assert_equal(#profile_calls, 7)

  local selected_open_opts
  assert_equal(codux._v5.select_keyed_permission_profile_open({
    initial_prompt = "cold prompt",
    open_opts = { initial_mode = "plan" },
    menu = function(opts, callback)
      return callback(opts.choices[1])
    end,
    open_default = function(_, open_opts)
      selected_open_opts = open_opts
      return "selected"
    end,
  }), "selected")
  assert_equal(selected_open_opts.initial_mode, "plan")

  local provider_profile_open
  local provider_profile_menus = {}
  assert_equal(codux._v5.select_keyed_provider_profile_open({
    initial_prompt = "hello",
    open_opts = { initial_mode = "plan" },
    menu = function(opts, callback)
      table.insert(provider_profile_menus, opts)
      if opts.filetype == "codux-agent-provider" then
        assert_equal(opts.title, " Codux agent provider ")
        assert_equal(opts.choices[1].agent_provider, "grok")
        return callback(opts.choices[1])
      end
      assert_equal(opts.title, " Codux Grok profile ")
      assert_equal(opts.filetype, "codux-agent-profile")
      assert_equal(opts.choices[2].profile, "auto")
      return callback(opts.choices[2])
    end,
    open_provider = function(provider, profile, prompt, open_opts)
      provider_profile_open = { provider = provider, profile = profile, prompt = prompt, open_opts = open_opts }
      return provider .. ":" .. profile
    end,
  }), "grok:auto")
  assert_equal(#provider_profile_menus, 2)
  assert_equal(provider_profile_open.prompt, "hello")
  assert_equal(provider_profile_open.open_opts.initial_mode, "plan")

  assert_equal(codux._v5.select_keyed_provider_profile_open({
    menu = function(opts, callback)
      if opts.filetype == "codux-agent-provider" then
        return callback(opts.choices[2])
      end
      return callback(opts.choices[3])
    end,
    open_provider = function(provider, profile)
      return provider .. ":" .. profile
    end,
  }), "codex:danger")

  local canceled_profile_opened = false
  assert_equal(codux._v5.select_keyed_provider_profile_open({
    menu = function(opts, callback)
      if opts.filetype == "codux-agent-provider" then
        return callback(nil)
      end
      canceled_profile_opened = true
      return callback(opts.choices[1])
    end,
    open_provider = function()
      return "opened"
    end,
  }), false)
  assert_false(canceled_profile_opened)

  local canceled_open
  assert_equal(codux._v5.select_keyed_provider_profile_open({
    menu = function(opts, callback)
      if opts.filetype == "codux-agent-provider" then
        return callback(opts.choices[1])
      end
      return callback(nil)
    end,
    open_provider = function()
      canceled_open = true
      return "opened"
    end,
  }), false)
  assert_nil(canceled_open)

  local forced_menus = {}
  assert_equal(codux._v5.select_keyed_provider_profile_open({
    agent_provider = "grok",
    menu = function(opts, callback)
      table.insert(forced_menus, opts)
      return callback(opts.choices[3])
    end,
    open_provider = function(provider, profile)
      return provider .. ":" .. profile
    end,
  }), "grok:danger")
  assert_equal(#forced_menus, 1)
  assert_equal(forced_menus[1].filetype, "codux-agent-profile")

  local selected_only
  assert_equal(codux._v5.select_keyed_provider_profile({
    menu = function(opts, callback)
      if opts.filetype == "codux-agent-provider" then
        return callback(opts.choices[1])
      end
      return callback(opts.choices[2])
    end,
    open_provider = function()
      error("selection-only picker must not open an agent")
    end,
    open_default = function()
      error("selection-only picker must not open default")
    end,
    on_select = function(choice)
      selected_only = {
        agent_provider = choice.agent_provider,
        profile = choice.profile,
      }
      return "selected-only"
    end,
  }), "selected-only")
  assert_equal(selected_only.agent_provider, "grok")
  assert_equal(selected_only.profile, "auto")

  local default_provider_choice
  assert_equal(codux._v5.select_default_agent_provider({
    menu = function(opts, callback)
      assert_equal(opts.title, " Codux agent provider ")
      assert_equal(opts.filetype, "codux-default-provider")
      assert_equal(opts.choices[1].agent_provider, "grok")
      assert_equal(opts.choices[2].agent_provider, "codex")
      return callback(opts.choices[1])
    end,
    on_select = function(choice)
      default_provider_choice = choice.agent_provider
      return true
    end,
  }), true)
  assert_equal(default_provider_choice, "grok")

  assert_equal(codux.set_default_provider("grok"), true)
  assert_equal(codux.set_default_provider("nope"), false)

  local default_open_menus = {}
  local old_select_keyed = codux._v5.select_keyed_provider_profile_open
  codux._v5.select_keyed_provider_profile_open = function(opts)
    table.insert(default_open_menus, opts)
    return "profile-only"
  end
  assert_equal(codux.open_with_keyed_profile_menu({ initial_prompt = "hi" }), "profile-only")
  assert_equal(#default_open_menus, 1)
  assert_equal(default_open_menus[1].agent_provider, "grok")
  assert_equal(default_open_menus[1].initial_prompt, "hi")

  -- Fail-safe: when the Codux popup is already open, open is a no-op.
  local menu_calls_before = #default_open_menus
  local old_is_popup_open = codux.is_popup_open
  codux.is_popup_open = function()
    return true
  end
  assert_false(codux.open_with_keyed_profile_menu({ initial_prompt = "blocked" }))
  assert_equal(#default_open_menus, menu_calls_before)
  codux.is_popup_open = old_is_popup_open
  codux._v5.select_keyed_provider_profile_open = old_select_keyed

  local opened_opts
  local old_open_with_keyed_profile_menu = codux.open_with_keyed_profile_menu
  codux.open_with_keyed_profile_menu = function(opts)
    opened_opts = opts
    return "opened"
  end
  assert_equal(codux._v5.send_prompt_or_open_with_profile("review me"), "opened")
  assert_equal(opened_opts.initial_prompt, "review me")
  assert_equal(opened_opts.open_opts.initial_mode, "plan")
  codux.open_with_keyed_profile_menu = old_open_with_keyed_profile_menu

  local open_map = vim.fn.maparg("<leader>zc", "n", false, true)
  assert_equal(open_map.desc, "open codux")
  local default_provider_map = vim.fn.maparg("<leader>zP", "n", false, true)
  assert_equal(default_provider_map.desc, "set default provider")
  assert_equal(vim.tbl_isempty(vim.fn.maparg("<leader>za", "n", false, true)), true)
  assert_equal(vim.tbl_isempty(vim.fn.maparg("<leader>zA", "n", false, true)), true)

  settings.set_path_for_tests(nil)
  pcall(vim.fn.delete, settings_path)
end

print("open_profile_spec.lua: ok")
