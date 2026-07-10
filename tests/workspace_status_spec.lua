local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_true = h.assert_true

local workspace_status = require("codux.workspace_status")

assert_equal(workspace_status.normalize_agent_mode("plan"), "plan")
assert_equal(workspace_status.normalize_agent_mode("execute"), "execute")
assert_equal(workspace_status.normalize_agent_mode("read-only"), nil)
assert_equal(workspace_status.normalize_codex_mode("plan"), "plan")
assert_true(workspace_status.inactive_like_status("inactive"))
assert_true(workspace_status.inactive_like_status("missing"))
assert_false(workspace_status.inactive_like_status("active"))
assert_false(workspace_status.inactive_like_status("idle"))

print("workspace_status_spec.lua: ok")
