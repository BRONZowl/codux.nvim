local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local mission_control_mod = require("codux.mission_control")

local function with_editor_size(columns, lines, callback)
  local old_columns = vim.o.columns
  local old_lines = vim.o.lines
  local old_cmdheight = vim.o.cmdheight
  vim.o.columns = columns
  vim.o.lines = lines
  vim.o.cmdheight = 1

  local ok, err = pcall(callback)
  vim.o.columns = old_columns
  vim.o.lines = old_lines
  vim.o.cmdheight = old_cmdheight
  if not ok then
    error(err, 0)
  end
end

do
  local controller = mission_control_mod.new({})

  with_editor_size(42, 12, function()
    local objective_config = controller:objective_editor_config(20)
    local preview_config = controller:preview_config(20)
    local dashboard_config = controller:dashboard_config(20)
    local command_config = controller:dashboard_command_config(3)
    local output_config = controller:dashboard_output_config(2)

    assert_equal(objective_config.title, " Codux Mission Objective ")
    assert_equal(preview_config.title, " Codux Mission Control ")
    assert_contains(preview_config.footer, "y yes")
    assert_contains(preview_config.footer, "n no")
    assert_contains(preview_config.footer, "e edit instruction")
    assert_false(preview_config.focusable)
    assert_equal(objective_config.zindex, 80)
    assert_equal(preview_config.zindex, 80)
    assert_equal(dashboard_config.title, " Mission Control ")
    assert_contains(dashboard_config.footer, "Commands shown below")
    assert_equal(dashboard_config.footer:find("Enter open", 1, true), nil)
    assert_equal(dashboard_config.footer:find("Tab search", 1, true), nil)
    assert_equal(dashboard_config.footer:find("m menu", 1, true), nil)
    assert_equal(dashboard_config.footer:find("p prompt", 1, true), nil)
    assert_equal(dashboard_config.footer:find("O preview", 1, true), nil)
    assert_equal(dashboard_config.footer:find("e edit", 1, true), nil)
    assert_equal(dashboard_config.footer:find("x close", 1, true), nil)
    assert_equal(dashboard_config.footer:find("d delete", 1, true), nil)
    assert_equal(dashboard_config.footer:find("n mission", 1, true), nil)
    assert_equal(dashboard_config.footer:find("w workspace", 1, true), nil)
    assert_equal(dashboard_config.footer:find("q close", 1, true), nil)
    assert_equal(dashboard_config.footer:find("output above", 1, true), nil)
    assert_equal(dashboard_config.footer:find("r refresh", 1, true), nil)
    assert_true(objective_config.width <= 38)
    assert_true(preview_config.width <= 38)
    assert_true(dashboard_config.width <= 38)
    assert_true(objective_config.height <= 7)
    assert_true(preview_config.height <= 7)
    assert_true(dashboard_config.height <= 7)
    assert_equal(command_config.title, " Commands ")
    assert_equal(command_config.focusable, false)
    assert_equal(output_config.title, " Output ")
    assert_equal(output_config.focusable, false)
    assert_nil(output_config.footer)
    assert_true(preview_config.zindex > command_config.zindex)
    assert_true(preview_config.zindex > output_config.zindex)

    local search_config = controller:dashboard_search_config()
    assert_true(preview_config.zindex > search_config.zindex)
  end)

  with_editor_size(140, 40, function()
    assert_equal(controller:objective_editor_config(20).width, 96)
    assert_equal(controller:preview_config(20).width, 92)
    assert_equal(controller:dashboard_config(20).width, 128)
  end)
end

do
  local controller = mission_control_mod.new({})
  local old_is_valid_win = controller.is_valid_win
  local old_get_window_config = controller.get_window_config
  local old_get_window_height = controller.get_window_height
  local old_get_window_width = controller.get_window_width

  with_editor_size(120, 24, function()
    local reserved_dashboard_config = controller:dashboard_config(18, {
      reserve_command_bar = true,
      reserve_output_panel = true,
    })
    local reserved_command_config
    controller.state.mission_dashboard_win = 91
    controller.state.mission_dashboard_command_bar_win = 92
    controller.is_valid_win = function(win)
      return win == 91 or win == 92
    end
    controller.get_window_config = function(win)
      if win == 92 then
        return reserved_command_config
      end
      return reserved_dashboard_config
    end
    controller.get_window_height = function(win)
      if win == 92 and reserved_command_config then
        return reserved_command_config.height
      end
      return reserved_dashboard_config.height
    end
    controller.get_window_width = function()
      return reserved_dashboard_config.width
    end

    reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
    local reserved_output_config = controller:dashboard_output_config(2)
    assert_equal(reserved_dashboard_config.height, 15)
    assert_equal(reserved_output_config.height, 1)
    assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
    assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
    assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)

    reserved_dashboard_config = controller:dashboard_config(18, {
      reserve_command_bar = true,
      reserve_output_panel = true,
      selected_item = { kind = "mission", mission = { name = "Alpha" } },
    })
    reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
    reserved_output_config = controller:dashboard_output_config(2, {
      selected_item = { kind = "mission", mission = { name = "Alpha" } },
    })
    assert_equal(reserved_dashboard_config.height, 15)
    assert_equal(reserved_output_config.height, 1)
    assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
    assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
    assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)

    assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = { status = "inactive" } }), "compact")
    assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = {} }), "compact")
    assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = { status = "active" } }), "workspace")
    assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = { status = "idle" } }), "workspace")
    assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = { status = "question" } }), "workspace")

    reserved_dashboard_config = controller:dashboard_config(18, {
      reserve_command_bar = true,
      reserve_output_panel = true,
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder" } },
    })
    reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
    reserved_output_config = controller:dashboard_output_config(2, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder" } },
    })
    assert_equal(reserved_dashboard_config.height, 15)
    assert_equal(reserved_output_config.height, 1)

    reserved_dashboard_config = controller:dashboard_config(18, {
      reserve_command_bar = true,
      reserve_output_panel = true,
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    })
    reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
    reserved_output_config = controller:dashboard_output_config(2, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    })
    assert_equal(reserved_dashboard_config.height, 1)
    assert_equal(reserved_output_config.height, 15)
    assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
    assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
    assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)

    reserved_dashboard_config = controller:dashboard_config(18, {
      reserve_command_bar = true,
      reserve_output_panel = true,
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
      dashboard_min_height = 2,
    })
    reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
    reserved_output_config = controller:dashboard_output_config(2, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
      dashboard_min_height = 2,
    })
    assert_equal(reserved_dashboard_config.height, 2)
    assert_equal(reserved_output_config.height, 14)

    for _, status in ipairs({ "idle", "question" }) do
      reserved_dashboard_config = controller:dashboard_config(18, {
        reserve_command_bar = true,
        reserve_output_panel = true,
        selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = status } },
      })
      reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
      reserved_output_config = controller:dashboard_output_config(2, {
        selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = status } },
      })
      assert_equal(reserved_dashboard_config.height, 1)
      assert_equal(reserved_output_config.height, 15)
      assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
      assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
      assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)
    end
  end)

  with_editor_size(140, 40, function()
    local reserved_dashboard_config = controller:dashboard_config(20, {
      reserve_command_bar = true,
      reserve_output_panel = true,
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    })
    local reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
    local reserved_output_config = controller:dashboard_output_config(2, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    })
    assert_equal(reserved_output_config.height, 31)
    assert_true(reserved_dashboard_config.height >= 1)
    assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
    assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
    assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)
  end)

  with_editor_size(42, 12, function()
    local reserved_dashboard_config = controller:dashboard_config(20, {
      reserve_command_bar = true,
      reserve_output_panel = true,
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    })
    local reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
    local reserved_output_config = controller:dashboard_output_config(2, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    })
    assert_equal(reserved_output_config.height, 3)
    assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
    assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
    assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)
  end)

  controller.is_valid_win = old_is_valid_win
  controller.get_window_config = old_get_window_config
  controller.get_window_height = old_get_window_height
  controller.get_window_width = old_get_window_width
end

do
  local configs = {
    [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
    [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 4 },
    [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
  }
  local calls = {}
  local controller = mission_control_mod.new({
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

  with_editor_size(120, 24, function()
    assert_true(controller:resize_dashboard_stack(18, {
      selected_item = { kind = "mission", mission = { name = "Alpha" } },
    }))
    assert_equal(table.concat(calls, ","), "91,92,93")
    assert_equal(configs[91].height, 15)
    assert_equal(configs[92].height, 1)
    assert_equal(configs[93].height, 1)

    calls = {}
    assert_true(controller:resize_dashboard_stack(18, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    }))
    assert_equal(table.concat(calls, ","), "91,92,93")
    assert_equal(configs[91].height, 1)
    assert_equal(configs[92].height, 1)
    assert_equal(configs[93].height, 15)

    calls = {}
    assert_true(controller:resize_dashboard_stack(18, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
      dashboard_min_height = 2,
    }))
    assert_equal(table.concat(calls, ","), "91,92,93")
    assert_equal(configs[91].height, 2)
    assert_equal(configs[92].height, 1)
    assert_equal(configs[93].height, 14)
  end)
end

do
  local configs = {
    [91] = { relative = "editor", row = 0, col = 0, width = 128, height = 8 },
    [92] = { relative = "editor", row = 0, col = 0, width = 128, height = 4 },
    [93] = { relative = "editor", row = 0, col = 0, width = 128, height = 6 },
    [94] = { relative = "editor", row = 0, col = 0, width = 128, height = 1 },
  }
  local calls = {}
  local controller = mission_control_mod.new({
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

  with_editor_size(140, 40, function()
    assert_true(controller:resize_dashboard_stack(20, {
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
    assert_true(controller:resize_dashboard_stack(20, {
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
  end)
end

print("mission_dashboard_layout_spec.lua: ok")
