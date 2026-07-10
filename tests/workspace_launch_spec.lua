local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_contains = h.assert_contains

local workspace_launch = require("codux.workspace_launch")

assert_equal(workspace_launch.lua_string('hello "codux"'), '"hello \\"codux\\""')
assert_equal(workspace_launch.lua_string("hello\ncodux"), '"hello\\ncodux"')
assert_equal(workspace_launch.shell_env_assignment("CODEX_CMD", "codex -s workspace-write"), "CODEX_CMD='codex -s workspace-write'")

do
  local lua = workspace_launch.bootstrap_lua({
    name = "mission-builder",
    safe_name = "mission-builder",
    project_root = "/codux-worktrees/mission-builder",
    mission_id = "mission:mission",
    mission_name = "Mission",
    mission_role = "Builder",
    mission_objective = "Build it",
    mission_focus_packet = "Focus packet",
    nvim_server = "/tmp/codux/mission-builder.sock",
    initial_mode = "plan",
  })

  assert_contains(lua, 'mission_id="mission:mission"')
  assert_contains(lua, 'mission_name="Mission"')
  assert_contains(lua, 'mission_role="Builder"')
  assert_contains(lua, 'mission_objective="Build it"')
  assert_contains(lua, 'mission_focus_packet="Focus packet"')
  assert_contains(lua, 'nvim_server="/tmp/codux/mission-builder.sock"')
  assert_contains(lua, 'initial_mode="plan"')
end

do
  local lua = workspace_launch.bootstrap_lua({
    name = "grok-review",
    safe_name = "grok-review",
    project_root = "/repo",
    agent_provider = "grok",
    codex_session_id = "codex-session",
    codex_session_path = "/codex/session.jsonl",
    codex_session_captured_at = "2026-07-09T12:00:00Z",
  })

  assert_contains(lua, 'agent_provider="grok"')
  assert_contains(lua, 'agent_session_id=""')
  assert_contains(lua, 'agent_session_path=""')
  assert_contains(lua, 'agent_session_captured_at=""')
  assert_contains(lua, "resume_agent_session=false")
end

do
  local lua = workspace_launch.bootstrap_lua({
    name = "grok-review",
    safe_name = "grok-review",
    project_root = "/repo",
    agent_provider = "grok",
    resume_agent_session = true,
  })

  assert_contains(lua, "resume_agent_session=true")
end

do
  local runtime = {
    command_util = {
      shell = function(value)
        return value
      end,
    },
    get_config = function()
      return {
        codex_cmd = "codex -s workspace-write",
        workspace_auto_cmd = "codex -a auto",
        danger_full_access_cmd = "codex -a never",
      }
    end,
    nvim_cmd = function()
      return "nvim"
    end,
    workspace_server_path = function()
      return "/tmp/codux/review.sock"
    end,
  }

  local command = workspace_launch.nvim_command(runtime, {
    project_root = "/repo",
    safe_name = "review",
    target_path = "/repo/file.lua",
    target_type = "file",
  })

  assert_contains(command, "cd '/repo' && env")
  assert_contains(command, "CODEX_CMD='codex -s workspace-write'")
  assert_contains(command, "'nvim' --listen '/tmp/codux/review.sock' '/repo/file.lua'")
  assert_contains(command, "-c 'lua local root=")
end

do
  local runtime = {
    command_util = {
      shell = function(value)
        return value
      end,
    },
    get_config = function()
      return {
        providers = {
          codex = {
            default_cmd = "nested-codex",
            auto_cmd = "nested-codex-auto",
            danger_cmd = "nested-codex-danger",
          },
          grok = {
            default_cmd = "nested-grok",
            auto_cmd = "nested-grok-auto",
            danger_cmd = "nested-grok-danger",
          },
        },
      }
    end,
    nvim_cmd = function()
      return "nvim"
    end,
    workspace_server_path = function()
      return "/tmp/codux/review.sock"
    end,
  }

  local command = workspace_launch.nvim_command(runtime, {
    project_root = "/repo",
    safe_name = "review",
    target_path = "/repo",
    target_type = "directory",
  })

  assert_contains(command, "CODEX_CMD='nested-codex'")
  assert_contains(command, "CODEX_WORKSPACE_AUTO_CMD='nested-codex-auto'")
  assert_contains(command, "CODEX_DANGER_FULL_ACCESS_CMD='nested-codex-danger'")
  assert_contains(command, "GROK_CMD='nested-grok'")
  assert_contains(command, "GROK_WORKSPACE_AUTO_CMD='nested-grok-auto'")
  assert_contains(command, "GROK_DANGER_FULL_ACCESS_CMD='nested-grok-danger'")
end

do
  local runtime = {
    command_util = {
      shell = function(value)
        return value
      end,
    },
    get_config = function()
      return {
        codex_cmd = "codex",
        workspace_auto_cmd = "codex-auto",
        danger_full_access_cmd = "codex-danger",
      }
    end,
    nvim_cmd = function()
      return "nvim"
    end,
    workspace_server_path = function()
      return "/tmp/codux/review.sock"
    end,
  }

  local command = workspace_launch.nvim_command(runtime, {
    project_root = "/repo",
    safe_name = "review",
    target_path = "/repo",
    target_type = "directory",
    launch_script = "/tmp/codux/review.lua",
    initial_prompt = string.rep("x", 1000),
  })

  assert_contains(command, "'nvim' --listen '/tmp/codux/review.sock' '.'")
  assert_contains(command, "-c 'luafile /tmp/codux/review.lua'")
  assert_equal(command:find(string.rep("x", 1000), 1, true), nil)
end

print("workspace_launch_spec.lua: ok")
