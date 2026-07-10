local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_contains = h.assert_contains

local workspace_remote_actions = require("codux.workspace_remote_actions")
local runtime_mod = require("codux.workspace_runtime")

local function runtime(opts)
  opts = type(opts) == "table" and opts or {}
  local calls = {}
  return {
    workspace_window_name = runtime_mod.workspace_window_name,
    lua_string = function(_, value)
      return ("%q"):format(tostring(value or ""))
    end,
    current_tmux_session = function()
      return opts.session or "session"
    end,
    tmux_window_id = function(_, _, window_name)
      return type(opts.window_ids) == "table" and opts.window_ids[window_name] or nil
    end,
    status_for_window = function(_, window_id)
      return type(opts.window_statuses) == "table" and opts.window_statuses[window_id] or "active"
    end,
    workspace_server_path = function(_, root, safe_name)
      return "/run/" .. tostring(root):gsub("[/%s]+", "-") .. "-" .. tostring(safe_name) .. ".sock"
    end,
    remote_luaeval = function(_, server, expression)
      table.insert(calls, { server = server, expression = expression })
      if type(opts.remote) == "function" then
        return opts.remote(server, expression)
      end
      return "ok", nil
    end,
    tmux_cmd = function()
      return "tmux"
    end,
    tmux_system = function(_, args)
      table.insert(calls, { tmux = table.concat(args, " ") })
      return "", 0
    end,
    kill_tmux_session = function(_, name)
      table.insert(calls, { kill_session = name })
      return true
    end,
    workspace_preview_session_name = function()
      return "codux-preview"
    end,
    calls = function()
      return calls
    end,
    ensure_workspace_remote = function(self, entry)
      return workspace_remote_actions.ensure_workspace_remote(self, entry)
    end,
    remote_workspace_call = function(self, entry, expression, call_opts)
      return workspace_remote_actions.remote_workspace_call(self, entry, expression, call_opts)
    end,
    ensure_workspace_plan_mode = function(self, entry)
      return workspace_remote_actions.ensure_workspace_plan_mode(self, entry)
    end,
  }
end

do
  local rt = runtime({
    window_ids = { review = "@1" },
    window_statuses = { ["@1"] = "active" },
  })
  local workspace, err = workspace_remote_actions.ensure_workspace_remote(rt, {
    safe_name = "review",
    project_root = "/repo",
  })

  assert_nil(err)
  assert_equal(workspace.window_id, "@1")
  assert_equal(workspace.nvim_server, "/run/-repo-review.sock")
end

do
  local rt = runtime({
    window_ids = { review = "@1" },
    window_statuses = { ["@1"] = "active" },
  })
  local ok, err = workspace_remote_actions.send_prompt_to_workspace(rt, {
    safe_name = "review",
    project_root = "/repo",
  }, "  /plan  ")

  assert_true(ok)
  assert_nil(err)
  local command_text = rt:calls()[1].expression .. "\n" .. rt:calls()[2].expression
  assert_contains(command_text, "remote_ensure_plan_mode")
  assert_contains(command_text, "remote_send_to_agent")
  assert_contains(command_text, "  /plan  ")
end

do
  local rt = runtime()
  local ok, err = workspace_remote_actions.select_workspace_question_option(rt, {
    safe_name = "review",
    project_root = "/repo",
  }, "5")

  assert_false(ok)
  assert_equal(err, "Option number must be 1, 2, 3, or 4")
  assert_equal(#rt:calls(), 0)
end

do
  local rt = runtime({
    window_ids = { review = "@1" },
    window_statuses = { ["@1"] = "active" },
    remote = function(_, expression)
      if expression:find("remote_workspace_status", 1, true) then
        return "ready", nil
      end
      return "ok", nil
    end,
  })
  local ok, err = workspace_remote_actions.verify_workspace_launch(rt, {
    safe_name = "review",
    project_root = "/repo",
    window_name = "review",
  })

  assert_true(ok)
  assert_nil(err)
end

do
  local rt = runtime({
    window_ids = { review = "@1" },
    window_statuses = { ["@1"] = "active" },
    remote = function(_, expression)
      if expression:find("remote_workspace_status", 1, true) then
        return "not_running", nil
      end
      return "ok", nil
    end,
  })
  local ok, err = workspace_remote_actions.verify_workspace_launch(rt, {
    safe_name = "review",
    project_root = "/repo",
    window_name = "review",
  }, {
    require_codex = true,
    attempts = 1,
  })

  assert_false(ok)
  assert_equal(err, "workspace agent session is not running")
end

print("workspace_remote_actions_spec.lua: ok")
