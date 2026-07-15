local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true
local assert_contains = h.assert_contains

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

do
  local nested_config = {
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

  assert_equal(providers.command(nested_config, "codex", "default"), "nested-default")
  assert_equal(providers.command(nested_config, "codex", "auto"), "nested-auto")
  assert_equal(providers.command(nested_config, "codex", "danger"), "nested-danger")
  assert_equal(nested_config.providers.codex.default_cmd, "nested-default")
end

do
  local provider_choices = providers.provider_choices()
  assert_equal(provider_choices[1].key, "g")
  assert_equal(provider_choices[1].agent_provider, "grok")
  assert_equal(provider_choices[2].key, "c")
  assert_equal(provider_choices[2].agent_provider, "codex")

  local profile_choices = providers.keyed_permission_profile_choices("profile_label")
  assert_equal(profile_choices[1].label, "Codex Default")
  assert_equal(profile_choices[4].label, "Grok Default")
  assert_equal(profile_choices[5].key, "G")
  assert_equal(profile_choices[5].agent_provider, "grok")
  assert_equal(profile_choices[5].profile, "auto")

  local grok_profiles = providers.keyed_permission_profile_choices_for_provider("grok")
  assert_equal(grok_profiles[1].key, "d")
  assert_equal(grok_profiles[1].label, "default")
  assert_equal(grok_profiles[1].agent_provider, "grok")
  assert_equal(grok_profiles[2].profile, "auto")
  assert_equal(grok_profiles[3].key, "f")
  assert_equal(grok_profiles[3].label, "full")
  assert_equal(grok_profiles[3].profile, "danger")
end

-- Legacy inline text still works when no instruction file is provided.
assert_equal(
  providers.command_with_instructions("grok", "grok", "Use repo rules."),
  "grok '--rules' 'Use repo rules.'"
)
-- Prefer file path: full instruction body never appears on argv.
do
  local with_file = providers.command_with_instructions("grok", "grok", "SECRET_RULES_BODY", {
    instruction_file = "/repo/.agents/codux/builder.md",
  })
  assert_contains(with_file, "/repo/.agents/codux/builder.md")
  assert_equal(with_file:find("SECRET_RULES_BODY", 1, true), nil)
  assert_contains(with_file, "--rules")
end
assert_equal(providers.command_with_prompt("grok", "grok", "hello"), "grok")
-- Prompts are never put on argv for any provider (paste after TUI ready).
assert_true(providers.prompt_must_be_pasted("codex"))
assert_true(providers.prompt_must_be_pasted("grok"))
assert_true(providers.prompt_must_be_pasted(nil))
assert_equal(providers.command_with_resume("grok", "grok"), "grok '--resume'")
assert_equal(providers.command_with_resume("grok", "grok", "session-1"), "grok '--resume' 'session-1'")

do
  local command = providers.workspace_command(config, {
    agent_provider = "grok",
    permission_profile = "auto",
    resolved_instruction = "Mission rules SECRET",
    instruction_file = "/repo/.agents/codux/role.md",
  }, "start now")
  assert_contains(command, "grok --sandbox workspace --always-approve")
  assert_contains(command, "/repo/.agents/codux/role.md")
  assert_equal(command:find("Mission rules SECRET", 1, true), nil)
end
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
  "grok --sandbox workspace"
)
assert_equal(
  providers.workspace_command(config, {
    agent_provider = "grok",
    permission_profile = "default",
    resume_agent_session = true,
    agent_session_id = "",
  }),
  "grok --sandbox workspace"
)
assert_equal(
  providers.workspace_command(config, {
    agent_provider = "grok",
    permission_profile = "default",
    resolved_instruction = "Mission rules",
    resume_agent_session = true,
  }),
  "grok --sandbox workspace '--rules' 'Mission rules'"
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
    agent_session_id = "codex-session",
  }),
  "codex-default 'resume' 'codex-session'"
)

print("providers_spec.lua: ok")
