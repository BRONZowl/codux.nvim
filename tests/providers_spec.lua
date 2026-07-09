local h = require("tests.helpers")
local assert_equal = h.assert_equal

local providers = require("codux.providers")

local config = {
  codex_cmd = "codex-default",
  workspace_auto_cmd = "codex-auto",
  danger_full_access_cmd = "codex-danger",
  providers = {
    grok = {
      default_cmd = "grok --sandbox workspace",
      auto_cmd = "grok --sandbox workspace --always-approve",
      danger_cmd = "grok --sandbox off --always-approve",
    },
  },
}

assert_equal(providers.command(config, "codex", "default"), "codex-default")
assert_equal(providers.command(config, "codex", "auto"), "codex-auto")
assert_equal(providers.command(config, "grok", "default"), "grok --sandbox workspace")
assert_equal(providers.command(config, "grok", "danger"), "grok --sandbox off --always-approve")

assert_equal(
  providers.command_with_instructions("grok", "grok", "Use repo rules."),
  "grok '--rules' 'Use repo rules.'"
)
assert_equal(providers.command_with_prompt("grok", "grok", "hello"), "grok")
assert_equal(providers.command_with_session_id("grok", "grok", "session-1"), "grok '--session-id' 'session-1'")
assert_equal(providers.command_with_resume("grok", "grok", "session-1"), "grok '--resume' 'session-1'")

print("providers_spec.lua: ok")
