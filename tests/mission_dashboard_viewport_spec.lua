local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local mission_control_mod = require("codux.mission_control")

do
  local revealed = {}
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_items = {
        [4] = { kind = "mission", mission = { name = "Alpha" } },
        [7] = {
          kind = "role",
          entry = {
            safe_name = "alpha-builder",
            project_root = "/repo",
            mission_role = "Builder",
            status = "active",
          },
        },
      },
      mission_dashboard_selected_row = 7,
      mission_dashboard_output_entry = {
        safe_name = "alpha-builder",
        project_root = "/repo",
        mission_role = "Builder",
        status = "active",
      },
    },
    is_valid_win = function(win)
      return win == 10
    end,
    reveal_window_row = function(win, row)
      table.insert(revealed, { win = win, row = row })
      return true
    end,
  })
  function controller:output_preview_running()
    return true
  end

  assert_true(controller:reveal_output_preview_row())
  assert_equal(revealed[1].win, 10)
  assert_equal(revealed[1].row, 7)
  assert_equal(controller.state.mission_dashboard_selected_row, 7)
end

do
  local reveal_calls = 0
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_items = {
        [7] = { kind = "role", entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" } },
        [8] = { kind = "role", entry = { safe_name = "alpha-reviewer", project_root = "/repo", status = "active" } },
      },
      mission_dashboard_selected_row = 7,
      mission_dashboard_output_entry = { safe_name = "alpha-reviewer", project_root = "/repo", status = "active" },
    },
    is_valid_win = function(win)
      return win == 10
    end,
    reveal_window_row = function()
      reveal_calls = reveal_calls + 1
      return true
    end,
  })
  function controller:output_preview_running()
    return true
  end

  assert_false(controller:reveal_output_preview_row())
  assert_equal(reveal_calls, 0)

  controller.state.mission_dashboard_output_entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" }
  function controller:output_preview_running()
    return false
  end
  assert_false(controller:reveal_output_preview_row())
  assert_equal(reveal_calls, 0)
end

do
  local old_getwininfo = vim.fn.getwininfo
  local old_win_execute = vim.fn.win_execute
  local window_info = { topline = 5, botline = 9, height = 5 }
  local executed
  vim.fn.getwininfo = function(win)
    assert_equal(win, 10)
    return { window_info }
  end
  vim.fn.win_execute = function(win, command)
    executed = { win = win, command = command }
    return true
  end

  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_items = {
        [7] = { kind = "role", entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" } },
      },
      mission_dashboard_selected_row = 7,
      mission_dashboard_output_entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" },
    },
    is_valid_win = function(win)
      return win == 10
    end,
  })
  function controller:output_preview_running()
    return true
  end

  local anchor = controller:capture_output_preview_anchor()
  assert_equal(anchor.win, 10)
  assert_equal(anchor.row, 7)
  assert_equal(anchor.offset, 2)

  window_info = { topline = 1, botline = 3, height = 3 }
  assert_true(controller:restore_output_preview_anchor(anchor))
  assert_equal(executed.win, 10)
  assert_contains(executed.command, "'topline': 5")
  assert_equal(controller.state.mission_dashboard_selected_row, 7)

  vim.fn.getwininfo = old_getwininfo
  vim.fn.win_execute = old_win_execute
end

do
  local old_getwininfo = vim.fn.getwininfo
  local old_win_execute = vim.fn.win_execute
  local window_info = { topline = 3, botline = 7, height = 5 }
  local executed
  vim.fn.getwininfo = function()
    return { window_info }
  end
  vim.fn.win_execute = function(win, command)
    executed = { win = win, command = command }
    return true
  end

  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_items = {
        [7] = { kind = "role", entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" } },
      },
      mission_dashboard_selected_row = 7,
      mission_dashboard_output_entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" },
    },
    is_valid_win = function(win)
      return win == 10
    end,
  })
  function controller:output_preview_running()
    return true
  end

  local anchor = controller:capture_output_preview_anchor()
  assert_equal(anchor.offset, 4)

  window_info = { topline = 1, botline = 2, height = 2 }
  assert_true(controller:restore_output_preview_anchor(anchor))
  assert_equal(executed.win, 10)
  assert_contains(executed.command, "'topline': 6")

  vim.fn.getwininfo = old_getwininfo
  vim.fn.win_execute = old_win_execute
end

do
  local old_getwininfo = vim.fn.getwininfo
  local old_win_execute = vim.fn.win_execute
  local execute_calls = 0
  vim.fn.getwininfo = function()
    return { { topline = 5, botline = 9, height = 5 } }
  end
  vim.fn.win_execute = function()
    execute_calls = execute_calls + 1
    return true
  end

  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_items = {
        [7] = { kind = "role", entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" } },
        [8] = { kind = "role", entry = { safe_name = "alpha-reviewer", project_root = "/repo", status = "active" } },
      },
      mission_dashboard_selected_row = 7,
      mission_dashboard_output_entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" },
    },
    is_valid_win = function(win)
      return win == 10
    end,
  })
  function controller:output_preview_running()
    return true
  end

  local anchor = controller:capture_output_preview_anchor()
  assert_equal(anchor.row, 7)

  function controller:output_preview_running()
    return false
  end
  assert_false(controller:restore_output_preview_anchor(anchor))
  assert_equal(execute_calls, 0)

  function controller:output_preview_running()
    return true
  end
  controller.state.mission_dashboard_output_entry = { safe_name = "alpha-reviewer", project_root = "/repo", status = "active" }
  assert_false(controller:restore_output_preview_anchor(anchor))
  assert_equal(execute_calls, 0)

  controller.state.mission_dashboard_output_entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" }
  controller.state.mission_dashboard_selected_row = 8
  assert_false(controller:restore_output_preview_anchor(anchor))
  assert_equal(execute_calls, 0)

  vim.fn.getwininfo = old_getwininfo
  vim.fn.win_execute = old_win_execute
end

do
  local old_getwininfo = vim.fn.getwininfo
  vim.fn.getwininfo = function()
    return { { topline = 1, botline = 5, height = 5 } }
  end

  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_items = {
        [7] = { kind = "role", entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" } },
      },
      mission_dashboard_selected_row = 7,
      mission_dashboard_output_entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" },
    },
    is_valid_win = function(win)
      return win == 10
    end,
  })
  function controller:output_preview_running()
    return true
  end

  assert_nil(controller:capture_output_preview_anchor())

  vim.fn.getwininfo = old_getwininfo
end

do
  local old_getwininfo = vim.fn.getwininfo
  local old_win_execute = vim.fn.win_execute
  local executed
  vim.fn.getwininfo = function()
    return { { topline = 5, botline = 9, height = 5 } }
  end
  vim.fn.win_execute = function(win, command)
    executed = { win = win, command = command }
    return true
  end

  local items = {
    [7] = {
      kind = "role",
      entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" },
    },
    [8] = {
      kind = "role",
      entry = { safe_name = "alpha-reviewer", project_root = "/repo", status = "active" },
    },
  }
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_buf = 90,
      mission_dashboard_win = 10,
      mission_dashboard_command_bar_win = 11,
      mission_dashboard_output_win = 12,
      mission_dashboard_output_buf = 13,
      mission_dashboard_items = items,
      mission_dashboard_selectable_rows = { 7, 8 },
      mission_dashboard_selected_row = 7,
      mission_dashboard_output_entry = items[7].entry,
      mission_dashboard_output_key = nil,
    },
    is_loaded_buf = function(bufnr)
      return bufnr == 90 or bufnr == 13
    end,
    is_valid_win = function(win)
      return win == 10 or win == 11 or win == 12
    end,
    get_window_config = function()
      return { relative = "editor", row = 0, col = 0, width = 80, height = 5 }
    end,
    get_window_height = function()
      return 5
    end,
    get_window_width = function()
      return 80
    end,
    set_window_config = function()
      return true
    end,
    ui = {
      set_lines = function()
        return true
      end,
    },
  })
  function controller:dashboard_lines()
    return { "Mission", "", "", "", "", "", "  Builder", "  Reviewer" }, items, { 7, 8 }, nil
  end
  function controller:highlight_dashboard()
    return true
  end
  function controller:render_command_bar()
    return true
  end
  function controller:render_output_panel(entry)
    self.state.mission_dashboard_output_entry = entry
    self.state.mission_dashboard_output_key = self:output_entry_key(entry)
    return true
  end
  function controller:output_preview_running()
    return true
  end

  controller.state.mission_dashboard_output_key = controller:output_entry_key(items[7].entry)
  assert_true(controller:move_mission_selection(1))
  assert_equal(controller.state.mission_dashboard_selected_row, 8)
  assert_equal(controller.state.mission_dashboard_output_entry.safe_name, "alpha-reviewer")
  assert_equal(executed.win, 10)
  assert_contains(executed.command, "'topline': 6")

  vim.fn.getwininfo = old_getwininfo
  vim.fn.win_execute = old_win_execute
end

do
  local old_getwininfo = vim.fn.getwininfo
  vim.fn.getwininfo = function()
    return { { topline = 5, botline = 9, height = 5 } }
  end

  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_items = {
        [7] = { kind = "role", entry = { safe_name = "alpha-builder", project_root = "/repo", status = "inactive" } },
      },
      mission_dashboard_selected_row = 7,
      mission_dashboard_output_entry = { safe_name = "alpha-builder", project_root = "/repo", status = "inactive" },
    },
    is_valid_win = function(win)
      return win == 10
    end,
  })
  function controller:output_preview_running()
    return true
  end

  assert_nil(controller:capture_stationary_output_preview_anchor())

  controller.state.mission_dashboard_items[7] = { kind = "mission", mission = { name = "Alpha" } }
  assert_nil(controller:capture_stationary_output_preview_anchor())

  vim.fn.getwininfo = old_getwininfo
end

do
  local configs = {
    [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
    [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 4 },
    [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
  }
  local items = {
    [4] = { kind = "mission", mission = { name = "Alpha" } },
    [7] = {
      kind = "role",
      mission = { name = "Alpha" },
      entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" },
    },
  }
  local revealed
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_buf = 90,
      mission_dashboard_win = 91,
      mission_dashboard_command_bar_win = 92,
      mission_dashboard_output_win = 93,
      mission_dashboard_items = items,
      mission_dashboard_selectable_rows = { 4, 7 },
      mission_dashboard_selected_row = 7,
      mission_dashboard_output_entry = { safe_name = "alpha-builder", project_root = "/repo", status = "active" },
    },
    is_loaded_buf = function(bufnr)
      return bufnr == 90
    end,
    is_valid_win = function(win)
      return win == 91 or win == 92 or win == 93
    end,
    get_window_config = function(win)
      return configs[win] or {}
    end,
    get_window_height = function(win)
      return configs[win] and configs[win].height or nil
    end,
    get_window_width = function(win)
      return configs[win] and configs[win].width or nil
    end,
    set_window_config = function(win, config)
      configs[win] = config
      return true
    end,
    reveal_window_row = function(win, row)
      revealed = { win = win, row = row }
      return true
    end,
    ui = {
      set_lines = function()
        return true
      end,
    },
  })
  function controller:dashboard_lines()
    return { "Mission", "", "roles", "", "", "", "  Builder" }, items, { 4, 7 }, nil
  end
  function controller:highlight_dashboard()
    return true
  end
  function controller:render_command_bar()
    return true
  end
  function controller:render_output_panel()
    return true
  end
  function controller:output_preview_running()
    return true
  end

  vim.o.columns = 120
  vim.o.lines = 24
  assert_true(controller:render_dashboard())
  assert_equal(revealed.win, 91)
  assert_equal(revealed.row, 7)
  assert_equal(controller.state.mission_dashboard_selected_row, 7)
end

print("mission_dashboard_viewport_spec.lua: ok")
