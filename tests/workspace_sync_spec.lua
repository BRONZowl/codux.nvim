local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true

local workspace_sync = require("codux.workspace_sync")
local runtime_mod = require("codux.workspace_runtime")

local function runtime(opts)
  opts = type(opts) == "table" and opts or {}
  local state_data = opts.state_data or {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
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
  local writes = 0
  local rendered = false
  return {
    state = opts.state or {
      workspace_manager_project_root = "/repo",
      workspace = {
        safe_name = "review",
        project_root = "/repo",
        window_name = "review",
      },
    },
    tmux_target = runtime_mod.tmux_target,
    normalize_codex_mode = function(_, mode)
      return mode == "execute" and "execute" or mode == "plan" and "plan" or nil
    end,
    read_state = function()
      return state_data, nil
    end,
    write_state = function(_, next_state)
      writes = writes + 1
      state_data = next_state
      return true
    end,
    current_tmux_session = function()
      return "session"
    end,
    tmux_window_id = function()
      return "@1"
    end,
    dashboard_workspace_status = function(_, _, window_id)
      return window_id and "idle" or "inactive"
    end,
    timestamp = function()
      return "2026-07-05T12:00:00Z"
    end,
    render_workspace_manager = function()
      rendered = true
    end,
    state_data = function()
      return state_data
    end,
    writes = function()
      return writes
    end,
    rendered = function()
      return rendered
    end,
  }
end

do
  local rt = runtime()
  assert_true(workspace_sync.sync_activity(rt, "working"))
  local record = rt:state_data().projects["/repo"].workspaces.review
  assert_equal(record.codex_status, "working")
  assert_equal(record.status, "active")
  assert_equal(rt.state.workspace.status, "active")
  assert_equal(rt:writes(), 1)
  assert_true(rt:rendered())
end

do
  local rt = runtime()
  assert_true(workspace_sync.sync_mode(rt, "plan"))
  local record = rt:state_data().projects["/repo"].workspaces.review
  assert_equal(record.codex_mode, "plan")
  assert_equal(rt.state.workspace.codex_mode, "plan")
  assert_equal(rt:writes(), 1)
end

print("workspace_sync_spec.lua: ok")
