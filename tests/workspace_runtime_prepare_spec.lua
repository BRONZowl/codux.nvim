local h = require("tests.helpers")
local fixtures = require("tests.workspace_fixtures")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local runtime_mod = require("codux.workspace_runtime")
local mission_mod = require("codux.mission")
local workspace_ui = require("codux.workspace_ui")

local runtime_with_tmux = fixtures.runtime_with_tmux
local review_workspace_record = fixtures.review_workspace_record
local workspace_state = fixtures.workspace_state
local default_workspace_config = fixtures.default_workspace_config
local default_workspace_from_state = fixtures.default_workspace_from_state
local default_state_record = fixtures.default_state_record
local project_state = fixtures.project_state
local with_filereadable = fixtures.with_filereadable
local with_workspace_prepare_env = fixtures.with_workspace_prepare_env
local workspace_prepare_runtime = fixtures.workspace_prepare_runtime
local workspace_store = fixtures.workspace_store
local prepare_harness = fixtures.prepare_harness
local mission_builder_prepare_harness = fixtures.mission_builder_prepare_harness
local mission_builder_prepare_opts = fixtures.mission_builder_prepare_opts
do
  with_workspace_prepare_env(function()
    local created = false
    local harness = prepare_harness({
      system = function(_, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("remote_workspace_status", 1, true) then
          return "ready\n", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime
    local store = harness.store

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(error_message)
    assert_equal(workspace.project_root, "/codux-worktrees/review")
    assert_equal(workspace.workspace_kind, "worktree")
    assert_equal(workspace.worktree_branch, "dev/review")
    assert_equal(workspace.worktree_base, "main")
    assert_equal(workspace.worktree_base_commit, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    assert_equal(workspace.git_common_dir, "/repo/.git")
    assert_equal(workspace.target_path, "/codux-worktrees/review/file.lua")
    assert_contains(harness.command_text(), "git -C /repo status --porcelain")
    assert_contains(harness.command_text(), "git -C /repo worktree add -b dev/review /codux-worktrees/review main")
    assert_equal(store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
    assert_equal(
      store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_base_commit,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    )
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local harness = prepare_harness({
      system = function(_, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/mission-builder main" then
          return "", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\tmission-builder\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("remote_workspace_status", 1, true) then
          return "ready\n", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime
    local store = harness.store

    local workspace, error_message = runtime:prepare_workspace("mission-builder", {
      resolved_instruction = "builder instructions",
      initial_prompt = "start building",
      initial_mode = "plan",
      permission_profile = "auto",
      mission_id = "mission:mission",
      mission_name = "Mission",
      mission_role = "Builder",
      mission_objective = "Build it",
    })
    assert_nil(error_message)
    assert_equal(workspace.permission_profile, "auto")
    assert_equal(workspace.status, "active")
    assert_equal(workspace.agent_status, "working")
    assert_equal(harness.command_text():find("start building", 1, true), nil)
    assert_contains(harness.command_text(), "-c 'luafile /tmp/codux/mission-builder.lua'")
    assert_contains(harness.launch_scripts["/tmp/codux/mission-builder.lua"], "start building")
    local record = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(record.permission_profile, "auto")
    assert_equal(record.mission_id, "mission:mission")
    assert_equal(record.mission_role, "Builder")
    assert_equal(record.mission_objective, "Build it")
  end)
end

do
  with_workspace_prepare_env(function()
    local harness, flags = mission_builder_prepare_harness()
    local runtime = harness.runtime
    local store = harness.store

    local workspace, error_message =
      runtime:prepare_workspace("mission-builder", mission_builder_prepare_opts({ initial_mode = "plan" }))

    assert_nil(error_message)
    assert_equal(workspace.safe_name, "mission-builder")
    assert_false(flags.killed)
    local record = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(record.initial_mode, "plan")
    assert_equal(record.permission_profile, "auto")
    assert_equal(record.mission_id, "mission:mission")
    assert_equal(record.agent_mode, "plan")
  end)
end

do
  with_workspace_prepare_env(function()
    local harness, flags = mission_builder_prepare_harness()
    local runtime = harness.runtime

    local workspace, error_message = runtime:prepare_workspace(
      "mission-builder",
      mission_builder_prepare_opts({
        initial_mode = "plan",
        require_codex_ready = true,
      })
    )

    assert_nil(workspace)
    assert_equal(error_message, "workspace agent session is not running")
    assert_true(flags.killed)
    assert_true(flags.removed_worktree)
    assert_true(flags.deleted_branch)
  end)
end

do
  with_workspace_prepare_env(function()
    local deleted_instruction = false
    local store = workspace_store({
      delete_instruction_file = function(_, root, safe_name)
        deleted_instruction = root == "/codux-worktrees/mission-builder" and safe_name == "mission-builder"
        return true, nil
      end,
    })
    local harness, flags = mission_builder_prepare_harness({
      store_instance = store,
      remote_status = false,
    })
    local runtime = harness.runtime

    local workspace, error_message = runtime:prepare_workspace("mission-builder", mission_builder_prepare_opts())

    assert_nil(workspace)
    assert_equal(error_message, "workspace is not reachable")
    assert_true(flags.killed)
    assert_true(deleted_instruction)
    assert_true(flags.removed_worktree)
    assert_true(flags.deleted_branch)
    assert_nil(store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"])
  end)
end

do
  with_workspace_prepare_env(function()
    local state_data = {
      projects = {
        ["/codux-worktrees/repo/mission-builder"] = {
          workspaces = {
            ["mission-builder"] = review_workspace_record({
              name = "mission-builder",
              safe_name = "mission-builder",
              project_root = "/codux-worktrees/repo/mission-builder",
              workspace_kind = "worktree",
            }),
          },
        },
      },
    }
    local harness = prepare_harness({
      store = {
        state_data = state_data,
      },
      system = function(_, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime
    local mission = assert(mission_mod.plan("Mission", "Build it", {
      roles = {
        { name = "Builder" },
      },
    }))

    local ok, error_message = runtime:preflight_mission(mission)
    assert_false(ok)
    assert_equal(error_message, "workspace already exists: mission-builder")
    assert_equal(harness.command_text():find("worktree add", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    h.with_stubs({
      {
        target = vim.fn,
        key = "isdirectory",
        value = function(path)
          return (path == "/repo" or path == "/codux-worktrees/repo/mission-builder") and 1 or 0
        end,
      },
    }, function()
      local harness = prepare_harness({
        system = function(_, command)
          if command == "tmux display-message -p #S" then
            return "session\n", 0
          end
          return "", 1
        end,
      })
      local runtime = harness.runtime
      local mission = assert(mission_mod.plan("Mission", "Build it", {
        roles = {
          { name = "Builder" },
        },
      }))

      local ok, error_message = runtime:preflight_mission(mission)
      assert_false(ok)
      assert_equal(error_message, "worktree path already exists: /codux-worktrees/repo/mission-builder")
      assert_equal(harness.command_text():find("worktree add", 1, true), nil)
    end)
  end)
end

do
  with_workspace_prepare_env(function()
    local windows = {}
    local next_window_id = 1
    local harness = prepare_harness({
      store = {
        instruction_file_path = function(_, root, safe_name)
          return root .. "/.agents/codux/" .. safe_name .. ".md"
        end,
      },
      system = function(_, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          local lines = {}
          for name, id in pairs(windows) do
            table.insert(lines, id .. "\t" .. name)
          end
          table.sort(lines)
          return table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""), 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-manager" then
          return "", 1
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-architect" then
          return "", 1
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/mission-manager /codux-worktrees/repo/mission-manager main" then
          return "", 0
        end
        if command == "git -C /repo worktree add -b dev/mission-architect /codux-worktrees/repo/mission-architect main" then
          return "", 0
        end
        if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/repo/mission-builder main" then
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          local name = command:find("mission%-manager") and "mission-manager"
            or command:find("mission%-architect") and "mission-architect"
            or "mission-builder"
          windows[name] = "@" .. tostring(next_window_id)
          next_window_id = next_window_id + 1
          return "", 0
        end
        if command:match("tmux list%-panes %-t @%d+ %-F") then
          return "nvim\n", 0
        end
        if command:find("remote_workspace_status", 1, true) then
          return "ready\n", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime
    local store = harness.store

    local mission, error_message = mission_mod.plan("Mission", "Build it", {
      roles = {
        { name = "Architect", safe_name = "architect", focus = "Design it" },
        { name = "Builder", safe_name = "builder", focus = "Build it" },
      },
    })
    assert_nil(error_message)
    mission.permission_profile = "danger"
    local preflight_ok, preflight_error, role_specs = runtime:preflight_mission(mission)
    assert_true(preflight_ok)
    assert_nil(preflight_error)
    assert_equal(#role_specs, 3, "Manager is always first in the mission crew")
    assert_equal(role_specs[1].safe_name, "mission-manager")
    assert_equal(role_specs[1].worktree_path, "/codux-worktrees/repo/mission-manager")
    assert_equal(role_specs[2].safe_name, "mission-architect")
    assert_equal(role_specs[2].worktree_path, "/codux-worktrees/repo/mission-architect")
    assert_equal(role_specs[3].safe_name, "mission-builder")
    assert_equal(role_specs[3].worktree_path, "/codux-worktrees/repo/mission-builder")
    assert_true(runtime:create_mission(mission))

    local manager = store.state_data().projects["/codux-worktrees/repo/mission-manager"].workspaces["mission-manager"]
    local architect =
      store.state_data().projects["/codux-worktrees/repo/mission-architect"].workspaces["mission-architect"]
    local builder = store.state_data().projects["/codux-worktrees/repo/mission-builder"].workspaces["mission-builder"]
    assert_equal(manager.permission_profile, "danger")
    assert_equal(manager.mission_role, "Manager")
    assert_equal(architect.permission_profile, "danger")
    assert_equal(builder.permission_profile, "danger")
    assert_equal(architect.mission_id, "mission:mission")
    assert_equal(builder.mission_id, "mission:mission")
    assert_equal(architect.mission_role, "Architect")
    assert_equal(builder.mission_role, "Builder")
    assert_equal(architect.project_root, "/codux-worktrees/repo/mission-architect")
    assert_equal(builder.project_root, "/codux-worktrees/repo/mission-builder")
    assert_equal(architect.worktree_path, "/codux-worktrees/repo/mission-architect")
    assert_equal(builder.worktree_path, "/codux-worktrees/repo/mission-builder")
    assert_equal(architect.target_path, "/codux-worktrees/repo/mission-architect/file.lua")
    assert_equal(builder.target_path, "/codux-worktrees/repo/mission-builder/file.lua")
    assert_equal(architect.mission_objective, "Build it")
    assert_equal(builder.mission_objective, "Build it")
    assert_contains(architect.mission_focus_packet, "# Mission Focus Packet")
    assert_contains(builder.mission_focus_packet, "# Mission Focus Packet")
    assert_equal(architect.initial_mode, "plan")
    assert_equal(builder.initial_mode, "plan")
    assert_equal(architect.agent_status, "working")
    assert_equal(builder.agent_status, "working")
    assert_equal(architect.agent_mode, "plan")
    assert_equal(builder.agent_mode, "plan")
    local missions = runtime:missions_for_project("/repo")
    assert_equal(#missions, 1)
    assert_equal(missions[1].name, "Mission")
    assert_equal(#missions[1].roles, 3)
    assert_contains(harness.command_text(), "git -C /repo status --porcelain")
    assert_contains(harness.command_text(), "--listen")
    assert_equal(harness.command_text():find("Start your Mission Control role now.", 1, true), nil)
    assert_contains(harness.launch_scripts["/tmp/codux/mission-manager.lua"], "Mission Focus Packet:")
    assert_contains(harness.launch_scripts["/tmp/codux/mission-manager.lua"], "outline worker handoffs")
    assert_contains(harness.launch_scripts["/tmp/codux/mission-builder.lua"], "Mission Focus Packet:")
    assert_contains(harness.launch_scripts["/tmp/codux/mission-architect.lua"], "Start your Mission Control role now.")
    assert_contains(harness.launch_scripts["/tmp/codux/mission-builder.lua"], "Start your Mission Control role now.")
  end)
end

do
  with_workspace_prepare_env(function()
    local windows = {}
    local harness = prepare_harness({
      system = function(_, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          local lines = {}
          for name, id in pairs(windows) do
            table.insert(lines, id .. "\t" .. name)
          end
          return table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""), 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/long-manager" then
          return "", 1
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/long-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/long-manager /codux-worktrees/repo/long-manager main" then
          return "", 0
        end
        if command == "git -C /repo worktree add -b dev/long-builder /codux-worktrees/repo/long-builder main" then
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          local name = command:find("long%-manager") and "long-manager" or "long-builder"
          windows[name] = "@" .. tostring((name == "long-manager") and 1 or 2)
          if #command > 5000 then
            return "command too long\n", 1
          end
          return "", 0
        end
        if command:match("tmux list%-panes %-t @%d+ %-F") then
          return "nvim\n", 0
        end
        if command:find("remote_workspace_status", 1, true) then
          return "ready\n", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime
    local objective = string.rep("ship this mission ", 1000)
    local normalized_objective = objective:gsub("%s+$", "")
    local mission, error_message = mission_mod.plan("Long", objective, {
      roles = {
        { name = "Builder", safe_name = "builder", focus = "Build it" },
      },
    })
    assert_nil(error_message)

    assert_true(runtime:create_mission(mission))
    assert_contains(harness.command_text(), "-c 'luafile /tmp/codux/long-manager.lua'")
    assert_contains(harness.command_text(), "-c 'luafile /tmp/codux/long-builder.lua'")
    assert_equal(harness.command_text():find(normalized_objective, 1, true), nil)
    assert_contains(harness.launch_scripts["/tmp/codux/long-builder.lua"], normalized_objective)
    assert_contains(harness.launch_scripts["/tmp/codux/long-manager.lua"], normalized_objective)
  end)
end

do
  with_workspace_prepare_env(function()
    local written = {}
    local notifications = {}
    local state_data = workspace_state({
      ["mission-architect"] = review_workspace_record({
        name = "mission-architect",
        safe_name = "mission-architect",
        mission_id = "mission:mission",
        mission_name = "Mission",
        mission_role = "Architect",
        mission_objective = "Build it",
        resolved_instruction = mission_mod.role_instruction("Mission", "Build it", {
          name = "Architect",
          safe_name = "architect",
          focus = "Design it",
        }),
      }),
      ["mission-builder"] = review_workspace_record({
        name = "mission-builder",
        safe_name = "mission-builder",
        mission_id = "mission:mission",
        mission_name = "Mission",
        mission_role = "Builder",
        mission_objective = "Build it",
        resolved_instruction = mission_mod.role_instruction("Mission", "Build it", {
          name = "Builder",
          safe_name = "builder",
          focus = "Build it",
        }),
      }),
    })
    local store = workspace_store({
      state_data = state_data,
      write_instruction_file = function(_, root, safe_name, instruction)
        written[root .. "/" .. safe_name] = instruction
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      notify = function(message)
        table.insert(notifications, message)
      end,
    })

    local ok, error_message = runtime:update_mission_objective("Mission", "Ship the dashboard")
    assert_nil(error_message)
    assert_true(ok)
    local architect = store.state_data().projects["/repo"].workspaces["mission-architect"]
    local builder = store.state_data().projects["/repo"].workspaces["mission-builder"]
    assert_equal(architect.mission_objective, "Ship the dashboard")
    assert_equal(builder.mission_objective, "Ship the dashboard")
    assert_contains(architect.resolved_instruction, "Ship the dashboard")
    assert_contains(builder.resolved_instruction, "Ship the dashboard")
    assert_contains(written["/repo/mission-architect"], "Mission: Mission")
    assert_contains(written["/repo/mission-builder"], "Role focus:")
    assert_contains(notifications[#notifications], "Updated Codux mission Mission objective for 2 roles")
  end)
end

do
  with_workspace_prepare_env(function()
    local runtime = workspace_prepare_runtime({
      store = workspace_store().store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:preflight_mission({
      roles = {
        { workspace_name = "mission-role!" },
        { workspace_name = "mission-role@" },
      },
    })
    assert_false(ok)
    assert_equal(error_message, "Duplicate mission workspace: mission-role")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local harness = prepare_harness({
      system = function(_, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
          return "", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1" then
          return "", 1
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1/review" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev1/review /codux-worktrees/review main" then
          return "", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime
    local store = harness.store

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(error_message)
    assert_equal(workspace.worktree_branch, "dev1/review")
    assert_contains(harness.command_text(), "git -C /repo worktree add -b dev1/review /codux-worktrees/review main")
    assert_equal(store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev1/review")
  end)
end

do
  with_workspace_prepare_env(function()
    local harness = prepare_harness({
      system = function(_, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo status --porcelain" then
          return " M file.lua\n", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_equal(error_message, "current branch must be clean before creating a Codux workspace")
    assert_equal(harness.command_text():find("worktree add", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local created_window = false
    local removed_worktree = false
    local deleted_branch = false
    local harness = prepare_harness({
      write_launch_script = function()
        return nil, "launch script failed"
      end,
      system = function(_, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/review /codux-worktrees/review main" then
          return "", 0
        end
        if command == "git -C /repo worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git -C /repo branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created_window = true
          return "", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_equal(error_message, "launch script failed")
    assert_false(created_window, "tmux window should not be created when launch script write fails")
    assert_true(removed_worktree, "git worktree should be removed when launch script write fails")
    assert_true(deleted_branch, "git branch should be deleted when launch script write fails")
  end)
end

do
  with_workspace_prepare_env(function()
    local wrote_instruction = false
    local store = workspace_store({
      read_instruction_file = function()
        return nil
      end,
      write_instruction_file = function()
        wrote_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          return "command too long\n", 1
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_contains(error_message, "Failed to create tmux window")
    assert_contains(error_message, "command too long")
    assert_false(wrote_instruction, "instruction file should not be written when tmux creation fails")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local killed = false
    local deleted_instruction = false
    local removed_worktree = false
    local deleted_branch = false
    local store = workspace_store({
      write_state = function()
        return false, "state write failed"
      end,
      read_instruction_file = function()
        return nil
      end,
      delete_instruction_file = function()
        deleted_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command == "tmux kill-window -t @1" then
          killed = true
          return "", 0
        end
        if command == "git -C /repo worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git -C /repo branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_equal(error_message, "state write failed")
    assert_true(killed, "new tmux window should be cleaned up when state write fails")
    assert_true(deleted_instruction, "new instruction file should be cleaned up when state write fails")
    assert_true(removed_worktree, "new git worktree should be cleaned up when state write fails")
    assert_true(deleted_branch, "new git branch should be cleaned up when state write fails")
  end)
end

do
  with_workspace_prepare_env(function()
    local created_window = false
    local wrote_instruction = false
    local wrote_state = false
    local store = workspace_store({
      write_state = function()
        wrote_state = true
        return true, nil
      end,
      read_instruction_file = function()
        return "existing instructions"
      end,
      write_instruction_file = function()
        wrote_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created_window = true
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "new instructions",
    })
    assert_nil(workspace)
    assert_equal(error_message, "workspace already exists")
    assert_false(created_window, "duplicate instruction-only workspace should not create tmux window")
    assert_false(wrote_instruction, "duplicate instruction-only workspace should not write instruction file")
    assert_false(wrote_state, "duplicate instruction-only workspace should not write state")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local store = workspace_store({
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
    })
    assert_nil(error_message)
    assert_equal(workspace.safe_name, "review")
    assert_equal(workspace.resolved_instruction, "existing instructions")
    assert_false(workspace.open_visible)
    assert_equal(store.state_data().projects["/repo"].workspaces.review.resolved_instruction, "existing instructions")
  end)
end

do
  with_workspace_prepare_env(function()
    local target_path, target_type = runtime_mod.normalize_workspace_target("/repo", "directory", "/fallback")
    assert_equal(target_path, "/repo")
    assert_equal(target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local killed = false
    local created = false
    local harness = prepare_harness({
      store = {
        state_data = workspace_state({
          review = review_workspace_record({
            nvim_server = "/tmp/stale-review.sock",
          }),
        }),
        read_instruction_file = function()
          return "existing instructions"
        end,
      },
      system = function(_, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@2\treview\n", 0
          end
          if not killed then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "bash\n", 0
        end
        if command == "tmux kill-window -t @1" then
          killed = true
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @2 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
      restart_inactive = true,
    })
    assert_nil(error_message)
    assert_equal(workspace.window_id, "@2")
    assert_contains(workspace.nvim_server, "/codux/ws-review-repo-")
    assert_true(killed)
    assert_true(created)
    local command_text = harness.command_text()
    assert_contains(command_text, "tmux kill-window -t @1")
    assert_contains(command_text, "--listen")
    assert_contains(command_text, workspace.nvim_server)
    assert_equal(command_text:find("/tmp/stale-review.sock", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    assert_false(runtime_mod.target_path_exists("health://"))
    assert_false(runtime_mod.target_path_exists("codux://codex"))
    assert_false(runtime_mod.target_path_exists("term://terminal"))

    local target_path, target_type = runtime_mod.normalize_workspace_target("health://", "file", "/repo")
    assert_equal(target_path, "/repo")
    assert_equal(target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local runtime = workspace_prepare_runtime({
      current_target = function()
        return { path = "health://", type = "file" }
      end,
      current_buffer_name = function()
        return "health://"
      end,
      git_root_for = function(path)
        assert_equal(path, "/repo")
        return "/repo"
      end,
      git_branch_for = function(path)
        assert_equal(path, "/repo")
        return "main"
      end,
    })

    local context = runtime:target_context()
    assert_nil(context.path)
    assert_equal(context.directory, "/repo")
    assert_equal(context.root, "/repo")
    assert_equal(context.branch, "main")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local new_window_command
    local launch_script
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record({
          resolved_instruction = "existing instructions",
          target_path = "/repo/neo-tree filesystem [1]",
          target_type = "file",
          initial_mode = "execute",
        }),
      }),
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          new_window_command = command
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })
    runtime.write_launch_script = function(rt, workspace)
      launch_script = rt:bootstrap_lua(workspace)
      return "/tmp/codux/review.lua", nil
    end

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
      initial_mode = "plan",
    })
    assert_nil(error_message)
    assert_equal(workspace.initial_mode, "plan")
    assert_equal(workspace.target_path, "/repo")
    assert_equal(workspace.target_type, "directory")
    assert_contains(new_window_command, "'nvim' --listen")
    assert_contains(new_window_command, "-c 'luafile /tmp/codux/review.lua'")
    assert_contains(launch_script, 'initial_mode="plan"')
    assert_contains(new_window_command, "/codux/ws-review-repo-")
    assert_contains(new_window_command, "' '.'")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.initial_mode, "plan")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_path, "/repo")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record({
          target_path = "/repo/file.lua",
          target_type = "file",
        }),
      }),
    })
    local runtime = workspace_prepare_runtime({
      state = {
        workspace = {
          project_root = "/repo",
          safe_name = "review",
          target_path = "/repo/file.lua",
          target_type = "file",
          git_branch = "main",
        },
      },
      store = store.store,
      current_target = function()
        return nil
      end,
      current_buffer_name = function()
        return "/repo/neo-tree filesystem [1]"
      end,
    })

    assert_true(runtime:sync_target("BufEnter", function()
      return "neo-tree"
    end))
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_path, "/repo")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_type, "directory")
    assert_equal(runtime.state.workspace.target_path, "/repo")
    assert_equal(runtime.state.workspace.target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local new_window_command
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record({
          resolved_instruction = "existing instructions",
          target_path = "/repo/file.lua",
          target_type = "file",
        }),
      }),
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          new_window_command = command
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
    })
    assert_nil(error_message)
    assert_equal(workspace.target_path, "/repo/file.lua")
    assert_equal(workspace.target_type, "file")
    assert_contains(new_window_command, "'nvim' --listen")
    assert_contains(new_window_command, "/codux/ws-review-repo-")
    assert_contains(new_window_command, "' '/repo/file.lua'")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_path, "/repo/file.lua")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_type, "file")
  end)
end

print("workspace_runtime_spec.lua: ok")

print("workspace_runtime_prepare_spec.lua: ok")
