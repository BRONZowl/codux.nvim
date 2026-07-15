local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true

local health = require("codux.health")

do
  local public = health.public_config({
    default_agent_provider = "codex",
    providers = {
      codex = {
        default_cmd = 'codex -s workspace-write -c api_key="should-not-appear"',
        auto_cmd = "codex-auto --token secret-value",
        danger_cmd = { "codex-danger", "--api-key", "xyz" },
      },
      grok = {
        default_cmd = "grok --sandbox workspace",
        theme = "tokyonight",
        api_key = "legacy-key-must-drop",
      },
    },
    token_monitor = {
      enabled = true,
      refresh_ms = 60000,
      timeout_ms = 5000,
      grok = {
        api_key = "legacy-monitor-key",
        oauth_token = "oauth-secret",
      },
      codex_cmd = "codex-token --profile usage",
    },
    password = "top-secret",
    client_secret = "drop-me",
  })

  assert_equal(public.default_agent_provider, "codex")
  assert_equal(public.providers.codex.default_cmd, "codex")
  assert_equal(public.providers.codex.auto_cmd, "codex-auto")
  assert_equal(public.providers.codex.danger_cmd, "codex-danger")
  assert_equal(public.providers.grok.default_cmd, "grok")
  assert_equal(public.providers.grok.theme, "tokyonight")
  assert_nil(public.providers.grok.api_key)
  assert_nil(public.password)
  assert_nil(public.client_secret)
  assert_equal(public.token_monitor.enabled, true)
  assert_equal(public.token_monitor.refresh_ms, 60000)
  assert_equal(public.token_monitor.codex_cmd, "codex-token")
  assert_true(public.token_monitor.grok == nil or public.token_monitor.grok.api_key == nil)
  if type(public.token_monitor.grok) == "table" then
    assert_nil(public.token_monitor.grok.api_key)
    assert_nil(public.token_monitor.grok.oauth_token)
  end

  local encoded = vim.inspect and vim.inspect(public) or ""
  if encoded == "" then
    -- Plain Lua test runner without vim.inspect: flatten manually.
    encoded = public.providers.codex.default_cmd
      .. " "
      .. tostring(public.providers.grok.api_key)
      .. " "
      .. tostring(public.password)
  end
  assert_equal(encoded:find("legacy-key", 1, true), nil)
  assert_equal(encoded:find("should-not-appear", 1, true), nil)
  assert_equal(encoded:find("secret-value", 1, true), nil)
  assert_equal(encoded:find("oauth-secret", 1, true), nil)
  assert_equal(encoded:find("top-secret", 1, true), nil)
end

do
  assert_true(type(health.public_config(nil)) == "table")
  assert_equal(next(health.public_config("nope")), nil)
end

print("health_public_config_spec.lua: ok")
