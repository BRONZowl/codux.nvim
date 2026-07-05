local h = require("tests.helpers")
local assert_equal = h.assert_equal

local terminal_window = require("codux.terminal_window")

do
  local controller = {}
  assert_equal(terminal_window.dimension(controller, 0.5, 80, 0.85), 40)
  assert_equal(terminal_window.dimension(controller, 12, 80, 0.85), 12)
  assert_equal(terminal_window.dimension(controller, nil, 80, 0.5), 40)
end

do
  local old_columns = vim.o.columns
  local old_lines = vim.o.lines
  local old_cmdheight = vim.o.cmdheight
  vim.o.columns = 100
  vim.o.lines = 40
  vim.o.cmdheight = 1

  local controller = {
    config = function()
      return {
        popup = {
          width = 0.5,
          height = 10,
          border = "rounded",
        },
      }
    end,
    dimension = function(_, value, total, fallback)
      return terminal_window.dimension(nil, value, total, fallback)
    end,
  }

  local config = terminal_window.popup_config(controller)
  assert_equal(config.width, 49)
  assert_equal(config.height, 10)
  assert_equal(config.col, 24)
  assert_equal(config.border, "rounded")

  vim.o.columns = old_columns
  vim.o.lines = old_lines
  vim.o.cmdheight = old_cmdheight
end

print("terminal_window_spec.lua: ok")
