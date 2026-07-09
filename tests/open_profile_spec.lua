local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false

if type(vim.api) == "table" then
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
  assert_equal(open_map.desc, "open codex")
  assert_equal(vim.tbl_isempty(vim.fn.maparg("<leader>za", "n", false, true)), true)
  assert_equal(vim.tbl_isempty(vim.fn.maparg("<leader>zA", "n", false, true)), true)
end

print("open_profile_spec.lua: ok")
