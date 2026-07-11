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

do
  local runtime = runtime_with_tmux({
    ["tmux list-panes -t @1 -F #{pane_current_command}"] = { "bash\nnvim\n", 0 },
  })

  assert_equal(runtime:status_for_window("@1"), "active", "nvim in any pane should mark window active")
end

do
  local runtime = runtime_with_tmux({
    ["tmux list-panes -t @1 -F #{pane_current_command}"] = { "bash\nzsh\n", 0 },
  })

  assert_equal(runtime:status_for_window("@1"), "inactive", "non-nvim panes should mark window inactive")
end

do
  local runtime = runtime_with_tmux({})

  assert_equal(runtime:status_for_window(nil), "inactive")
  assert_equal(runtime:dashboard_workspace_status({ status = "idle", agent_status = "idle" }, nil), "inactive")
  assert_equal(runtime:dashboard_workspace_status({ status = "inactive", agent_status = "idle" }, nil), "inactive")
end

do
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        safe_name = "review",
      },
    },
  })

  assert_false(runtime:target_sync_allowed("BufEnter", function()
    return "codux-missions"
  end))
  assert_false(runtime:target_sync_allowed("BufEnter", function()
    return "codux-missions-actions"
  end))
  assert_false(runtime:target_sync_allowed("BufEnter", function()
    return "codux-mission-workspace-prompt"
  end))
  assert_false(runtime:target_sync_allowed("BufEnter", function()
    return "codux-mission-question-option"
  end))
  assert_false(runtime:target_sync_allowed("BufEnter", function()
    return "codux-mission-question-note"
  end))
  assert_true(runtime:target_sync_allowed("BufEnter", function()
    return "lua"
  end))
end

do
  local builder_instruction = mission_mod.role_instruction("Alpha", "Old objective", {
    name = "Builder",
    safe_name = "builder",
    focus = "Build it.",
  })
  local reviewer_instruction = mission_mod.role_instruction("Alpha", "Old objective", {
    name = "Reviewer",
    safe_name = "reviewer",
    focus = "Review it.",
  })
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          ["alpha-builder"] = review_workspace_record({
            name = "alpha-builder",
            safe_name = "alpha-builder",
            project_root = "/repo",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_path = "/codux-worktrees/alpha-builder",
            status = "active",
            agent_status = "working",
            agent_mode = "execute",
            mission_id = "mission:alpha",
            mission_name = "Alpha",
            mission_role = "Builder",
            mission_objective = "Old objective",
            resolved_instruction = builder_instruction,
          }),
          ["alpha-reviewer"] = review_workspace_record({
            name = "alpha-reviewer",
            safe_name = "alpha-reviewer",
            project_root = "/repo",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_path = "/codux-worktrees/alpha-reviewer",
            status = "idle",
            agent_status = "idle",
            agent_mode = "plan",
            mission_id = "mission:alpha",
            mission_name = "Alpha",
            mission_role = "Reviewer",
            mission_objective = "Old objective",
            resolved_instruction = reviewer_instruction,
          }),
        },
      },
    },
  }
  local written_instructions = {}
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        mission_id = "mission:alpha",
        mission_objective = "Old objective",
        resolved_instruction = builder_instruction,
        project_root = "/repo",
        worktree_path = "/codux-worktrees/alpha-builder",
        safe_name = "alpha-builder",
      },
    },
    notify = function() end,
    render_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-07-02T00:00:00Z"
      end,
      project_state = project_state,
      instruction_file_records = function()
        return {}
      end,
      write_instruction_file = function(_, root, safe_name, instruction)
        table.insert(written_instructions, root .. ":" .. safe_name .. ":" .. instruction)
        return true, nil
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/alpha-builder status --porcelain" then
        return " M lua/codux/init.lua\n", 0
      end
      if command == "git -C /codux-worktrees/alpha-reviewer status --porcelain" then
        return "", 0
      end
      return "", 1
    end,
  })

  assert_equal(runtime:mission_names_for_project("/repo")[1], "Alpha")
  local ok, error_message = runtime:update_mission_objective("Alpha", "New objective", { project_root = "/repo" })
  assert_true(ok)
  assert_nil(error_message)
  assert_equal(
    state_data.projects["/repo"].workspaces["alpha-builder"].mission_objective,
    "New objective"
  )
  assert_contains(
    state_data.projects["/repo"].workspaces["alpha-reviewer"].resolved_instruction,
    "Objective:\nNew objective\n\nRole focus:"
  )
  assert_equal(runtime.state.workspace.mission_objective, "New objective")
  assert_equal(#written_instructions, 2)

  local dirty_roles, dirty_error = runtime:mission_dirty_roles("Alpha", { project_root = "/repo" })
  assert_nil(dirty_error)
  assert_equal(#dirty_roles, 1)
  assert_equal(dirty_roles[1].name, "alpha-builder")
  assert_equal(dirty_roles[1].reason, "dirty")

  assert_true(runtime:close_mission("Alpha", { project_root = "/repo" }))
  assert_equal(state_data.projects["/repo"].workspaces["alpha-builder"].status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces["alpha-builder"].agent_status, "idle")
  assert_nil(state_data.projects["/repo"].workspaces["alpha-builder"].agent_mode)
  assert_equal(state_data.projects["/repo"].workspaces["alpha-reviewer"].status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces["alpha-reviewer"].mission_id, "mission:alpha")

  local deleted = {}
  runtime.delete_saved_workspace = function(_, entry)
    table.insert(deleted, entry.safe_name)
    return true
  end
  assert_true(runtime:delete_mission("Alpha", { project_root = "/repo" }))
  table.sort(deleted)
  assert_equal(table.concat(deleted, ","), "alpha-builder,alpha-reviewer")
end

do
  local calls = {}
  local notifications = {}
  local rendered_manager = false
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(notifications, message)
    end,
    render_workspace_manager = function()
      rendered_manager = true
    end,
  })
  function runtime:mission_for_name(root, name)
    assert_equal(root, "/repo")
    assert_equal(name, "Alpha")
    return {
      name = "Alpha",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_role = "Builder",
          permission_profile = "danger",
          project_root = "/codux-worktrees/alpha-builder",
        },
        {
          name = "alpha-reviewer",
          safe_name = "alpha-reviewer",
          mission_role = "Reviewer",
          project_root = "/codux-worktrees/alpha-reviewer",
        },
      },
    }
  end
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    assert_true(opts.allow_existing)
    assert_true(opts.require_existing)
    assert_nil(opts.initial_prompt)
    assert_equal(opts.initial_mode, "plan")
    if name == "alpha-builder" then
      assert_equal(opts.permission_profile, "danger")
    else
      assert_equal(opts.permission_profile, "auto")
    end
    if name == "alpha-reviewer" then
      return nil, "workspace failed"
    end
    return { name = name, window_id = "@1" }, nil
  end
  function runtime:ensure_workspace_plan_mode(workspace)
    assert_equal(workspace.name, "alpha-builder")
    return true, nil
  end

  assert_false(runtime:start_mission("Alpha", { project_root = "/repo" }))
  assert_equal(#calls, 2)
  assert_equal(calls[1].name, "alpha-builder")
  assert_equal(calls[1].opts.project_root, "/codux-worktrees/alpha-builder")
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_equal(calls[1].opts.permission_profile, "danger")
  assert_equal(calls[2].name, "alpha-reviewer")
  assert_equal(calls[2].opts.project_root, "/codux-worktrees/alpha-reviewer")
  assert_equal(calls[2].opts.initial_mode, "plan")
  assert_equal(calls[2].opts.permission_profile, "auto")
  assert_true(rendered_manager)
  assert_contains(table.concat(notifications, "\n"), "Failed to start Codux mission role Reviewer: workspace failed")
  assert_contains(table.concat(notifications, "\n"), "Started 1 roles in Codux mission Alpha; 1 failed")
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    render_workspace_manager = function() end,
  })
  function runtime:mission_for_name(root, name)
    assert_equal(root, "/repo")
    assert_equal(name, "Alpha")
    return {
      name = "Alpha",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_role = "Builder",
          project_root = "/repo",
          initial_mode = "execute",
        },
      },
    }
  end
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    return {
      name = name,
      safe_name = name,
      project_root = "/repo",
      window_id = "@1",
      status = "idle",
      initial_mode = opts.initial_mode,
      window_created = false,
    }, nil
  end
  function runtime:ensure_workspace_plan_mode(workspace)
    assert_equal(workspace.safe_name, "alpha-builder")
    table.insert(calls, { name = "ensure_plan" })
    return true, nil
  end

  assert_true(runtime:start_mission("Alpha", { project_root = "/repo" }))
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_equal(calls[2].name, "ensure_plan")
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    render_workspace_manager = function() end,
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
          mission_role = "Builder",
          project_root = "/repo",
        },
      },
    }
  end
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    assert_true(opts.restart_inactive)
    return {
      name = name,
      safe_name = name,
      project_root = "/repo",
      window_id = "@1",
      status = "idle",
      initial_mode = opts.initial_mode,
    }, nil
  end
  function runtime:ensure_workspace_plan_mode(workspace)
    assert_equal(workspace.initial_mode, "plan")
    table.insert(calls, { name = "ensure_plan", workspace = workspace })
    return true, nil
  end
  function runtime:send_prompt_to_workspace(workspace, prompt)
    table.insert(calls, { name = "send_prompt", workspace = workspace, prompt = prompt })
    error("start_mission should not prompt roles on startup")
  end
  function runtime:switch_tmux_window(window_id)
    table.insert(calls, { name = "focus", window_id = window_id })
    return true
  end

  assert_true(runtime:start_mission("Alpha", {
    project_root = "/repo",
    restart_inactive = true,
    prompt_roles = true,
    focus_first = true,
  }))
  assert_equal(calls[1].name, "alpha-builder")
  assert_equal(calls[2].name, "ensure_plan")
  assert_equal(calls[3].name, "focus")
  assert_equal(calls[3].window_id, "@1")
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    notify = function() end,
  })
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    return {
      name = name,
      safe_name = name,
      project_root = "/repo",
      window_id = "@1",
      git_branch = "",
      initial_mode = opts.initial_mode,
    }, nil
  end
  function runtime:switch_tmux_window(window_id)
    table.insert(calls, { name = "focus", window_id = window_id })
    return true
  end

  assert_true(runtime:create_workspace("review", { initial_mode = "execute", initial_prompt = "start now" }))
  assert_equal(calls[1].name, "review")
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_equal(calls[1].opts.initial_prompt, "start now")
  assert_nil(calls[2])
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    notify = function() end,
  })
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    return {
      name = name,
      safe_name = name,
      project_root = opts.project_root,
      window_id = "@1",
      git_branch = "",
      initial_mode = opts.initial_mode,
    }, nil
  end
  function runtime:switch_tmux_window(window_id)
    table.insert(calls, { name = "focus", window_id = window_id })
    return true
  end

  assert_true(runtime:open_saved_workspace("review", "/repo"))
  assert_equal(calls[1].name, "review")
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_equal(calls[2].name, "focus")
end

do
  local calls = {}
  local notifications = {}
  local rendered = false
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(notifications, message)
    end,
    render_workspace_manager = function()
      rendered = true
    end,
  })
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    return {
      name = name,
      safe_name = name,
      project_root = opts.project_root,
      window_id = "@9",
      git_branch = "",
      initial_mode = opts.initial_mode,
    }, nil
  end
  function runtime:ensure_workspace_plan_mode(workspace)
    table.insert(calls, { name = "plan", workspace = workspace.name })
    return true
  end
  function runtime:switch_tmux_window()
    table.insert(calls, { name = "focus" })
    return true
  end

  assert_true(runtime:start_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    agent_provider = "grok",
    permission_profile = "auto",
  }))
  assert_equal(calls[1].name, "review")
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_true(calls[1].opts.restart_inactive)
  assert_equal(calls[1].opts.agent_provider, "grok")
  assert_equal(calls[1].opts.permission_profile, "auto")
  assert_equal(calls[2].name, "plan")
  assert_equal(#calls, 2, "start should not focus by default")
  assert_true(rendered)
  assert_contains(table.concat(notifications, "\n"), "Started Codux workspace review")
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    render_workspace_manager = function() end,
  })
  function runtime:mission_for_name(root, name)
    assert_equal(root, "/repo")
    assert_equal(name, "Alpha")
    return {
      name = "Alpha",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_role = "Builder",
          project_root = "/repo",
        },
      },
    }
  end
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    return {
      name = name,
      safe_name = name,
      project_root = "/repo",
      window_id = "@1",
      status = "inactive",
      initial_mode = opts.initial_mode,
      window_created = true,
    }, nil
  end
  function runtime:ensure_workspace_plan_mode(workspace)
    assert_equal(workspace.safe_name, "alpha-builder")
    assert_true(workspace.window_created)
    table.insert(calls, { name = "ensure_plan" })
    return true, nil
  end

  assert_true(runtime:start_mission("Alpha", { project_root = "/repo" }))
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_equal(calls[2].name, "ensure_plan")
end

do
  local notifications = {}
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(notifications, message)
    end,
    render_workspace_manager = function() end,
  })
  function runtime:mission_for_name()
    return {
      name = "Alpha",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_role = "Builder",
          project_root = "/repo",
        },
      },
    }
  end
  function runtime:prepare_workspace(_, opts)
    return {
      name = "alpha-builder",
      safe_name = "alpha-builder",
      project_root = "/repo",
      window_id = "@1",
      status = "idle",
      initial_mode = opts.initial_mode,
      window_created = false,
    }, nil
  end
  function runtime:ensure_workspace_plan_mode()
    table.insert(notifications, "ensure_plan_attempted")
    return false, "still execute"
  end
  function runtime:switch_tmux_window(window_id)
    table.insert(notifications, "focus:" .. tostring(window_id))
    return true
  end

  assert_true(runtime:start_mission("Alpha", { project_root = "/repo", focus_first = true }))
  assert_equal(#notifications, 3)
  assert_equal(notifications[1], "ensure_plan_attempted")
  assert_equal(notifications[2], "Started Codux mission Alpha with 1 roles")
  assert_equal(notifications[3], "focus:@1")
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          stale = {
            name = "stale",
            safe_name = "stale",
            project_root = "/repo",
            tmux_window = "stale",
            status = "idle",
            agent_status = "idle",
            agent_mode = "plan",
          },
        },
      },
    },
  }
  local writes = 0
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        project_root = "/repo",
        safe_name = "stale",
        window_name = "stale",
      },
    },
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        return "@2\tother\n", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        writes = writes + 1
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
    },
  })

  assert_equal(runtime:sync_activity("working"), true)
  local record = state_data.projects["/repo"].workspaces.stale
  assert_equal(record.status, "inactive", "activity sync should not revive inactive window")
  assert_equal(record.agent_status, "idle")
  assert_equal(record.agent_mode, nil)
  assert_equal(writes, 1)
end

do
  local state_data = workspace_state({
    review = review_workspace_record({
      agent_provider = "codex",
      permission_profile = "default",
      agent_session_id = "codex-session",
      agent_session_path = "/codex/session.jsonl",
      agent_session_captured_at = "2026-07-09T12:00:00Z",
    }),
  })
  local store = workspace_store({ state_data = state_data })
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    store = store.store,
    render_workspace_manager = function() end,
  })

  local ok, err, restarted = runtime:update_workspace_profile({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
  }, "codex", "danger", { restart = true })

  assert_true(ok)
  assert_nil(err)
  assert_nil(restarted)
  local record = store.state_data().projects["/repo"].workspaces.review
  assert_equal(record.agent_provider, "codex")
  assert_equal(record.permission_profile, "danger")
  assert_equal(record.agent_session_id, "codex-session")
end

do
  local killed = false
  local prepared = false
  local state_data = workspace_state({
    review = review_workspace_record({
      agent_provider = "codex",
      permission_profile = "default",
      agent_session_id = "codex-session",
      agent_session_path = "/codex/session.jsonl",
      agent_session_captured_at = "2026-07-09T12:00:00Z",
      status = "inactive",
      agent_status = "idle",
      agent_mode = "plan",
    }),
  })
  local store = workspace_store({ state_data = state_data })
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    store = store.store,
    render_workspace_manager = function() end,
  })
  function runtime:status_for_window(window_id)
    assert_equal(window_id, "@1")
    return "inactive"
  end
  function runtime:kill_tmux_window()
    killed = true
    return true
  end
  function runtime:prepare_workspace()
    prepared = true
    return { name = "review" }, nil
  end

  local ok, err, restarted = runtime:update_workspace_profile({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
  }, "grok", "auto", { restart = true })

  assert_true(ok)
  assert_nil(err)
  assert_nil(restarted)
  assert_false(killed)
  assert_false(prepared)
  local record = store.state_data().projects["/repo"].workspaces.review
  assert_equal(record.agent_provider, "grok")
  assert_equal(record.permission_profile, "auto")
  assert_nil(record.agent_session_id)
  assert_nil(record.agent_session_id)
end

do
  local prepared
  local killed
  local state_data = workspace_state({
    review = review_workspace_record({
      agent_provider = "codex",
      permission_profile = "default",
      agent_session_id = "codex-session",
      agent_session_path = "/codex/session.jsonl",
      agent_session_captured_at = "2026-07-09T12:00:00Z",
      agent_session_id = "agent-session",
      agent_session_path = "/agent/session",
      agent_session_captured_at = "2026-07-09T12:01:00Z",
      status = "idle",
      agent_status = "idle",
      agent_mode = "plan",
    }),
  })
  local store = workspace_store({ state_data = state_data })
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
      workspace = {
        project_root = "/repo",
        safe_name = "review",
      },
    },
    store = store.store,
    render_workspace_manager = function() end,
  })
  function runtime:current_tmux_session()
    return "session"
  end
  function runtime:status_for_window(window_id)
    assert_equal(window_id, "@1")
    return "active"
  end
  function runtime:kill_tmux_window(window_id)
    killed = window_id
    return true
  end
  function runtime:prepare_workspace(name, opts)
    prepared = { name = name, opts = opts }
    return { name = name, safe_name = "review", project_root = "/repo" }, nil
  end

  local ok, err, restarted = runtime:update_workspace_profile({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
  }, "grok", "auto", { restart = true })

  assert_true(ok)
  assert_nil(err)
  assert_true(restarted)
  assert_equal(killed, "@1")
  assert_equal(prepared.name, "review")
  assert_true(prepared.opts.allow_existing)
  assert_true(prepared.opts.require_existing)
  assert_true(prepared.opts.restart_inactive)
  assert_equal(prepared.opts.agent_provider, "grok")
  assert_equal(prepared.opts.permission_profile, "auto")

  local record = store.state_data().projects["/repo"].workspaces.review
  assert_equal(record.agent_provider, "grok")
  assert_equal(record.permission_profile, "auto")
  assert_nil(record.agent_session_id)
  assert_nil(record.agent_session_id)
  assert_equal(runtime.state.workspace.agent_provider, "grok")
  assert_equal(runtime.state.workspace.permission_profile, "auto")
  assert_nil(runtime.state.workspace.agent_session_id)
end
