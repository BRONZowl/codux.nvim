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
  -- Multi-line prompt with env + bearer mixed into code review context.
  local multi = table.concat({
    "Review this .env snippet:",
    "OPENAI_API_KEY=sk-multiline-secret-value",
    "XAI_API_KEY: \"xai-another-secret-value\"",
    "Authorization: Bearer multi.line-token_value",
    "function ok() return 1 end",
  }, "\n")
  local redacted = redact.redact_text(multi)
  assert_equal(redacted:find("sk-multiline-secret-value", 1, true), nil)
  assert_equal(redacted:find("xai-another-secret-value", 1, true), nil)
  assert_equal(redacted:find("multi.line-token_value", 1, true), nil)
  assert_contains(redacted, "function ok() return 1 end")
  assert_contains(redacted, "Review this .env snippet:")
end

do
  -- Quoted env forms
  local redacted = redact.redact_text('export GITHUB_TOKEN="ghp_quotedtokenvalue12"')
  assert_equal(redacted:find("ghp_quotedtokenvalue12", 1, true), nil)
  assert_contains(redacted, "GITHUB_TOKEN")
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
    security = { scrub_prompts = true, audit_scrubs = true },
  })
  assert_equal(public.providers.codex.default_cmd, "codex")
  assert_nil(public.providers.grok.api_key)
  assert_equal(public.security.scrub_prompts, true)
  assert_equal(public.security.audit_scrubs, true)
end

do
  assert_false(redact.scrub_prompts_enabled({}))
  assert_false(redact.scrub_prompts_enabled({ security = { scrub_prompts = false } }))
  assert_true(redact.scrub_prompts_enabled({ security = { scrub_prompts = true } }))
  assert_equal(redact.maybe_scrub_prompt("sk-abc123token", {}), "sk-abc123token")
  assert_equal(redact.maybe_scrub_prompt("sk-abc123token", { security = { scrub_prompts = true } }), "[REDACTED]")
end

do
  redact.reset_audit_stats()
  local before = redact.audit_stats()
  assert_equal(before.text_calls, 0)
  assert_equal(before.text_redacted, 0)
  assert_equal(before.prompt_calls, 0)
  assert_equal(before.prompt_scrubbed, 0)
  assert_nil(before.text_redaction_rate)
  assert_nil(before.prompt_scrub_rate)
  assert_nil(before.session_started_at)
  assert_nil(before.last_redact_at)
  assert_nil(before.last_prompt_scrub_at)

  redact.redact_text("no secrets here")
  redact.redact_text("Bearer super.secret-token-value")
  -- Detection must not inflate counters.
  redact.contains_secret_value("sk-detectonlytoken")

  local mid = redact.audit_stats()
  assert_equal(mid.text_calls, 2)
  assert_equal(mid.text_redacted, 1)
  assert_equal(mid.text_redaction_rate, 50)
  assert_true(type(mid.session_started_at) == "number")
  assert_true(type(mid.last_redact_at) == "number")
  assert_nil(mid.last_prompt_scrub_at)

  local line_mid = redact.audit_summary_line({ security = { audit_scrubs = true } })
  assert_contains(line_mid, "text 1/2 (50%)")
  assert_contains(line_mid, "prompts 0/0")

  redact.maybe_scrub_prompt("sk-promptscrubtoken", { security = { scrub_prompts = false } })
  redact.maybe_scrub_prompt("sk-promptscrubtoken", { security = { scrub_prompts = true } })
  local after = redact.audit_stats()
  assert_equal(after.prompt_calls, 2)
  assert_equal(after.prompt_scrubbed, 1)
  assert_equal(after.prompt_scrub_rate, 50)
  -- Scrub path also runs redact_text (audited).
  assert_equal(after.text_calls, 3)
  assert_equal(after.text_redacted, 2)
  assert_equal(after.text_redaction_rate, 66)
  assert_true(type(after.last_prompt_scrub_at) == "number")

  assert_nil(redact.audit_summary_line({ security = { audit_scrubs = false } }))
  local line = redact.audit_summary_line({ security = { audit_scrubs = true } })
  assert_contains(line, "redact audit:")
  assert_contains(line, "text 2/3 (66%)")
  assert_contains(line, "prompts 1/2 (50%)")
end

do
  -- Known ratio flooring: 1 of 3 → 33%.
  redact.reset_audit_stats()
  redact.redact_text("clean")
  redact.redact_text("still clean")
  redact.redact_text("sk-onetokenvalue")
  local s = redact.audit_stats()
  assert_equal(s.text_calls, 3)
  assert_equal(s.text_redacted, 1)
  assert_equal(s.text_redaction_rate, 33)
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
