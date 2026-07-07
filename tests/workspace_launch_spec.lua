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
