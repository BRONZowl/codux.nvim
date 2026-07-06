local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains
local fixtures = require("tests.mission_control_fixtures")

local mission_control_mod = require("codux.mission_control")
local ui_mod = require("codux.ui")
local workspace_ui = require("codux.workspace_ui")

local mission_role_entry = fixtures.mission_role_entry

if type(vim.api) == "table" then
  local captured_mission
  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_control.test"),
    notify = function() end,
    set_buffer_keymap = function(bufnr, modes, lhs, rhs, desc, opts)
      opts = type(opts) == "table" and opts or {}
      return pcall(vim.keymap.set, modes, lhs, rhs, {
        buffer = bufnr,
        silent = opts.silent ~= false,
        desc = desc,
      })
    end,
    bind_close_keys = function() end,
  })
  function controller:open_preview(mission)
    captured_mission = mission
    return true
  end

  local old_columns = vim.o.columns
  local old_lines = vim.o.lines
  local old_cmdheight = vim.o.cmdheight
  do
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 4 },
      [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
    }
    local calls = {}
    local resize_controller = mission_control_mod.new({
      state = {
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
      },
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
        table.insert(calls, win)
        return true
      end,
    })

    vim.o.columns = 120
    vim.o.lines = 24
    assert_true(resize_controller:resize_dashboard_stack(18, {
      selected_item = { kind = "mission", mission = { name = "Alpha" } },
    }))
    assert_equal(table.concat(calls, ","), "91,92,93")
    assert_equal(configs[91].height, 15)
    assert_equal(configs[92].height, 1)
    assert_equal(configs[93].height, 1)
    assert_equal(configs[92].row, configs[91].row + configs[91].height + 2)
    assert_equal(configs[93].row, configs[92].row + configs[92].height + 2)
    assert_true(configs[93].row + configs[93].height + 2 <= vim.o.lines - vim.o.cmdheight)
    assert_equal(configs[92].width, configs[91].width)
    assert_equal(configs[93].width, configs[91].width)

    calls = {}
    assert_true(resize_controller:resize_dashboard_stack(18, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    }))
    assert_equal(table.concat(calls, ","), "91,92,93")
    assert_equal(configs[91].height, 1)
    assert_equal(configs[92].height, 1)
    assert_equal(configs[93].height, 15)
    assert_equal(configs[92].row, configs[91].row + configs[91].height + 2)
    assert_equal(configs[93].row, configs[92].row + configs[92].height + 2)
    assert_true(configs[93].row + configs[93].height + 2 <= vim.o.lines - vim.o.cmdheight)
    assert_equal(configs[92].width, configs[91].width)
    assert_equal(configs[93].width, configs[91].width)

    calls = {}
    assert_true(resize_controller:resize_dashboard_stack(18, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
      dashboard_min_height = 2,
    }))
    assert_equal(table.concat(calls, ","), "91,92,93")
    assert_equal(configs[91].height, 2)
    assert_equal(configs[92].height, 1)
    assert_equal(configs[93].height, 14)
    assert_equal(configs[92].row, configs[91].row + configs[91].height + 2)
    assert_equal(configs[93].row, configs[92].row + configs[92].height + 2)
    assert_true(configs[93].row + configs[93].height + 2 <= vim.o.lines - vim.o.cmdheight)
    assert_equal(configs[92].width, configs[91].width)
    assert_equal(configs[93].width, configs[91].width)
  end

  do
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 128, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 128, height = 4 },
      [93] = { relative = "editor", row = 0, col = 0, width = 128, height = 6 },
      [94] = { relative = "editor", row = 0, col = 0, width = 128, height = 1 },
    }
    local calls = {}
    local resize_controller = mission_control_mod.new({
      state = {
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
        mission_dashboard_search_win = 94,
      },
      is_valid_win = function(win)
        return win == 91 or win == 92 or win == 93 or win == 94
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
        table.insert(calls, win)
        return true
      end,
    })

    vim.o.columns = 140
    vim.o.lines = 40
    assert_true(resize_controller:resize_dashboard_stack(20, {
      selected_item = { kind = "mission", mission = { name = "Alpha" } },
    }))
    assert_equal(table.concat(calls, ","), "91,94,92,93")
    local compact_dashboard_row = configs[91].row
    local compact_search_row = configs[94].row
    assert_equal(configs[94].row, configs[91].row - 3)
    assert_equal(configs[94].width, configs[91].width)
    assert_equal(configs[92].row, configs[91].row + configs[91].height + 2)
    assert_equal(configs[93].row, configs[92].row + configs[92].height + 2)
    assert_true(configs[93].row + configs[93].height + 2 <= vim.o.lines - vim.o.cmdheight)

    calls = {}
    assert_true(resize_controller:resize_dashboard_stack(20, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    }))
    assert_equal(table.concat(calls, ","), "91,94,92,93")
    assert_true(configs[91].row < compact_dashboard_row)
    assert_true(configs[94].row < compact_search_row)
    assert_equal(configs[94].row, configs[91].row - 3)
    assert_equal(configs[94].width, configs[91].width)
    assert_equal(configs[92].row, configs[91].row + configs[91].height + 2)
    assert_equal(configs[93].row, configs[92].row + configs[92].height + 2)
    assert_true(configs[93].row + configs[93].height + 2 <= vim.o.lines - vim.o.cmdheight)
  end

  do
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 4 },
      [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
    }
    local items = {
      [4] = { kind = "mission", mission = { name = "Alpha" } },
      [7] = { kind = "role", mission = { name = "Alpha" }, entry = { safe_name = "alpha-builder", status = "active" } },
    }
    local controller = mission_control_mod.new({
      state = {
        mission_dashboard_buf = 90,
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
        mission_dashboard_items = items,
        mission_dashboard_selectable_rows = { 4, 7 },
        mission_dashboard_search_confirmed = true,
        mission_dashboard_selected_row = 4,
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
      set_window_cursor = function()
        return true
      end,
      ui = {
        set_lines = function()
          return true
        end,
      },
    })
    function controller:dashboard_lines()
      return { "Mission", "  Builder" }, items, { 4, 7 }, nil
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

    vim.o.columns = 120
    vim.o.lines = 24
    assert_true(controller:render_dashboard())
    local compact_dashboard_height = configs[91].height
    assert_equal(configs[93].height, 1)
    assert_true(controller:move_mission_selection(1))
    assert_equal(controller.state.mission_dashboard_selected_row, 7)
    assert_true(configs[91].height < compact_dashboard_height)
    assert_true(configs[93].height > 1)
  end

  do
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 4 },
      [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
    }
    local items = {
      [4] = { kind = "mission", mission = { name = "Alpha" } },
      [6] = { kind = "role", mission = { name = "Alpha" }, entry = { safe_name = "alpha-builder", status = "active" } },
    }
    local controller = mission_control_mod.new({
      state = {
        mission_dashboard_buf = 90,
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
        mission_dashboard_items = items,
        mission_dashboard_selectable_rows = { 4, 6 },
        mission_dashboard_search_confirmed = true,
        mission_dashboard_selected_row = 6,
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
      ui = {
        set_lines = function()
          return true
        end,
      },
    })
    function controller:dashboard_lines()
      return { "Mission", "usage | 5hr 12% | wk 34%", "", "Alpha", "role", "Builder" }, items, { 4, 6 }, nil
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

    vim.o.columns = 120
    vim.o.lines = 24
    assert_true(controller:render_dashboard())
    assert_equal(configs[91].height, 2)
    assert_equal(configs[93].height, 14)
  end

  do
    local now_ms = 1000
    local refresh_calls = 0
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 1 },
      [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
    }
    local items = {
      [3] = { kind = "mission", mission = { name = "Alpha" } },
    }
    local controller = mission_control_mod.new({
      state = {
        mission_dashboard_buf = 90,
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
        mission_dashboard_items = items,
        mission_dashboard_selectable_rows = { 3 },
        mission_dashboard_search_confirmed = true,
        mission_dashboard_selected_row = 3,
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
      refresh_token_usage = function(force)
        assert_false(force)
        refresh_calls = refresh_calls + 1
        return true
      end,
      token_usage_refresh_ms = function()
        return 60000
      end,
      token_usage_now_ms = function()
        return now_ms
      end,
      ui = {
        set_lines = function()
          return true
        end,
      },
    })
    function controller:dashboard_lines()
      return { "Mission", "usage | 5hr --% | wk --%" }, items, { 3 }, nil
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

    assert_true(controller:render_dashboard())
    assert_equal(refresh_calls, 1)
    assert_true(controller:render_dashboard())
    assert_equal(refresh_calls, 1)
    now_ms = 62000
    assert_true(controller:render_dashboard())
    assert_equal(refresh_calls, 2)
  end

  local codux = require("codux")
  codux.setup({ token_monitor = false })
  assert_true(codux._v5.should_select_permission_profile(nil))
  assert_false(codux._v5.should_select_permission_profile(12))
  assert_equal(codux._v5.remote_show_existing_codex_terminal(), "not_running")
  assert_equal(codux._v5.remote_interrupt_codex_session(), "failed")
  assert_equal(codux._v5.remote_switch_codex_mode(), "failed")

  assert_true(codux._v5.suppress_startup_plan_warning_for_workspace({
    mission_id = "mission:alpha",
  }))
  assert_false(codux._v5.suppress_startup_plan_warning_for_workspace({
    mission_id = "",
  }))
  assert_false(codux._v5.suppress_startup_plan_warning_for_workspace({
    name = "review",
  }))

  local mission_map = vim.fn.maparg("<leader>zm", "n", false, true)
  assert_true(vim.tbl_isempty(mission_map))
  local workspace_create_map = vim.fn.maparg("<leader>zw", "n", false, true)
  assert_true(vim.tbl_isempty(workspace_create_map))
  local workspaces_map = vim.fn.maparg("<leader>zW", "n", false, true)
  assert_true(vim.tbl_isempty(workspaces_map))
  local autopilot_map = vim.fn.maparg("<leader>za", "n", false, true)
  assert_true(vim.tbl_isempty(autopilot_map))
  local danger_map = vim.fn.maparg("<leader>zA", "n", false, true)
  assert_true(vim.tbl_isempty(danger_map))
  local missions_map = vim.fn.maparg("<leader>zM", "n", false, true)
  assert_equal(missions_map.desc, "mission control")
  assert_true(controller:open_objective_editor("Save Test"))
  local bufnr = vim.api.nvim_get_current_buf()
  assert_contains(vim.api.nvim_buf_get_name(bufnr), "codux://mission-objective/")
  assert_equal(vim.b[bufnr].codux_disable_completion, true)
  assert_false(vim.bo[bufnr].modified)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "mission objective" })
  assert_true(vim.bo[bufnr].modified)
  vim.cmd("write")
  assert_equal(captured_mission.name, "Save Test")
  assert_equal(captured_mission.objective, "mission objective")

  local attempted_objective
  assert_true(controller:open_objective_editor("Failed Save", "old objective", {
    on_save = function(_, objective)
      attempted_objective = objective
      return false
    end,
  }))
  local failed_bufnr = vim.api.nvim_get_current_buf()
  assert_false(vim.bo[failed_bufnr].modified)
  vim.api.nvim_buf_set_lines(failed_bufnr, 0, -1, false, { "new objective" })
  assert_true(vim.bo[failed_bufnr].modified)
  vim.cmd("write")
  assert_equal(attempted_objective, "new objective")
  assert_equal(vim.api.nvim_get_current_buf(), failed_bufnr)
  assert_true(vim.bo[failed_bufnr].modified)
  pcall(vim.api.nvim_buf_delete, failed_bufnr, { force = true })
end

print("mission_control_resize_setup_spec.lua: ok")
