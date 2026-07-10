local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil

local config_defaults = require("codux.config_defaults")

do
  local config = config_defaults.defaults()
  assert_nil(config.codex_cmd)
  assert_nil(config.workspace_auto_cmd)
  assert_nil(config.danger_full_access_cmd)
end

do
  local opts = {
    codex_cmd = "legacy-default",
    workspace_auto_cmd = "legacy-auto",
    danger_full_access_cmd = "legacy-danger",
  }
  local config = config_defaults.defaults()
  config_defaults.apply_legacy_codex_aliases(config, opts)

  assert_equal(config.providers.codex.default_cmd, "legacy-default")
  assert_equal(config.providers.codex.auto_cmd, "legacy-auto")
  assert_equal(config.providers.codex.danger_cmd, "legacy-danger")
end

do
  local opts = {
    codex_cmd = "legacy-default",
    workspace_auto_cmd = "legacy-auto",
    danger_full_access_cmd = "legacy-danger",
    providers = {
      codex = {
        default_cmd = "nested-default",
        auto_cmd = "nested-auto",
        danger_cmd = "nested-danger",
      },
    },
  }
  local config = config_defaults.defaults()
  config.providers.codex.default_cmd = opts.providers.codex.default_cmd
  config.providers.codex.auto_cmd = opts.providers.codex.auto_cmd
  config.providers.codex.danger_cmd = opts.providers.codex.danger_cmd
  config_defaults.apply_legacy_codex_aliases(config, opts)

  assert_equal(config.providers.codex.default_cmd, "nested-default")
  assert_equal(config.providers.codex.auto_cmd, "nested-auto")
  assert_equal(config.providers.codex.danger_cmd, "nested-danger")
end

print("config_defaults_spec.lua: ok")
