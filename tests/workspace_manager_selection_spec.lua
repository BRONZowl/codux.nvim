local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true

local selection = require("codux.workspace_manager_selection")

do
  vim.api = vim.api or {}
  local cursor = { 3, 0 }
  local old_get_cursor = vim.api.nvim_win_get_cursor
  vim.api.nvim_win_get_cursor = function(win)
    assert_equal(win, 10)
    return cursor
  end

  local controller = {
    state = {
      workspace_manager_win = 10,
      workspace_manager_items = {
        { name = "one" },
        { name = "two" },
        { name = "three" },
      },
    },
    is_valid_win = function(win)
      return win == 10
    end,
  }

  assert_equal(selection.selected_item(controller).name, "two")
  controller.state.workspace_manager_search_confirmed = true
  controller.state.workspace_manager_selected_index = 3
  assert_equal(selection.selected_item(controller).name, "three")

  vim.api.nvim_win_get_cursor = old_get_cursor
end

do
  local rendered = 0
  local focused
  local cursor
  local controller = {
    state = {
      workspace_manager_win = 10,
      workspace_manager_items = {
        { name = "one" },
        { name = "two" },
        { name = "three" },
      },
      workspace_manager_best_match_index = 2,
    },
    is_valid_win = function(win)
      return win == 10
    end,
    set_window_cursor = function(win, next_cursor)
      cursor = { win = win, row = next_cursor[1], col = next_cursor[2] }
      return true
    end,
    set_current_win = function(win)
      focused = win
      return true
    end,
    render = function()
      rendered = rendered + 1
      return true
    end,
    workspace_list_focus_row = function(self)
      return selection.workspace_list_focus_row(self)
    end,
  }

  assert_equal(selection.workspace_list_focus_row(controller), 3)
  assert_true(selection.focus_workspace_list(controller))
  assert_equal(focused, 10)
  assert_equal(cursor.row, 3)
  assert_true(selection.move_workspace_selection(controller, 1))
  assert_equal(controller.state.workspace_manager_selected_index, 3)
  assert_equal(rendered, 1)
  assert_equal(cursor.row, 4)
end

print("workspace_manager_selection_spec.lua: ok")
