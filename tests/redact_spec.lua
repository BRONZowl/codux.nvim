local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local redact = require("codux.redact")

do
  assert_true(redact.is_secret_key("api_key"))
  assert_true(redact.is_secret_key("OPENAI_API_KEY"))
  assert_true(redact.is_secret_key("client_secret"))
  assert_false(redact.is_secret_key("token_monitor"))
  assert_false(redact.is_secret_key("default_cmd"))
end

do
  assert_equal(redact.redact_command_value("codex -s workspace-write --api-key sk-test"), "codex")
  assert_equal(redact.redact_command_value({ "codex-danger", "--flag" }), "codex-danger")
end

do
  local text = "Authorization: Bearer abc.def-123 and sk-supersecretvalue and ghp_abcdefghijklmnop"
  local redacted = redact.redact_text(text)
  assert_equal(redacted:find("abc.def-123", 1, true), nil)
  assert_equal(redacted:find("sk-supersecretvalue", 1, true), nil)
  assert_equal(redacted:find("ghp_abcdefghijklmnop", 1, true), nil)
  assert_contains(redacted, "[REDACTED]")
  assert_contains(redacted, "Bearer")
end

do
  local text = "OPENAI_API_KEY=sk-live-xyz and normal code"
  local redacted = redact.redact_text(text)
  assert_contains(redacted, "OPENAI_API_KEY=[REDACTED]")
  assert_contains(redacted, "normal code")
end

do
  assert_true(redact.contains_secret_value("codex --api-key sk-abc123def"))
  assert_false(redact.contains_secret_value("codex -s workspace-write -a on-request"))
end

do
  local public = redact.public_config({
    providers = {
      codex = { default_cmd = "codex --api-key sk-hidden" },
      grok = { default_cmd = "grok", api_key = "drop-me" },
    },
    security = { scrub_prompts = true },
  })
  assert_equal(public.providers.codex.default_cmd, "codex")
  assert_nil(public.providers.grok.api_key)
  assert_equal(public.security.scrub_prompts, true)
end

do
  assert_false(redact.scrub_prompts_enabled({}))
  assert_false(redact.scrub_prompts_enabled({ security = { scrub_prompts = false } }))
  assert_true(redact.scrub_prompts_enabled({ security = { scrub_prompts = true } }))
  assert_equal(redact.maybe_scrub_prompt("sk-abc123token", {}), "sk-abc123token")
  assert_equal(redact.maybe_scrub_prompt("sk-abc123token", { security = { scrub_prompts = true } }), "[REDACTED]")
end

do
  local findings = redact.provider_commands_with_secrets({
    providers = {
      codex = { default_cmd = "codex --api-key sk-should-flag" },
      grok = { default_cmd = "grok --sandbox workspace" },
    },
  })
  assert_equal(#findings, 1)
  assert_equal(findings[1].label, "codex.default_cmd")
  assert_equal(findings[1].sample:find("sk-should-flag", 1, true), nil)
end

do
  local health = require("codux.health")
  h.with_stubs({
    {
      target = vim.fn,
      key = "executable",
      value = function()
        return 0
      end,
    },
  }, function()
    local lines = health.doctor_lines({
      config = {
        providers = {
          codex = { default_cmd = "codex --api-key sk-doctor-test" },
          grok = { default_cmd = "grok" },
        },
      },
      tmux_cmd = function()
        return "tmux"
      end,
    })
    local joined = table.concat(lines, "\n")
    assert_contains(joined, "provider command may embed a secret")
    assert_equal(joined:find("sk-doctor-test", 1, true), nil)
  end)
end

print("redact_spec.lua: ok")
