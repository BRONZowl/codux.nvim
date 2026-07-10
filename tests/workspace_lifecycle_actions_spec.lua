local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true

local workspace_lifecycle_actions = require("codux.workspace_lifecycle_actions")
local runtime_mod = require("codux.workspace_runtime")

local function project_state(state_data, root)
  state_data.projects = state_data.projects or {}
  state_data.projects[root] = state_data.projects[root] or { workspaces = {} }
  state_data.projects[root].workspaces = state_data.projects[root].workspaces or {}
  return state_data.projects[root]
end

local function runtime(opts)
  opts = type(opts) == "table" and opts or {}
  local state_data = opts.state_data or {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "Review",
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
  local writes = 0
  local notifications = {}
  local killed = {}
  local rendered = false
  return {
    state = opts.state or { workspace_manager_project_root = "/repo" },
    sanitize_workspace_name = runtime_mod.sanitize_workspace_name,
    target_path_exists = function()
      return false
    end,
    workspace_window_name = runtime_mod.workspace_window_name,
    tmux_target = runtime_mod.tmux_target,
    read_state = function()
      return state_data, nil
    end,
    write_state = function(_, next_state)
      writes = writes + 1
      state_data = next_state
      return opts.write_ok ~= false, opts.write_error
    end,
    project_state = function(_, next_state, root)
      return project_state(next_state, root)
    end,
    timestamp = function()
      return "2026-07-05T12:00:00Z"
    end,
    read_instruction_file = function()
      return opts.instruction
    end,
    write_instruction_file = function(_, root, safe_name, instruction)
      opts.written_instruction = { root = root, safe_name = safe_name, instruction = instruction }
      return true, nil
    end,
    instruction_file_path = function(_, root, safe_name)
      return tostring(root) .. "/.agents/codux/" .. tostring(safe_name) .. ".md"
    end,
    delete_instruction_file = function()
      return true, nil
    end,
    current_tmux_session = function()
      return "session"
    end,
    tmux_window_id = function(_, _, window_name)
      return window_name == "review" and "@1" or nil
    end,
    kill_tmux_window = function(_, window_id)
      table.insert(killed, window_id)
      return true
    end,
    kill_tmux_window_deferred = function(_, window_id)
      table.insert(killed, window_id)
    end,
    dashboard_workspace_status = function()
      return "idle"
    end,
    notify = function(message)
      table.insert(notifications, message)
    end,
    render_workspace_manager = function()
      rendered = true
    end,
    close_workspace_manager = function()
      opts.closed_manager = true
    end,
    state_data = function()
      return state_data
    end,
    writes = function()
      return writes
    end,
    notifications = function()
      return notifications
    end,
    killed = function()
      return killed
    end,
    rendered = function()
      return rendered
    end,
  }
end

do
  local rt = runtime()
  local ok, err = workspace_lifecycle_actions.update_saved_workspace_instruction(rt, {
    project_root = "/repo",
    safe_name = "review",
  }, "New instruction")

  assert_true(ok)
  assert_equal(err, nil)
  assert_equal(rt:state_data().projects["/repo"].workspaces.review.resolved_instruction, "New instruction")
  assert_equal(rt:writes(), 1)
  assert_true(rt:rendered())
end

do
  local rt = runtime()
  local ok = workspace_lifecycle_actions.close_all_saved_workspace_windows(rt, "/repo")

  assert_true(ok)
  local record = rt:state_data().projects["/repo"].workspaces.review
  assert_equal(record.status, "inactive")
  assert_equal(record.agent_status, "idle")
  assert_equal(rt:killed()[1], "@1")
  assert_equal(rt:notifications()[1], "Closed 1 Codux workspaces")
end

print("workspace_lifecycle_actions_spec.lua: ok")
