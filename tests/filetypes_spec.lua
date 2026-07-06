local h = require("tests.helpers")
local assert_true = h.assert_true
local assert_false = h.assert_false

local filetypes = require("codux.filetypes")

assert_true(filetypes.is_mission_control("codux-missions"))
assert_true(filetypes.is_mission_control("codux-mission-preview-footer"))
assert_true(filetypes.is_workspace("codux-workspace-instruction"))
assert_true(filetypes.is_internal("codux"))
assert_true(filetypes.is_internal("codux-mission-question-answer-sink"))
assert_false(filetypes.is_internal("lua"))
assert_false(filetypes.is_mission_control("codux-workspaces"))

print("filetypes_spec.lua: ok")
