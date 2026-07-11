local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true
local assert_nil = h.assert_nil

local state_mod = require("codux.state")

local state = state_mod.initial()
assert_true(type(state.workspace_manager) == "table")
assert_true(type(state.mission_dashboard) == "table")
assert_nil(getmetatable(state))

state.workspace_manager.win = 42
assert_equal(state.workspace_manager.win, 42)

state.mission_dashboard.query = "alpha"
assert_equal(state.mission_dashboard.query, "alpha")

state.agent_working = true
assert_true(state.agent_working)

-- Dynamic key accessors (used by dashboard_search / action_palette) map flat
-- UI keys into nested tables without a metatable proxy.
state_mod.set(state, "mission_dashboard_selected_row", 3)
assert_equal(state.mission_dashboard.selected_row, 3)
assert_equal(state_mod.get(state, "mission_dashboard_selected_row"), 3)

state_mod.set(state, "workspace_manager_buf", 7)
assert_equal(state.workspace_manager.buf, 7)
assert_equal(state_mod.get(state, "workspace_manager_buf"), 7)

-- Flat keys on the root table are not magical anymore.
state.mission_dashboard_win = 99
assert_equal(state.mission_dashboard_win, 99)
assert_nil(state.mission_dashboard.win)

print("state_spec.lua: ok")
