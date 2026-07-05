local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_contains = h.assert_contains

local workspace_remote = require("codux.workspace_remote")

assert_equal(workspace_remote.server_path("/repo root", "Builder", "/run/codux"), "/run/codux/repo-root-Builder.sock")
assert_contains(workspace_remote.launch_server_path("/repo root", "Builder Role", "/run/codux"), "/run/codux/ws-Builder-Role-")
assert_equal(
  workspace_remote.preview_session_name({ project_root = "/repo root", safe_name = "Builder Role" }),
  "codux-preview-repo-root-Builder-Role"
)

do
  local calls = {}
  local sleeps = {}
  h.with_stubs({
    {
      target = vim.fn,
      key = "sleep",
      value = function(value)
        table.insert(sleeps, value)
      end,
    },
  }, function()
    local output, err = workspace_remote.remote_luaeval(function(args)
      table.insert(calls, args)
      if #calls == 1 then
        return "warming", 1
      end
      return " ok\n", 0
    end, "/tmp/server.sock", "require('codux').health_info()", {
      attempts = 2,
      sleep_ms = 7,
    })

    assert_equal(output, "ok")
    assert_equal(err, nil)
    assert_equal(#calls, 2)
    assert_equal(sleeps[1], "7m")
    assert_equal(calls[1][1], "--server")
    assert_equal(calls[1][2], "/tmp/server.sock")
    assert_equal(calls[1][3], "--remote-expr")
    assert_contains(calls[1][4], "luaeval")
  end)
end

do
  local output, err = workspace_remote.remote_luaeval(function()
    return "", 1
  end, "", "expr")
  assert_equal(output, nil)
  assert_equal(err, "workspace server is unavailable")
end

print("workspace_remote_spec.lua: ok")
