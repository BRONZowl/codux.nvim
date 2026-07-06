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


print("workspace_runtime_worktree_spec.lua: ok")
