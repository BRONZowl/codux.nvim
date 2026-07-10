local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false

local settings = require("codux.settings")
local providers = require("codux.providers")

do
  assert_true(settings.should_apply_persisted_default({}, {}))
  assert_true(settings.should_apply_persisted_default({}, { CODUX_AGENT_PROVIDER = "" }))
  assert_true(settings.should_apply_persisted_default({}, { CODUX_AGENT_PROVIDER = "   " }))
  assert_false(settings.should_apply_persisted_default({ default_agent_provider = "grok" }, {}))
  assert_false(settings.should_apply_persisted_default({}, { CODUX_AGENT_PROVIDER = "codex" }))
  assert_false(settings.should_apply_persisted_default({ default_agent_provider = "codex" }, {
    CODUX_AGENT_PROVIDER = "grok",
  }))
end

if type(vim.api) == "table" and type(vim.fn.tempname) == "function" then
  local path = vim.fn.tempname() .. "-codux-settings.json"
  settings.set_path_for_tests(path)

  assert_nil(settings.get_default_agent_provider())

  local ok, err = settings.set_default_agent_provider("nope")
  assert_false(ok)
  assert_equal(err, "Unknown agent provider")
  assert_nil(settings.get_default_agent_provider())

  assert_true(settings.set_default_agent_provider("grok"))
  assert_equal(settings.get_default_agent_provider(), "grok")

  assert_true(settings.set_default_agent_provider("codex"))
  assert_equal(settings.get_default_agent_provider(), "codex")

  -- Round-trip through read/write of full settings table.
  assert_true(settings.write({ default_agent_provider = "grok", extra = true }))
  local data = settings.read()
  assert_equal(data.default_agent_provider, "grok")
  assert_equal(data.extra, true)
  assert_equal(settings.get_default_agent_provider(), "grok")

  local codux = require("codux")
  local old_env = vim.env.CODUX_AGENT_PROVIDER
  vim.env.CODUX_AGENT_PROVIDER = nil

  settings.set_default_agent_provider("grok")
  codux.setup({ token_monitor = false })
  assert_equal(providers.default_provider(codux.health_info().config), "grok")

  codux.setup({ token_monitor = false, default_agent_provider = "codex" })
  assert_equal(providers.default_provider(codux.health_info().config), "codex")

  settings.set_default_agent_provider("grok")
  vim.env.CODUX_AGENT_PROVIDER = "codex"
  codux.setup({ token_monitor = false })
  assert_equal(providers.default_provider(codux.health_info().config), "codex")

  vim.env.CODUX_AGENT_PROVIDER = old_env
  settings.set_path_for_tests(nil)
  pcall(vim.fn.delete, path)

  -- set_default_provider persists for the next setup when no setup/env override.
  local path2 = vim.fn.tempname() .. "-codux-settings2.json"
  settings.set_path_for_tests(path2)
  vim.env.CODUX_AGENT_PROVIDER = nil
  codux.setup({ token_monitor = false, default_agent_provider = "codex" })
  assert_true(codux.set_default_provider("grok"))
  assert_equal(settings.get_default_agent_provider(), "grok")
  codux.setup({ token_monitor = false })
  assert_equal(providers.default_provider(codux.health_info().config), "grok")
  vim.env.CODUX_AGENT_PROVIDER = old_env
  settings.set_path_for_tests(nil)
  pcall(vim.fn.delete, path2)
end

print("settings_spec.lua: ok")
