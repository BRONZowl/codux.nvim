local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_true = h.assert_true
local assert_nil = h.assert_nil

local terminal_mode = require("codux.terminal_mode")

assert_equal(terminal_mode.mode_display_label("execute"), "exec")
assert_equal(terminal_mode.mode_display_label("plan"), "plan")
assert_equal(terminal_mode.mode_display_label(nil), "not running")

assert_equal(terminal_mode.detect_terminal_mode_from_line("mode: plan"), "plan")
assert_equal(terminal_mode.detect_terminal_mode_from_line("codex mode: execute"), "execute")
assert_equal(terminal_mode.detect_terminal_mode_from_line("plan mode (shift+tab to cycle)"), "plan")
assert_nil(terminal_mode.detect_terminal_mode_from_line("hello world"))

local mode = terminal_mode.detect_terminal_mode_from_lines({
  "noise",
  "mode: plan",
  "more noise",
})
assert_equal(mode, "plan")

assert_true(terminal_mode.output_looks_like_question({
  "Would you like me to continue?",
}))
assert_false(terminal_mode.output_looks_like_question({
  "Working on the patch.",
}))

assert_true(terminal_mode.terminal_prompt_is_plan_toggle("/plan", true))
assert_false(terminal_mode.terminal_prompt_is_plan_toggle("ship it", true))

print("terminal_mode_spec.lua: ok")
