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
local workspace_delete_runtime = fixtures.workspace_delete_runtime
local lifecycle_runtime = fixtures.lifecycle_runtime
local worktree_delete_state = fixtures.worktree_delete_state
local with_tmux_env = fixtures.with_tmux_env
do
  with_tmux_env("/tmp/tmux,1,0", function()
    local harness = lifecycle_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n@2\tdebug\n", 0
        end
        if command == "tmux kill-window -t @1" or command == "tmux kill-window -t @2" then
          return "", 0
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime

    assert_true(runtime:close_all_saved_workspace_windows("/repo"))
    assert_equal(harness.state_data().projects["/repo"].workspaces.review.status, "inactive")
    assert_equal(harness.state_data().projects["/repo"].workspaces.debug.status, "inactive")
    assert_nil(harness.state_data().projects["/repo"].workspaces.debug.agent_mode)
    assert_contains(harness.messages[#harness.messages], "Closed 2 Codux workspaces")
  end)
end

do
  with_tmux_env("/tmp/tmux,1,0", function()
    local harness = lifecycle_runtime({
      state = {
        workspace = {
          project_root = "/repo",
          safe_name = "debug",
          status = "active",
          agent_status = "working",
          agent_mode = "execute",
          tmux_target = "session:debug",
        },
      },
      notify = function() end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n@2\tdebug\n", 0
        end
        if command == "tmux kill-window -t @1" then
          return "", 0
        end
        if command == "tmux kill-window -t @2" then
          return "", 1
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime

    assert_false(runtime:close_all_saved_workspace_windows("/repo"))
    assert_equal(harness.state_data().projects["/repo"].workspaces.review.status, "inactive")
    assert_equal(harness.state_data().projects["/repo"].workspaces.debug.status, "active")
    assert_equal(harness.state_data().projects["/repo"].workspaces.debug.agent_status, "working")
    assert_equal(harness.state_data().projects["/repo"].workspaces.debug.agent_mode, "execute")
    assert_equal(runtime.state.workspace.status, "active")
    assert_equal(runtime.state.workspace.agent_status, "working")
    assert_equal(runtime.state.workspace.agent_mode, "execute")
    assert_equal(runtime.state.workspace.tmux_target, "session:debug")
  end)
end

do
  with_tmux_env("/tmp/tmux,1,0", function()
    local harness = lifecycle_runtime({
      state = {
        workspace = {
          project_root = "/repo",
          safe_name = "review",
          status = "idle",
          agent_status = "idle",
          agent_mode = "plan",
          tmux_target = "session:review",
        },
      },
      notify = function() end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n@2\tdebug\n", 0
        end
        if command == "tmux kill-window -t @1" then
          return "", 0
        end
        if command == "tmux kill-window -t @2" then
          return "", 1
        end
        return "", 1
      end,
    })
    local runtime = harness.runtime

    assert_false(runtime:close_all_saved_workspace_windows("/repo"))
    assert_equal(harness.state_data().projects["/repo"].workspaces.review.status, "inactive")
    assert_equal(harness.state_data().projects["/repo"].workspaces.debug.status, "active")
    assert_equal(runtime.state.workspace.status, "inactive")
    assert_equal(runtime.state.workspace.agent_status, "idle")
    assert_nil(runtime.state.workspace.agent_mode)
    assert_nil(runtime.state.workspace.tmux_target)
  end)
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            tmux_target = "session:review",
            status = "idle",
            agent_status = "idle",
          },
        },
      },
    },
  }
  local messages = {}
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = nil
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(messages, message)
    end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      return "", 1
    end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_true(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_nil(state_data.projects["/repo"].workspaces.debug.tmux_target)
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_window, "debug")
  assert_contains(messages[#messages], "Renamed Codux workspace to debug")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            tmux_target = "session:review",
            status = "inactive",
            agent_status = "idle",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function()
      return "", 1
    end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_true(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_name = "review",
  }, "debug"))
  assert_nil(state_data.projects["/repo"].workspaces.debug.tmux_target)
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_window, "debug")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "inactive")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            tmux_target = "session:review",
            status = "idle",
            agent_status = "idle",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      return "", 1
    end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_true(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_target, "session:debug")
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_window, "debug")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "idle")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "idle",
            agent_status = "idle",
          },
        },
      },
    },
  }
  local commands = {}
  local notification
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      notification = message
    end,
    system = function(args)
      local command = table.concat(args, " ")
      table.insert(commands, command)
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux rename-window -t @1 review" then
        return "", 0
      end
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function()
        return false, "write failed"
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_false(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_equal(state_data.projects["/repo"].workspaces.review.name, "review")
  assert_nil(state_data.projects["/repo"].workspaces.debug)
  assert_contains(table.concat(commands, "\n"), "tmux rename-window -t @1 debug")
  assert_contains(table.concat(commands, "\n"), "tmux rename-window -t @1 review")
  assert_equal(notification, "write failed")
end

do
  local state_data = {
    projects = {
      ["/codux-worktrees/review"] = {
        workspaces = {
          review = review_workspace_record({
            name = "review",
            safe_name = "review",
            project_root = "/codux-worktrees/review",
            tmux_window = "review",
            status = "idle",
            agent_status = "idle",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_path = "/codux-worktrees/review",
            worktree_branch = "dev/review",
            git_branch = "dev/review",
          }),
        },
      },
    },
  }
  local commands = {}
  local notification
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      notification = message
    end,
    system = function(args)
      local command = table.concat(args, " ")
      table.insert(commands, command)
      if command == "git -C /codux-worktrees/review show-ref --verify --quiet refs/heads/dev/debug" then
        return "", 1
      end
      if command == "git -C /codux-worktrees/review worktree move /codux-worktrees/review /codux-worktrees/debug" then
        return "", 0
      end
      if command == "git -C /codux-worktrees/debug branch -m dev/review dev/debug" then
        return "", 0
      end
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      if command == "tmux rename-window -t @1 review" then
        return "", 0
      end
      if command == "git -C /codux-worktrees/debug branch -m dev/debug dev/review" then
        return "", 0
      end
      if command == "git -C /codux-worktrees/debug worktree move /codux-worktrees/debug /codux-worktrees/review" then
        return "", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function()
        return false, "write failed"
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = project_state,
      instruction_file_path = function(_, root, safe_name)
        return root .. "/.agents/codux/" .. safe_name .. ".md"
      end,
    },
  })

  assert_false(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/codux-worktrees/review",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_equal(state_data.projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
  assert_nil(state_data.projects["/codux-worktrees/debug"])
  local command_text = table.concat(commands, "\n")
  assert_contains(command_text, "git -C /codux-worktrees/review worktree move /codux-worktrees/review /codux-worktrees/debug")
  assert_contains(command_text, "git -C /codux-worktrees/debug branch -m dev/debug dev/review")
  assert_contains(command_text, "git -C /codux-worktrees/debug worktree move /codux-worktrees/debug /codux-worktrees/review")
  assert_equal(notification, "write failed")
end

do
  with_tmux_env("/tmp/tmux,1,0", function()
  with_filereadable(0, function()
    local state_data = {
      projects = {
        ["/codux-worktrees/repo/alpha-builder"] = {
          workspaces = {
            ["alpha-builder"] = review_workspace_record({
              name = "alpha-builder",
              safe_name = "alpha-builder",
              project_root = "/codux-worktrees/repo/alpha-builder",
              tmux_window = "alpha-builder",
              tmux_target = "session:alpha-builder",
              status = "idle",
              agent_status = "idle",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/repo/alpha-builder",
              worktree_branch = "dev/alpha-builder",
              git_branch = "dev/alpha-builder",
              target_path = "/codux-worktrees/repo/alpha-builder/lua/init.lua",
              mission_id = "mission:alpha",
              mission_name = "Alpha",
              mission_role = "Builder",
              mission_objective = "Build it",
              resolved_instruction = table.concat({
                "You are the Builder for Codux Mission Control.",
                "",
                "Mission: Alpha",
                "",
                "Objective:",
                "Build it",
                "",
                "Role focus:",
                "Keep the implementation focused.",
                "",
                "Stay inside this workspace and keep your work scoped to this role. Coordinate through concise handoff notes when another role needs context.",
              }, "\n"),
            }),
          },
        },
      },
    }
    local commands = {}
    local written_instruction
    local runtime = runtime_mod.new({
      state = {
        workspace_manager_project_root = "/repo",
        workspace = {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          project_root = "/codux-worktrees/repo/alpha-builder",
          worktree_path = "/codux-worktrees/repo/alpha-builder",
          worktree_branch = "dev/alpha-builder",
          tmux_target = "session:alpha-builder",
          mission_role = "Builder",
        },
      },
      notify = function() end,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if
          command
          == "git -C /codux-worktrees/repo/alpha-builder show-ref --verify --quiet refs/heads/dev/alpha-build-lead"
        then
          return "", 1
        end
        if
          command
          == "git -C /codux-worktrees/repo/alpha-builder worktree move /codux-worktrees/repo/alpha-builder /codux-worktrees/repo/alpha-build-lead"
        then
          return "", 0
        end
        if command == "git -C /codux-worktrees/repo/alpha-build-lead branch -m dev/alpha-builder dev/alpha-build-lead" then
          return "", 0
        end
        if command == "tmux rename-window -t @1 alpha-build-lead" then
          return "", 0
        end
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
      store = {
        read_state = function()
          return state_data, nil
        end,
        write_state = function(_, next_state)
          state_data = next_state
          return true, nil
        end,
        timestamp = function()
          return "2026-06-30T00:00:00Z"
        end,
        project_state = project_state,
        instruction_file_path = function(_, root, safe_name)
          return root .. "/.agents/codux/" .. safe_name .. ".md"
        end,
        write_instruction_file = function(_, root, safe_name, instruction)
          written_instruction = {
            root = root,
            safe_name = safe_name,
            instruction = instruction,
          }
          return true, nil
        end,
      },
    })
    function runtime:mission_for_name(root, name)
      assert_equal(root, "/repo")
      assert_equal(name, "Alpha")
      return {
        name = "Alpha",
        objective = "Build it",
        roles = {
          {
            name = "alpha-builder",
            safe_name = "alpha-builder",
            project_root = "/codux-worktrees/repo/alpha-builder",
            mission_role = "Builder",
          },
        },
      }, nil
    end

    assert_true(runtime:rename_mission_role({
      name = "alpha-builder",
      safe_name = "alpha-builder",
      project_root = "/codux-worktrees/repo/alpha-builder",
      window_id = "@1",
      window_name = "alpha-builder",
      mission_name = "Alpha",
    }, "Build Lead", { project_root = "/repo" }))
    assert_nil(state_data.projects["/codux-worktrees/repo/alpha-builder"].workspaces["alpha-builder"])
    local record = state_data.projects["/codux-worktrees/repo/alpha-build-lead"].workspaces["alpha-build-lead"]
    assert_equal(record.name, "alpha-build-lead")
    assert_equal(record.safe_name, "alpha-build-lead")
    assert_equal(record.project_root, "/codux-worktrees/repo/alpha-build-lead")
    assert_equal(record.worktree_path, "/codux-worktrees/repo/alpha-build-lead")
    assert_equal(record.worktree_branch, "dev/alpha-build-lead")
    assert_equal(record.git_branch, "dev/alpha-build-lead")
    assert_equal(record.target_path, "/codux-worktrees/repo/alpha-build-lead/lua/init.lua")
    assert_equal(record.tmux_window, "alpha-build-lead")
    assert_equal(record.tmux_target, "session:alpha-build-lead")
    assert_equal(record.mission_role, "Build Lead")
    assert_contains(record.resolved_instruction, "You are the Build Lead")
    assert_contains(record.resolved_instruction, "Role focus:\nKeep the implementation focused.")
    assert_equal(written_instruction.root, "/codux-worktrees/repo/alpha-build-lead")
    assert_equal(written_instruction.safe_name, "alpha-build-lead")
    assert_equal(written_instruction.instruction, record.resolved_instruction)
    assert_equal(runtime.state.workspace.name, "alpha-build-lead")
    assert_equal(runtime.state.workspace.safe_name, "alpha-build-lead")
    assert_equal(runtime.state.workspace.project_root, "/codux-worktrees/repo/alpha-build-lead")
    assert_equal(runtime.state.workspace.worktree_branch, "dev/alpha-build-lead")
    assert_equal(runtime.state.workspace.mission_role, "Build Lead")
    local command_text = table.concat(commands, "\n")
    assert_contains(
      command_text,
      "git -C /codux-worktrees/repo/alpha-builder worktree move /codux-worktrees/repo/alpha-builder /codux-worktrees/repo/alpha-build-lead"
    )
    assert_contains(command_text, "git -C /codux-worktrees/repo/alpha-build-lead branch -m dev/alpha-builder dev/alpha-build-lead")
    assert_contains(command_text, "tmux rename-window -t @1 alpha-build-lead")
  end)
  end)
end

do
  local commands = {}
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    system = function(args)
      table.insert(commands, table.concat(args, " "))
      return "", 1
    end,
  })
  function runtime:mission_for_name()
    return {
      name = "Alpha",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          project_root = "/codux-worktrees/alpha-builder",
          mission_role = "Builder",
        },
        {
          name = "alpha-reviewer",
          safe_name = "alpha-reviewer",
          project_root = "/codux-worktrees/alpha-reviewer",
          mission_role = "Reviewer",
        },
      },
    }, nil
  end

  local ok, err = runtime:rename_mission_role({
    name = "alpha-builder",
    safe_name = "alpha-builder",
    project_root = "/codux-worktrees/alpha-builder",
    mission_name = "Alpha",
  }, "Reviewer", { project_root = "/repo" })

  assert_false(ok)
  assert_equal(err, "mission role already exists")
  assert_equal(#commands, 0)
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          old = {
            name = "old",
            safe_name = "old",
            project_root = "/repo",
            tmux_window = "old",
            status = "inactive",
            agent_status = "idle",
            agent_session_captured_at = "2026-06-30T12:00:00Z",
          },
          other = {
            name = "other",
            safe_name = "other",
            project_root = "/repo",
            tmux_window = "other",
            status = "inactive",
            agent_status = "idle",
            created_at = "2026-06-01T12:00:00Z",
          },
        },
      },
    },
  }
  local runtime = runtime_mod.new({
    state = {},
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      instruction_file_records = function()
        return {}
      end,
    },
  })

  local entries = runtime:entries_for_project("/repo")
  local by_name = {}
  for _, entry in ipairs(entries) do
    by_name[entry.name] = entry
  end

  assert_equal(by_name.old.agent_session_captured_at, "2026-06-30T12:00:00Z")
  assert_equal(workspace_ui.activity_timestamp(by_name.old), "2026-06-30T12:00:00Z")
  assert_equal(workspace_ui.sort_entries(entries, "status_recent")[1].name, "old")
end

do
  with_filereadable(1, function()
    local delete_calls = 0
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record(),
      }),
      write_state = function()
        return false, "write failed"
      end,
      delete_instruction_file = function()
        delete_calls = delete_calls + 1
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store)

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }))
    assert_equal(delete_calls, 0, "instruction file should not be deleted when state write fails")
  end)
end

do
  with_filereadable(1, function()
    local state_data = workspace_state({
      review = review_workspace_record(),
    }, {
      updated_at = "before",
    })
    local write_count = 0
    local killed = false
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        write_count = write_count + 1
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return false, "delete instruction failed"
      end,
    })
    local runtime = workspace_delete_runtime(store.store)
    runtime.kill_tmux_window_deferred = function()
      killed = true
    end

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      window_id = "@1",
    }))
    assert_equal(write_count, 2, "failed instruction delete should restore prior state")
    assert_equal(state_data.projects["/repo"].workspaces.review.name, "review")
    assert_false(killed, "tmux window should not be killed when delete is rolled back")
  end)
end

do
  with_filereadable(1, function()
    local delete_calls = 0
    local killed = false
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record(),
      }),
      delete_instruction_file = function(_, root, safe_name)
        delete_calls = delete_calls + 1
        assert_equal(root, "/repo")
        assert_equal(safe_name, "review")
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store)
    runtime.kill_tmux_window_deferred = function(_, window_id)
      killed = window_id == "@1"
    end

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      window_id = "@1",
    }))
    assert_nil(store.state_data().projects["/repo"].workspaces.review)
    assert_equal(delete_calls, 1)
    assert_true(killed)
  end)
end

do
  with_filereadable(1, function()
    local deleted_instruction = false
    local removed_worktree = false
    local deleted_branch = false
    local closed = false
    local state_data = worktree_delete_state()
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function(_, root, safe_name)
        deleted_instruction = root == "/repo" and safe_name == "review"
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      close_workspace_manager = function()
        closed = true
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_true(deleted_instruction)
    assert_true(removed_worktree)
    assert_true(deleted_branch)
    assert_true(closed)
    assert_nil(state_data.projects["/repo"].workspaces.review)
  end)
end

do
  with_filereadable(1, function()
    local deleted_instruction = false
    local removed_worktree = false
    local deleted_branch = false
    local killed_window = false
    local cleanup_root
    local nested_root = "/codux-worktrees/repo/alpha-builder"
    local state_data = {
      projects = {
        [nested_root] = {
          workspaces = {
            ["alpha-builder"] = review_workspace_record({
              name = "alpha-builder",
              safe_name = "alpha-builder",
              project_root = nested_root,
              tmux_window = "stale-window-name",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = nested_root,
              worktree_branch = "dev/alpha-builder",
              worktree_base = "main",
              mission_id = "mission:alpha",
              mission_name = "Alpha",
              mission_role = "Builder",
              mission_objective = "Build it",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function(_, root, safe_name)
        deleted_instruction = root == nested_root and safe_name == "alpha-builder"
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
          return "/repo/.git\n", 0
        end
        if command == "git --git-dir=/repo/.git worktree list --porcelain" then
          return "worktree /repo\nHEAD base\nbranch refs/heads/main\n\nworktree "
            .. nested_root
            .. "\nHEAD role\nbranch refs/heads/dev/alpha-builder\n",
            0
        end
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\tunrelated\n", 0
        end
        if command == "tmux list-panes -a -F #{window_id}\t#{pane_current_path}" then
          return "@9\t" .. nested_root .. "\n", 0
        end
        if command == "tmux kill-window -t @9" then
          killed_window = true
          return "", 0
        end
        if command == "git --git-dir=/repo/.git worktree remove --force " .. nested_root then
          removed_worktree = true
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/alpha-builder" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })
    runtime.cleanup_mission_residue = function(_, root)
      cleanup_root = root
      return true, {}
    end

    assert_true(runtime:delete_mission("Alpha", { project_root = "/repo" }))
    assert_true(deleted_instruction)
    assert_true(killed_window)
    assert_true(removed_worktree)
    assert_true(deleted_branch)
    assert_equal(cleanup_root, "/repo")
    assert_nil(state_data.projects[nested_root])
  end)
end

do
  with_filereadable(1, function()
    local notification
    local attempted_remove = false
    local state_data = worktree_delete_state()
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      notify = function(message)
        notification = message
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree list --porcelain" then
          return "worktree /repo\nHEAD base\nbranch refs/heads/main\n\nworktree /codux-worktrees/review\nHEAD role\nbranch refs/heads/dev/review\n",
            0
        end
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        if command == "tmux list-panes -a -F #{window_id}\t#{pane_current_path}" then
          return "@9\t/codux-worktrees/review/subdir\n", 0
        end
        if command == "tmux kill-window -t @9" then
          return "failed\n", 1
        end
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          attempted_remove = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_contains(notification, "Failed to close tmux window")
    assert_false(attempted_remove)
    assert_equal(state_data.projects["/repo"].workspaces.review.worktree_branch, "dev/review")
  end)
end

do
  with_filereadable(1, function()
    local deleted_instruction = false
    local removed_worktree = false
    local state_data = worktree_delete_state()
    local store = workspace_store({
      state_data = state_data,
      write_state = function()
        return false, "write failed"
      end,
      delete_instruction_file = function()
        deleted_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_false(deleted_instruction)
    assert_false(removed_worktree)
    assert_equal(state_data.projects["/repo"].workspaces.review.worktree_branch, "dev/review")
  end)
end

do
  with_filereadable(1, function()
    local notification
    local rendered = false
    local closed = false
    local attempted_branch_delete = false
    local state_data = worktree_delete_state()
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      notify = function(message)
        notification = message
      end,
      render_workspace_manager = function()
        rendered = true
      end,
      close_workspace_manager = function()
        closed = true
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          return "fatal: worktree is locked\n", 1
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          attempted_branch_delete = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_contains(notification, "Failed to remove Git worktree /codux-worktrees/review")
    assert_contains(notification, "fatal: worktree is locked")
    assert_true(rendered)
    assert_false(closed)
    assert_false(attempted_branch_delete)
    assert_equal(state_data.projects["/repo"].workspaces.review.worktree_branch, "dev/review")
  end)
end

do
  with_filereadable(1, function()
    local notification
    local rendered = false
    local closed = false
    local removed_worktree = false
    local state_data = worktree_delete_state()
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      notify = function(message)
        notification = message
      end,
      render_workspace_manager = function()
        rendered = true
      end,
      close_workspace_manager = function()
        closed = true
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          return "fatal: branch delete failed\n", 1
        end
        return "", 1
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_true(removed_worktree)
    assert_contains(notification, "Failed to delete Git branch dev/review")
    assert_contains(notification, "fatal: branch delete failed")
    assert_true(rendered)
    assert_false(closed)
    assert_nil(state_data.projects["/repo"].workspaces.review)
  end)
end

do
  with_filereadable(1, function()
    local deleted_branch = false
    local state_data = worktree_delete_state()
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_true(deleted_branch)
    assert_nil(state_data.projects["/repo"].workspaces.review)
  end)
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          ["alpha-research"] = review_workspace_record({
            name = "alpha-research",
            safe_name = "alpha-research",
            project_root = "/repo",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_path = "/codux-worktrees/alpha-research",
            worktree_branch = "dev/alpha-research",
            mission_id = "mission:alpha",
            mission_name = "Alpha",
            mission_role = "Research",
            mission_objective = "Build it",
          }),
        },
      },
    },
  }
  local runtime = runtime_mod.new({
    store = {
      read_state = function()
        return state_data, nil
      end,
      instruction_file_records = function()
        return {}
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      return "", 1
    end,
  })

  local entries = runtime:entries_for_project("/repo")
  local missions = mission_mod.group_entries(entries)
  local mission = assert(mission_mod.find_mission(missions, "Alpha"))
  assert_equal(#mission.roles, 1)
  assert_equal(mission.roles[1].safe_name, "alpha-research")
  assert_equal(mission.roles[1].mission_role, "Research")
end

do
  with_filereadable(1, function()
    local delete_calls = 0
    local store = workspace_store({
      state_data = workspace_state({}),
      delete_instruction_file = function(_, root, safe_name)
        delete_calls = delete_calls + 1
        assert_equal(root, "/repo")
        assert_equal(safe_name, "review")
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store)

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }))
    assert_equal(delete_calls, 1)
  end)
end

do
  with_filereadable(1, function()
    local closed = false
    local store = workspace_store({
      state_data = workspace_state({}),
      delete_instruction_file = function()
        return false, "delete instruction failed"
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      close_workspace_manager = function()
        closed = true
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }))
    assert_false(closed, "instruction-only delete should fail when instruction file remains")
  end)
end


print("workspace_runtime_lifecycle_spec.lua: ok")
