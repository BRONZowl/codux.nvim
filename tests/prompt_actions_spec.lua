local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local prompt_actions_mod = require("codux.prompt_actions")

do
  local selected = prompt_actions_mod.selection_from_lines({ "abcdef", "ghijkl" }, 2, 4, "V")
  assert_equal(selected, "abcdef\nghijkl")
end

do
  local selected = prompt_actions_mod.selection_from_lines({ "abcdef", "ghijkl" }, 2, 4, "v")
  assert_equal(selected, "bcdef\nghij")
end

do
  local selected = prompt_actions_mod.selection_from_lines({ "abcdef", "ghijkl" }, 2, 4, "\22")
  assert_equal(selected, "bcd\nhij")
end

do
  local selected = prompt_actions_mod.selection_from_lines({ "abcdef", "ghijkl" }, 2, 4, "\19")
  assert_equal(selected, "bcd\nhij")
end

do
  local actions = prompt_actions_mod.new({
    current_buffer = function()
      return 1
    end,
    buffer_lines = function(_, start_line, end_line)
      assert_equal(start_line, 0)
      assert_equal(end_line, 2)
      return { "abcdef", "ghijkl" }
    end,
  })
  local selected, start_line, end_line = actions:selection_from_positions({ 0, 2, 2, 0 }, { 0, 1, 4, 0 }, "\22")
  assert_equal(selected, "bcd\nhij")
  assert_equal(start_line, 1)
  assert_equal(end_line, 2)
end

do
  local actions = prompt_actions_mod.new({
    current_buffer = function()
      return 1
    end,
    buffer_lines = function(_, start_line, end_line)
      assert_equal(start_line, 0)
      assert_equal(end_line, 1)
      return { "abcdef" }
    end,
  })
  local selected, start_line, end_line = actions:selection_from_positions({ 0, 1, 4, 0 }, { 0, 1, 2, 0 }, "\22")
  assert_equal(selected, "bcd")
  assert_equal(start_line, 1)
  assert_equal(end_line, 1)
end

do
  local actions = prompt_actions_mod.new({
    current_buffer = function()
      return 1
    end,
    buffer_lines = function(_, start_line, end_line)
      assert_equal(start_line, 0)
      assert_equal(end_line, 2)
      return { "abcdef", "ghijkl" }
    end,
  })
  local selected, start_line, end_line = actions:selection_from_positions({ 0, 2, 2, 0 }, { 0, 1, 4, 0 }, "\19")
  assert_equal(selected, "bcd\nhij")
  assert_equal(start_line, 1)
  assert_equal(end_line, 2)
end

print("prompt_actions_spec.lua: ok")
