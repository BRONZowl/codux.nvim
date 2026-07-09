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
assert_equal(providers.command_with_resume("grok", "grok"), "grok '--resume'")
assert_equal(providers.command_with_resume("grok", "grok", "session-1"), "grok '--resume' 'session-1'")

assert_equal(
  providers.workspace_command(config, {
    agent_provider = "grok",
    permission_profile = "auto",
    resolved_instruction = "Mission rules",
  }, "start now"),
  "grok --sandbox workspace --always-approve '--rules' 'Mission rules'"
)
assert_equal(
  providers.workspace_command(config, {
    agent_provider = "grok",
    permission_profile = "auto",
    resolved_instruction = "Mission rules",
    agent_session_id = "generated-id",
  }, "start now"),
  "grok --sandbox workspace --always-approve '--rules' 'Mission rules'"
)
assert_equal(
  providers.workspace_command(config, {
    agent_provider = "grok",
    permission_profile = "default",
    resume_agent_session = true,
  }),
  "grok --sandbox workspace '--resume'"
)
assert_equal(
  providers.workspace_command(config, {
    agent_provider = "grok",
    permission_profile = "default",
    resume_agent_session = true,
    agent_session_id = "session-1",
  }),
  "grok --sandbox workspace '--resume' 'session-1'"
)
assert_equal(
  providers.workspace_command(config, {
    agent_provider = "codex",
    permission_profile = "default",
    codex_session_id = "codex-session",
  }),
  "codex-default 'resume' 'codex-session'"
)

print("providers_spec.lua: ok")
