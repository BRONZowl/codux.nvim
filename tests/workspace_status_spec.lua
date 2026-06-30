package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

local runtime_mod = require("codux.workspace_runtime")
local workspace_ui = require("codux.workspace_ui")

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function runtime_with_tmux(responses, state)
  return runtime_mod.new({
    state = state or {},
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      local response = responses[command]
      if response == nil then
        return "", 1
      end
      return response[1], response[2]
    end,
  })
end

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

  assert_equal(runtime:dashboard_workspace_status({ status = "idle", codex_status = "idle" }, nil), "missing")
  assert_equal(runtime:dashboard_workspace_status({ status = "inactive", codex_status = "idle" }, nil), "inactive")
end

do
  assert_equal(workspace_ui.manager_mode_label({ status = "missing", codex_mode = "plan" }), "--")
  assert_equal(workspace_ui.manager_mode_label({ status = "idle", codex_mode = "plan" }), "plan")
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
  assert_equal(record.status, "missing", "activity sync should not revive missing window")
  assert_equal(record.codex_status, "idle")
  assert_equal(record.codex_mode, nil)
  assert_equal(writes, 1)
end

print("workspace_status_spec.lua: ok")
