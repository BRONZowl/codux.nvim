local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true
local assert_false = h.assert_false

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
