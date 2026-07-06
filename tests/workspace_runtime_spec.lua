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
  assert_equal(runtime:dashboard_workspace_status({ status = "idle", codex_status = "idle" }, nil), "inactive")
  assert_equal(runtime:dashboard_workspace_status({ status = "inactive", codex_status = "idle" }, nil), "inactive")
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
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
        return "", 1
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(error_message)
  assert_equal(branch, "dev/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1/review" then
        return "", 1
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(error_message)
  assert_equal(branch, "dev1/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1" then
        return "", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev2" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev2/review" then
        return "", 1
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(error_message)
  assert_equal(branch, "dev2/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
        return "", 0
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(branch)
  assert_equal(error_message, "branch already exists: dev/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
  })

  assert_equal(runtime:renamed_worktree_branch({ worktree_branch = "dev1/review" }, "search"), "dev1/search")
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          docs = {
            name = "docs",
            safe_name = "docs",
            project_root = "/repo",
            tmux_window = "docs",
          },
        },
      },
      ["/codux-worktrees/review"] = {
        workspaces = {
          explicit_review = {
            name = "explicit-review",
            safe_name = "explicit_review",
            project_root = "/codux-worktrees/review",
            tmux_window = "explicit_review",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_path = "/codux-worktrees/review",
            worktree_branch = "dev/review",
            worktree_base = "main",
          },
          legacy_review = {
            name = "legacy-review",
            safe_name = "legacy_review",
            tmux_window = "legacy_review",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_path = "/codux-worktrees/review",
            worktree_branch = "dev/review",
            worktree_base = "main",
          },
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
  local by_name = {}
  for _, entry in ipairs(entries) do
    by_name[entry.name] = entry
  end
  assert_equal(by_name.docs.project_root, "/repo")
  assert_nil(by_name["explicit-review"])
  assert_equal(by_name["legacy-review"].project_root, "/codux-worktrees/review")
  assert_equal(by_name["legacy-review"].worktree_branch, "dev/review")
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
            codex_status = "working",
            codex_mode = "execute",
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
            codex_status = "idle",
            codex_mode = "plan",
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
  assert_equal(state_data.projects["/repo"].workspaces["alpha-builder"].codex_status, "idle")
  assert_nil(state_data.projects["/repo"].workspaces["alpha-builder"].codex_mode)
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
  local runtime = runtime_mod.new({
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /codux-worktrees/review rev-list --count aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..dev/review" then
        return "2\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 0
      end
      return "", 1
    end,
  })

  local state = runtime:workspace_branch_state({
    project_root = "/codux-worktrees/review",
    workspace_kind = "worktree",
    worktree_branch = "dev/review",
    worktree_base = "main",
    worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  })
  assert_true(state.worktree)
  assert_equal(state.ahead_count, 2)
  assert_true(state.merged)

  local missing = runtime:workspace_branch_state({
    workspace_kind = "worktree",
    worktree_branch = "dev/review",
    worktree_base = "main",
  })
  assert_true(missing.worktree)
  assert_equal(missing.error, "missing base")
end

do
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function()
    error("fresh workspace should not prompt for deletion")
  end
  local state_data = workspace_state({}, {})
  state_data.projects = {
    ["/repo"] = {
      workspaces = {
        review = review_workspace_record({
          project_root = "/repo",
          workspace_kind = "worktree",
          git_common_dir = "/repo/.git",
          worktree_path = "/codux-worktrees/review",
          worktree_branch = "dev/review",
          worktree_base = "main",
          worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }),
      },
    },
  }
  local runtime = runtime_mod.new({
    state = {},
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
      if command == "git -C /codux-worktrees/review rev-list --count aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..dev/review" then
        return "0\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 0
      end
      return "", 1
    end,
  })

  local ok, err = pcall(function()
    assert_true(runtime:prompt_merged_workspaces("/repo"))
  end)
  vim.fn.confirm = old_confirm
  if not ok then
    error(err, 0)
  end
end

do
  local old_filereadable = vim.fn.filereadable
  local old_confirm = vim.fn.confirm
  vim.fn.filereadable = function()
    return 1
  end
  vim.fn.confirm = function()
    return 1
  end
  local state_data = workspace_state({}, {})
  state_data.projects = {
    ["/repo"] = {
      workspaces = {
        review = review_workspace_record({
          project_root = "/repo",
          workspace_kind = "worktree",
          git_common_dir = "/repo/.git",
          worktree_path = "/codux-worktrees/review",
          worktree_branch = "dev/review",
          worktree_base = "main",
          worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }),
      },
    },
  }
  local removed_worktree = false
  local deleted_branch = false
  local runtime = runtime_mod.new({
    state = {},
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
      instruction_file_records = function()
        return {}
      end,
      instruction_file_path = function()
        return "/codux-worktrees/review/.agents/codux/review.md"
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    },
    notify = function() end,
    render_workspace_manager = function() end,
    close_workspace_manager = function() end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/review rev-list --count aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..dev/review" then
        return "1\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 0
      end
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

  local ok, err = pcall(function()
    assert_true(runtime:prompt_merged_workspaces("/repo"))
    assert_true(removed_worktree)
    assert_true(deleted_branch)
    assert_nil(state_data.projects["/repo"].workspaces.review)
  end)
  vim.fn.filereadable = old_filereadable
  vim.fn.confirm = old_confirm
  if not ok then
    error(err, 0)
  end
end

do
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function()
    error("backfilled workspace should not prompt during the same dashboard refresh")
  end
  local state_data = workspace_state({}, {})
  state_data.projects = {
    ["/repo"] = {
      workspaces = {
        review = review_workspace_record({
          project_root = "/repo",
          workspace_kind = "worktree",
          git_common_dir = "/repo/.git",
          worktree_path = "/codux-worktrees/review",
          worktree_branch = "dev/review",
          worktree_base = "main",
        }),
      },
    },
  }
  local runtime = runtime_mod.new({
    state = {},
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
      instruction_file_records = function()
        return {}
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base dev/review main" then
        return "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", 0
      end
      return "", 1
    end,
  })

  local ok, err = pcall(function()
    assert_true(runtime:prompt_merged_workspaces("/repo"))
    assert_equal(
      state_data.projects["/repo"].workspaces.review.worktree_base_commit,
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    )
  end)
  vim.fn.confirm = old_confirm
  if not ok then
    error(err, 0)
  end
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
            codex_status = "idle",
            codex_mode = "plan",
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
  assert_equal(record.codex_status, "idle")
  assert_equal(record.codex_mode, nil)
  assert_equal(writes, 1)
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
            codex_status = "idle",
            codex_mode = "plan",
          },
          debug = {
            name = "debug",
            safe_name = "debug",
            project_root = "/repo",
            tmux_window = "debug",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
          },
        },
      },
    },
  }
  local messages = {}
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
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
    },
  })

  assert_true(runtime:close_all_saved_workspace_windows("/repo"))
  assert_equal(state_data.projects["/repo"].workspaces.review.status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "inactive")
  assert_nil(state_data.projects["/repo"].workspaces.debug.codex_mode)
  assert_contains(messages[#messages], "Closed 2 Codux workspaces")
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
            codex_status = "idle",
            codex_mode = "plan",
          },
          debug = {
            name = "debug",
            safe_name = "debug",
            project_root = "/repo",
            tmux_window = "debug",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        project_root = "/repo",
        safe_name = "debug",
        status = "active",
        codex_status = "working",
        codex_mode = "execute",
        tmux_target = "session:debug",
      },
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
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
    },
  })

  assert_false(runtime:close_all_saved_workspace_windows("/repo"))
  assert_equal(state_data.projects["/repo"].workspaces.review.status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "active")
  assert_equal(state_data.projects["/repo"].workspaces.debug.codex_status, "working")
  assert_equal(state_data.projects["/repo"].workspaces.debug.codex_mode, "execute")
  assert_equal(runtime.state.workspace.status, "active")
  assert_equal(runtime.state.workspace.codex_status, "working")
  assert_equal(runtime.state.workspace.codex_mode, "execute")
  assert_equal(runtime.state.workspace.tmux_target, "session:debug")
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
            codex_status = "idle",
            codex_mode = "plan",
          },
          debug = {
            name = "debug",
            safe_name = "debug",
            project_root = "/repo",
            tmux_window = "debug",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        project_root = "/repo",
        safe_name = "review",
        status = "idle",
        codex_status = "idle",
        codex_mode = "plan",
        tmux_target = "session:review",
      },
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
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
    },
  })

  assert_false(runtime:close_all_saved_workspace_windows("/repo"))
  assert_equal(state_data.projects["/repo"].workspaces.review.status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "active")
  assert_equal(runtime.state.workspace.status, "inactive")
  assert_equal(runtime.state.workspace.codex_status, "idle")
  assert_nil(runtime.state.workspace.codex_mode)
  assert_nil(runtime.state.workspace.tmux_target)
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
            codex_status = "idle",
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
            codex_status = "idle",
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
            codex_status = "idle",
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
            codex_status = "idle",
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
            codex_status = "idle",
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
            codex_status = "idle",
            codex_session_captured_at = "2026-06-30T12:00:00Z",
          },
          other = {
            name = "other",
            safe_name = "other",
            project_root = "/repo",
            tmux_window = "other",
            status = "inactive",
            codex_status = "idle",
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

  assert_equal(by_name.old.codex_session_captured_at, "2026-06-30T12:00:00Z")
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
    local state_data = {
      projects = {
        ["/repo"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/repo",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
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
    local state_data = {
      projects = {
        ["/repo"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/repo",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
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
    local state_data = {
      projects = {
        ["/repo"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/repo",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
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
    local state_data = {
      projects = {
        ["/repo"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/repo",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
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
    local state_data = {
      projects = {
        ["/repo"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/repo",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
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

do
  with_workspace_prepare_env(function()
    local commands = {}
    local created = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
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
    assert_contains(table.concat(commands, "\n"), "git -C /repo status --porcelain")
    assert_contains(table.concat(commands, "\n"), "git -C /repo worktree add -b dev/review /codux-worktrees/review main")
    assert_equal(store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
    assert_equal(
      store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_base_commit,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    )
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local created = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
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
    assert_equal(workspace.codex_status, "working")
    assert_contains(table.concat(commands, "\n"), "start building")
    local record = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(record.permission_profile, "auto")
    assert_equal(record.mission_id, "mission:mission")
    assert_equal(record.mission_role, "Builder")
    assert_equal(record.mission_objective, "Build it")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local killed = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
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
          return "not_running\n", 0
        end
        if command == "tmux kill-window -t @1" then
          killed = true
          return "", 0
        end
        if command == "git -C /repo worktree remove --force /codux-worktrees/mission-builder" then
          removed_worktree = true
          return "", 0
        end
        if command == "git -C /repo branch -D dev/mission-builder" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("mission-builder", {
      resolved_instruction = "builder instructions",
      initial_prompt = "start building",
      initial_mode = "plan",
      permission_profile = "auto",
      mission_id = "mission:mission",
      mission_name = "Mission",
      mission_role = "Builder",
      launch_verify_attempts = 1,
    })

    assert_nil(error_message)
    assert_equal(workspace.safe_name, "mission-builder")
    assert_false(killed)
    local record = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(record.initial_mode, "plan")
    assert_equal(record.permission_profile, "auto")
    assert_equal(record.mission_id, "mission:mission")
    assert_equal(record.codex_mode, "plan")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local killed = false
    local removed_worktree = false
    local deleted_branch = false
    local deleted_instruction = false
    local store = workspace_store({
      delete_instruction_file = function(_, root, safe_name)
        deleted_instruction = root == "/codux-worktrees/mission-builder" and safe_name == "mission-builder"
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
        if command == "tmux kill-window -t @1" then
          killed = true
          return "", 0
        end
        if command == "git -C /repo worktree remove --force /codux-worktrees/mission-builder" then
          removed_worktree = true
          return "", 0
        end
        if command == "git -C /repo branch -D dev/mission-builder" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("mission-builder", {
      resolved_instruction = "builder instructions",
      initial_prompt = "start building",
      permission_profile = "auto",
      mission_id = "mission:mission",
      mission_name = "Mission",
      mission_role = "Builder",
      launch_verify_attempts = 1,
    })

    assert_nil(workspace)
    assert_equal(error_message, "workspace is not reachable")
    assert_true(killed)
    assert_true(deleted_instruction)
    assert_true(removed_worktree)
    assert_true(deleted_branch)
    assert_nil(store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"])
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local state_data = {
      projects = {
        ["/codux-worktrees/mission-builder"] = {
          workspaces = {
            ["mission-builder"] = review_workspace_record({
              name = "mission-builder",
              safe_name = "mission-builder",
              project_root = "/codux-worktrees/mission-builder",
              workspace_kind = "worktree",
            }),
          },
        },
      },
    }
    local runtime = workspace_prepare_runtime({
      store = workspace_store({
        state_data = state_data,
      }).store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        return "", 1
      end,
    })
    local mission = assert(mission_mod.plan("Mission", "Build it", {
      roles = {
        { name = "Builder" },
      },
    }))

    local ok, error_message = runtime:preflight_mission(mission)
    assert_false(ok)
    assert_equal(error_message, "workspace already exists: mission-builder")
    assert_equal(table.concat(commands, "\n"):find("worktree add", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local windows = {}
    local next_window_id = 1
    local store = workspace_store({
      instruction_file_path = function(_, root, safe_name)
        return root .. "/.agents/codux/" .. safe_name .. ".md"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
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
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-architect" then
          return "", 1
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/mission-architect /codux-worktrees/mission-architect main" then
          return "", 0
        end
        if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/mission-builder main" then
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          local name = command:find("mission%-architect") and "mission-architect" or "mission-builder"
          windows[name] = "@" .. tostring(next_window_id)
          next_window_id = next_window_id + 1
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command == "tmux list-panes -t @2 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("remote_workspace_status", 1, true) then
          return "ready\n", 0
        end
        return "", 1
      end,
    })

    local mission, error_message = mission_mod.plan("Mission", "Build it", {
      roles = {
        { name = "Architect", safe_name = "architect", focus = "Design it" },
        { name = "Builder", safe_name = "builder", focus = "Build it" },
      },
    })
    assert_nil(error_message)
    assert_true(runtime:create_mission(mission))

    local architect =
      store.state_data().projects["/codux-worktrees/mission-architect"].workspaces["mission-architect"]
    local builder = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(architect.permission_profile, "auto")
    assert_equal(builder.permission_profile, "auto")
    assert_equal(architect.mission_id, "mission:mission")
    assert_equal(builder.mission_id, "mission:mission")
    assert_equal(architect.mission_role, "Architect")
    assert_equal(builder.mission_role, "Builder")
    assert_equal(architect.mission_objective, "Build it")
    assert_equal(builder.mission_objective, "Build it")
    assert_equal(architect.initial_mode, "plan")
    assert_equal(builder.initial_mode, "plan")
    assert_equal(architect.codex_status, "working")
    assert_equal(builder.codex_status, "working")
    assert_equal(architect.codex_mode, "plan")
    assert_equal(builder.codex_mode, "plan")
    local missions = runtime:missions_for_project("/repo")
    assert_equal(#missions, 1)
    assert_equal(missions[1].name, "Mission")
    assert_equal(#missions[1].roles, 2)
    assert_contains(table.concat(commands, "\n"), "git -C /repo status --porcelain")
    assert_contains(table.concat(commands, "\n"), "--listen")
    assert_contains(table.concat(commands, "\n"), "Start your Mission Control role now.")
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
    local commands = {}
    local created = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
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

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(error_message)
    assert_equal(workspace.worktree_branch, "dev1/review")
    assert_contains(table.concat(commands, "\n"), "git -C /repo worktree add -b dev1/review /codux-worktrees/review main")
    assert_equal(store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev1/review")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      store = workspace_store().store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo status --porcelain" then
          return " M file.lua\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_equal(error_message, "current branch must be clean before creating a Codux workspace")
    assert_equal(table.concat(commands, "\n"):find("worktree add", 1, true), nil)
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
          return "", 1
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_contains(error_message, "Failed to create tmux window")
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
    local commands = {}
    local killed = false
    local created = false
    local store = workspace_store({
      state_data = {
        projects = {
          ["/repo"] = {
            workspaces = {
              review = review_workspace_record({
                name = "review",
                safe_name = "review",
                project_root = "/repo",
                tmux_window = "review",
                nvim_server = "/tmp/stale-review.sock",
              }),
            },
          },
        },
      },
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
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
    local command_text = table.concat(commands, "\n")
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
    assert_contains(new_window_command, 'initial_mode="plan"')
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
