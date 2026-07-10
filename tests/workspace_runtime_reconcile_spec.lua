local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true

local runtime_mod = require("codux.workspace_runtime")

local function project_state(_, state_data, root)
  state_data.projects = state_data.projects or {}
  state_data.projects[root] = state_data.projects[root] or { workspaces = {} }
  state_data.projects[root].workspaces = state_data.projects[root].workspaces or {}
  return state_data.projects[root]
end

local function worktree_record(path, safe_name, role, fields)
  fields = type(fields) == "table" and fields or {}
  local record = {
    name = safe_name,
    safe_name = safe_name,
    project_root = path,
    target_path = fields.target_path,
    target_type = fields.target_type,
    git_branch = "dev/" .. safe_name,
    workspace_kind = "worktree",
    git_common_dir = "/repo/.git",
    worktree_path = path,
    worktree_branch = "dev/" .. safe_name,
    worktree_base = "main",
    mission_id = "mission:alpha",
    mission_name = "Alpha",
    mission_role = role,
    tmux_window = safe_name,
    nvim_server = fields.nvim_server,
    status = fields.status or "idle",
    agent_status = "idle",
  }
  return record
end

local function runtime_with_state(state_data, opts)
  opts = type(opts) == "table" and opts or {}
  local writes = 0
  local list_calls = 0
  local runtime = runtime_mod.new({
    state = opts.state,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git --git-dir=/repo/.git worktree list --porcelain" then
        list_calls = list_calls + 1
        return opts.worktree_list or "", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        writes = writes + 1
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-07-05T12:00:00Z"
      end,
      project_state = project_state,
    },
  })

  return runtime, {
    writes = function()
      return writes
    end,
    list_calls = function()
      return list_calls
    end,
    state_data = function()
      return state_data
    end,
  }
end

do
  local old_path = "/tmp/codux-reconcile-alpha/alpha-builder"
  local new_path = "/tmp/codux-reconcile-alpha/alpha-builder-moved"
  local old_isdirectory = vim.fn.isdirectory
  vim.fn.isdirectory = function(path)
    return path == new_path and 1 or 0
  end
  local state_data = {
    projects = {
      [old_path] = {
        workspaces = {
          ["alpha-builder"] = worktree_record(old_path, "alpha-builder", "Builder", {
            target_path = old_path .. "/lua/init.lua",
            target_type = "file",
            nvim_server = "/tmp/stale-alpha.sock",
          }),
        },
      },
    },
  }
  local runtime = runtime_with_state(state_data, {
    state = {
      workspace = {
        safe_name = "alpha-builder",
        project_root = old_path,
        worktree_branch = "dev/alpha-builder",
      },
    },
    worktree_list = table.concat({
      "worktree /repo",
      "HEAD aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "branch refs/heads/main",
      "",
      "worktree " .. new_path,
      "HEAD bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "branch refs/heads/dev/alpha-builder",
    }, "\n"),
  })

  local updated, changed, error_message = runtime:reconcile_moved_worktree({
    safe_name = "alpha-builder",
    project_root = old_path,
    workspace_kind = "worktree",
    worktree_path = old_path,
    git_common_dir = "/repo/.git",
    worktree_branch = "dev/alpha-builder",
  })
  assert_nil(error_message)
  assert_true(changed)
  assert_equal(updated.project_root, new_path)
  assert_equal(updated.worktree_path, new_path)
  assert_nil(state_data.projects[old_path].workspaces["alpha-builder"])
  local record = state_data.projects[new_path].workspaces["alpha-builder"]
  assert_equal(record.project_root, new_path)
  assert_equal(record.worktree_path, new_path)
  assert_equal(record.target_path, new_path .. "/lua/init.lua")
  assert_equal(record.nvim_server, "/tmp/stale-alpha.sock")
  assert_equal(runtime.state.workspace.project_root, new_path)
  assert_equal(runtime.state.workspace.worktree_path, new_path)
  vim.fn.isdirectory = old_isdirectory
end

do
  local old_path = "/tmp/codux-reconcile-reviewer/alpha-reviewer"
  local new_path = "/tmp/codux-reconcile-reviewer/alpha-reviewer-moved"
  local old_isdirectory = vim.fn.isdirectory
  vim.fn.isdirectory = function(path)
    return path == new_path and 1 or 0
  end
  local state_data = {
    projects = {
      [old_path] = {
        workspaces = {
          ["alpha-reviewer"] = worktree_record(old_path, "alpha-reviewer", "Reviewer", {
            nvim_server = "/tmp/stale-reviewer.sock",
            status = "inactive",
          }),
        },
      },
    },
  }
  local runtime = runtime_with_state(state_data, {
    worktree_list = table.concat({
      "worktree " .. new_path,
      "HEAD bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "branch refs/heads/dev/alpha-reviewer",
    }, "\n"),
  })

  local changed, error_message = runtime:reconcile_moved_worktrees_for_project("/repo")
  assert_nil(error_message)
  assert_equal(changed, 1)
  local record = state_data.projects[new_path].workspaces["alpha-reviewer"]
  assert_equal(record.project_root, new_path)
  assert_nil(record.nvim_server)
  vim.fn.isdirectory = old_isdirectory
end

do
  local old_builder = "/tmp/codux-reconcile-batch/alpha-builder"
  local new_builder = "/tmp/codux-reconcile-batch/alpha-builder-moved"
  local old_reviewer = "/tmp/codux-reconcile-batch/alpha-reviewer"
  local new_reviewer = "/tmp/codux-reconcile-batch/alpha-reviewer-moved"
  local old_isdirectory = vim.fn.isdirectory
  vim.fn.isdirectory = function(path)
    return (path == new_builder or path == new_reviewer) and 1 or 0
  end
  local state_data = {
    projects = {
      [old_builder] = {
        workspaces = {
          ["alpha-builder"] = worktree_record(old_builder, "alpha-builder", "Builder"),
        },
      },
      [old_reviewer] = {
        workspaces = {
          ["alpha-reviewer"] = worktree_record(old_reviewer, "alpha-reviewer", "Reviewer"),
        },
      },
    },
  }
  local runtime, harness = runtime_with_state(state_data, {
    worktree_list = table.concat({
      "worktree " .. new_builder,
      "HEAD bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "branch refs/heads/dev/alpha-builder",
      "",
      "worktree " .. new_reviewer,
      "HEAD cccccccccccccccccccccccccccccccccccccccc",
      "branch refs/heads/dev/alpha-reviewer",
    }, "\n"),
  })

  local changed, error_message = runtime:reconcile_moved_worktrees_for_project("/repo")
  assert_nil(error_message)
  assert_equal(changed, 2)
  assert_equal(harness.writes(), 1)
  assert_equal(harness.list_calls(), 1)
  assert_equal(state_data.projects[new_builder].workspaces["alpha-builder"].project_root, new_builder)
  assert_equal(state_data.projects[new_reviewer].workspaces["alpha-reviewer"].project_root, new_reviewer)
  vim.fn.isdirectory = old_isdirectory
end

print("workspace_runtime_reconcile_spec.lua: ok")
