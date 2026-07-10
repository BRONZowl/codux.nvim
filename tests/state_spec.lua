local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true
local assert_nil = h.assert_nil

local state_mod = require("codux.state")

local state = state_mod.initial()
assert_true(type(state.workspace_manager) == "table")
assert_true(type(state.mission_dashboard) == "table")

state.workspace_manager_win = 42
assert_equal(state.workspace_manager.win, 42)
assert_equal(state.workspace_manager_win, 42)

state.mission_dashboard_query = "alpha"
assert_equal(state.mission_dashboard.query, "alpha")
assert_equal(state.mission_dashboard_query, "alpha")

state.agent_working = true
assert_true(state.agent_working)

local plain = state_mod.with_ui_proxy({
  workspace_manager_buf = 7,
  mission_dashboard_selected_row = 3,
})
assert_equal(plain.workspace_manager.buf, 7)
assert_equal(plain.mission_dashboard.selected_row, 3)
assert_nil(rawget(plain, "workspace_manager_buf"))

print("state_spec.lua: ok")
