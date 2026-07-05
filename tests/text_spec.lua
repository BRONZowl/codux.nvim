local h = require("tests.helpers")
local assert_equal = h.assert_equal

local text = require("codux.text")

assert_equal(text.trim("  alpha  "), "alpha")
assert_equal(select("#", text.trim(" alpha ")), 1)
assert_equal(text.display_width("alpha"), 5)
assert_equal(text.truncate_display_tail("alpha-builder", 8), "...ilder")
assert_equal(text.pad_display_right("alpha", 7), "alpha  ")
assert_equal(text.center_display_line("alpha", 9), "  alpha")

print("text_spec.lua: ok")
