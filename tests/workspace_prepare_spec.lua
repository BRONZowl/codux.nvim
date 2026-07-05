local h = require("tests.helpers")
local fixtures = require("tests.workspace_fixtures")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_nil = h.assert_nil
local assert_true = h.assert_true

local workspace_prepare = require("codux.workspace_prepare")
local runtime_mod = require("codux.workspace_runtime")

local function runtime(opts)
  opts = type(opts) == "table" and opts or {}
  local state_data = opts.state_data or { projects = {} }
  local cleaned = {}

  return {
    state = opts.state or {},
    sanitize_workspace_name = runtime_mod.sanitize_workspace_name,
    target_path_exists = function(path)
      return type(opts.existing_paths) == "table" and opts.existing_paths[path] == true or false
    end,
    workspace_window_name = runtime_mod.workspace_window_name,
    workspaces_enabled = function()
      return opts.enabled ~= false
    end,
    tmux_cmd = function()
      return "tmux"
    end,
    current_tmux_session = function()
      return opts.session or "session"
    end,
    target_context = function()
      return opts.context or {
        root = "/repo",
        path = "/repo",
        target = { type = "directory" },
        branch = "main",
      }
    end,
    git_checkout_clean = function()
      return opts.clean ~= false, opts.clean_error
    end,
    resolve_worktree_branch = function(_, _, safe_name)
      return opts.branch or ("codux/" .. tostring(safe_name))
    end,
    worktree_path = function(_, root, safe_name)
      return tostring(root) .. "-worktrees/" .. tostring(safe_name)
    end,
    git_current_ref = function()
      return "main"
    end,
    git_rev_parse = function()
      return "abc123"
    end,
    git_common_dir = function()
      return "/repo/.git"
    end,
    create_git_worktree = function()
      opts.created_worktree = true
      return true
    end,
    cleanup_created_worktree = function(_, _, path, branch)
      table.insert(cleaned, { path = path, branch = branch })
    end,
    warn_workspace_instruction_ignore = function() end,
    permission_profile = function()
      return "default"
    end,
    read_state = function()
      return state_data, nil
    end,
    project_state = function(_, next_state, root)
      return fixtures.simple_project_state(next_state, root)
    end,
    read_instruction_file = function()
      return opts.file_instruction
    end,
    tmux_window_id = function(_, _, window_name)
      return type(opts.window_ids) == "table" and opts.window_ids[window_name] or nil
    end,
    instruction_file_path = function(_, worktree_path, safe_name)
      return tostring(worktree_path) .. "/.agents/codux/" .. tostring(safe_name) .. ".md"
    end,
    cleaned = function()
      return cleaned
    end,
  }
end

local function with_tmux(callback)
  return fixtures.with_tmux(callback)
end

with_tmux(function()
  local rt = runtime({
    state_data = {
      projects = {
        ["/repo-worktrees/review"] = {
          workspaces = {
            review = {
              name = "Review",
              safe_name = "review",
            },
          },
        },
      },
    },
  })

  local workspace, err = workspace_prepare.prepare(rt, "Review")
  assert_nil(workspace)
  assert_equal(err, "workspace already exists")
  assert_true(rt.cleaned()[1].path == "/repo-worktrees/review")
end)

with_tmux(function()
  local rt = runtime()
  local ok, err = workspace_prepare.preflight_mission(rt, {
    roles = {
      { workspace_name = "Builder" },
      { workspace_name = "Builder" },
    },
  })

  assert_false(ok)
  assert_equal(err, "Duplicate mission workspace: builder")
end)

with_tmux(function()
  h.with_stubs({
    { target = vim.fn, key = "filereadable", value = function() return 1 end },
  }, function()
    local rt = runtime()
    local ok, err = workspace_prepare.preflight_mission(rt, {
      roles = {
        { workspace_name = "Review" },
      },
    })

    assert_false(ok)
    assert_equal(err, "workspace instruction already exists: /repo-worktrees/review/.agents/codux/review.md")
  end)
end)

do
  local calls = { prepared = 0, deleted = {}, notification = nil }
  local rt = {
    state = {},
    preflight_mission = function()
      return true
    end,
    prepare_workspace = function()
      calls.prepared = calls.prepared + 1
      if calls.prepared == 1 then
        return { safe_name = "builder" }, nil
      end
      return nil, "launch failed"
    end,
    delete_saved_workspace = function(_, workspace)
      table.insert(calls.deleted, workspace.safe_name)
    end,
    notify = function(message)
      calls.notification = message
    end,
  }

  local ok = workspace_prepare.create_mission(rt, {
    name = "Alpha",
    mission_id = "mission:alpha",
    objective = "Build it",
    roles = {
      { name = "Builder", workspace_name = "Builder" },
      { name = "Reviewer", workspace_name = "Reviewer" },
    },
  })

  assert_false(ok)
  assert_equal(calls.deleted[1], "builder")
  assert_equal(calls.notification, "launch failed")
end

print("workspace_prepare_spec.lua: ok")
