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
  local old_open_win = vim.api.nvim_open_win
  local old_schedule = vim.schedule
  local create_callback
  local scheduled = {}
  local calls = {}
  local opened = {}
  local buffer_lines = {}
  local window_options = {}
  local created = 0
  vim.api.nvim_open_win = function(bufnr, enter, config)
    table.insert(opened, { bufnr = bufnr, enter = enter, config = config })
    return bufnr + 100
  end
  vim.schedule = function(callback)
    table.insert(scheduled, callback)
  end

  local controller = mission_control_mod.new({
    mission = {
      preview_lines = function()
        return { "Mission preview" }
      end,
    },
    ui = {
      create_scratch_buffer = function()
        created = created + 1
        return created == 1 and 43 or 44
      end,
      set_lines = function(bufnr, lines)
        buffer_lines[bufnr] = lines
      end,
      set_window_options = function(win, opts)
        window_options[win] = opts
      end,
      close_window = function(win)
        table.insert(calls, "close_window:" .. tostring(win))
      end,
      delete_buffer = function(bufnr)
        table.insert(calls, "delete_buffer:" .. tostring(bufnr))
      end,
    },
    is_valid_win = function()
      return true
    end,
    is_loaded_buf = function()
      return true
    end,
    set_buffer_keymap = function(_, _, lhs, rhs)
      if lhs == "<CR>" then
        create_callback = rhs
      elseif lhs == "y" or lhs == "n" then
        error("mission preview should use workspace create confirmation keys")
      end
    end,
    bind_close_keys = function() end,
    create_mission = function()
      table.insert(calls, "create_mission")
      return true
    end,
  })
  function controller:refresh_or_open_dashboard()
    table.insert(calls, "refresh_dashboard")
    return true
  end

  assert_true(controller:open_preview({ name = "Alpha" }))
  assert_equal(opened[1].bufnr, 43)
  assert_true(opened[1].enter)
  assert_true(opened[1].config.focusable)
  assert_nil(opened[1].config.footer)
  assert_equal(opened[1].config.zindex, 80)
  assert_equal(opened[2].bufnr, 44)
  assert_false(opened[2].enter)
  assert_equal(opened[2].config.relative, "win")
  assert_equal(opened[2].config.win, 143)
  assert_equal(opened[2].config.zindex, 81)
  assert_contains(buffer_lines[44][1], "enter create")
  assert_contains(buffer_lines[44][1], "e edit instruction")
  assert_contains(buffer_lines[44][1], "<c-q> cancel")
  assert_false(window_options[143].wrap)
  assert_false(window_options[143].linebreak)
  assert_false(window_options[143].cursorline)
  assert_contains(window_options[143].winhighlight, "Cursor:CoduxMissionPreviewCursor")
  assert_true(type(create_callback) == "function")
  assert_true(create_callback())
  assert_true(create_callback())
  assert_equal(#calls, 0)
  assert_equal(#scheduled, 2)
  scheduled[1]()
  scheduled[2]()
  assert_equal(calls[1], "close_window:144")
  assert_equal(calls[2], "delete_buffer:44")
  assert_equal(calls[3], "close_window:143")
  assert_equal(calls[4], "delete_buffer:43")
  assert_equal(calls[5], "create_mission")
  assert_equal(calls[6], "refresh_dashboard")
  assert_equal(calls[7], nil)

  vim.api.nvim_open_win = old_open_win
  vim.schedule = old_schedule
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_columns = vim.o.columns
  local old_lines = vim.o.lines
  local old_cmdheight = vim.o.cmdheight
  local opened = {}
  local buffer_lines = {}
  local window_options = {}
  local created = 0

  vim.o.columns = 42
  vim.o.lines = 12
  vim.o.cmdheight = 1
  vim.api.nvim_open_win = function(bufnr, enter, config)
    table.insert(opened, { bufnr = bufnr, enter = enter, config = config })
    return bufnr + 100
  end

  local controller = mission_control_mod.new({
    ui = {
      create_scratch_buffer = function()
        created = created + 1
        return created == 1 and 55 or 56
      end,
      set_lines = function(bufnr, lines)
        buffer_lines[bufnr] = lines
      end,
      set_window_options = function(win, opts)
        window_options[win] = opts
      end,
      close_window = function() end,
      delete_buffer = function() end,
    },
    is_valid_win = function()
      return true
    end,
    is_loaded_buf = function()
      return true
    end,
    set_buffer_keymap = function() end,
    bind_close_keys = function() end,
  })

  assert_true(controller:open_preview({
    name = "Alpha",
    objective = string.rep("very long objective ", 12) .. "\nsecond line\nthird line\nfourth line",
    roles = {
      { workspace_name = "alpha-builder", name = "Builder" },
      { workspace_name = "alpha-reviewer", name = "Reviewer" },
      { workspace_name = "alpha-debugger", name = "Debugger" },
      { workspace_name = "alpha-architect", name = "Architect" },
    },
  }))
  assert_equal(opened[1].bufnr, 55)
  assert_true(opened[1].enter)
  assert_true(opened[1].config.focusable)
  assert_equal(opened[1].config.zindex, 80)
  assert_true(#buffer_lines[55] <= opened[1].config.height)
  for _, line in ipairs(buffer_lines[55]) do
    assert_true(workspace_ui.display_width(line) <= opened[1].config.width)
  end
  assert_contains(buffer_lines[55][#buffer_lines[55]], "truncated")
  assert_false(window_options[155].wrap)
  assert_false(window_options[155].linebreak)
  assert_equal(opened[2].bufnr, 56)
  assert_false(opened[2].enter)
  assert_equal(opened[2].config.relative, "win")
  assert_equal(opened[2].config.win, 155)
  assert_contains(buffer_lines[56][1], "enter create")

  vim.api.nvim_open_win = old_open_win
  vim.o.columns = old_columns
  vim.o.lines = old_lines
  vim.o.cmdheight = old_cmdheight
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_schedule = vim.schedule
  local create_callback
  local scheduled
  local dashboard_refreshed = false
  local created = 0
  vim.api.nvim_open_win = function(bufnr)
    return bufnr + 100
  end
  vim.schedule = function(callback)
    scheduled = callback
  end

  local controller = mission_control_mod.new({
    mission = {
      preview_lines = function()
        return { "Mission preview" }
      end,
    },
    ui = {
      create_scratch_buffer = function()
        created = created + 1
        return created == 1 and 45 or 46
      end,
      set_lines = function() end,
      set_window_options = function() end,
      close_window = function() end,
      delete_buffer = function() end,
    },
    is_valid_win = function()
      return true
    end,
    is_loaded_buf = function()
      return true
    end,
    set_buffer_keymap = function(_, _, lhs, rhs)
      if lhs == "<CR>" then
        create_callback = rhs
      end
    end,
    bind_close_keys = function() end,
    create_mission = function()
      return false
    end,
  })
  function controller:refresh_or_open_dashboard()
    dashboard_refreshed = true
    return true
  end

  assert_true(controller:open_preview({ name = "Alpha" }))
  assert_true(type(create_callback) == "function")
  assert_true(create_callback())
  assert_false(dashboard_refreshed)
  assert_true(type(scheduled) == "function")
  scheduled()
  assert_false(dashboard_refreshed)

  vim.api.nvim_open_win = old_open_win
  vim.schedule = old_schedule
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_schedule = vim.schedule
  local cancel_callback
  local edit_callback
  local scheduled
  local calls = {}
  local created = 0
  vim.api.nvim_open_win = function(bufnr)
    return bufnr + 100
  end
  vim.schedule = function(callback)
    scheduled = callback
  end

  local controller = mission_control_mod.new({
    mission = {
      preview_lines = function()
        return { "Mission preview" }
      end,
    },
    ui = {
      create_scratch_buffer = function()
        created = created + 1
        return created == 1 and 47 or 48
      end,
      set_lines = function() end,
      set_window_options = function() end,
      close_window = function(win)
        table.insert(calls, "close_window:" .. tostring(win))
      end,
      delete_buffer = function(bufnr)
        table.insert(calls, "delete_buffer:" .. tostring(bufnr))
      end,
    },
    is_valid_win = function()
      return true
    end,
    is_loaded_buf = function()
      return true
    end,
    set_buffer_keymap = function(_, _, lhs, rhs)
      if lhs == "e" then
        edit_callback = rhs
      end
    end,
    bind_close_keys = function(_, close_fn)
      cancel_callback = close_fn
    end,
    create_mission = function()
      error("no/edit preview actions should not create a mission")
    end,
  })
  function controller:open_objective_editor(name, objective)
    table.insert(calls, "edit:" .. tostring(name) .. ":" .. tostring(objective))
    return true
  end

  assert_true(controller:open_preview({ name = "Alpha", objective = "Build it" }))
  assert_true(type(cancel_callback) == "function")
  assert_true(cancel_callback())
  assert_equal(#calls, 0)
  assert_true(type(scheduled) == "function")
  scheduled()
  assert_equal(calls[1], "close_window:148")
  assert_equal(calls[2], "delete_buffer:48")
  assert_equal(calls[3], "close_window:147")
  assert_equal(calls[4], "delete_buffer:47")

  calls = {}
  scheduled = nil
  created = 0
  assert_true(controller:open_preview({ name = "Alpha", objective = "Build it" }))
  assert_true(type(edit_callback) == "function")
  assert_true(edit_callback())
  assert_equal(#calls, 0)
  assert_true(type(scheduled) == "function")
  scheduled()
  assert_equal(calls[1], "close_window:148")
  assert_equal(calls[2], "delete_buffer:48")
  assert_equal(calls[3], "close_window:147")
  assert_equal(calls[4], "delete_buffer:47")
  assert_equal(calls[5], "edit:Alpha:Build it")

  vim.api.nvim_open_win = old_open_win
  vim.schedule = old_schedule
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_win_set_cursor = vim.api.nvim_win_set_cursor
  local opened = {}
  local window_options = {}
  local cursor_set
  local bound = {}
  local created = 0
  local ran_action
  vim.api.nvim_open_win = function(bufnr, enter, config)
    table.insert(opened, {
      bufnr = bufnr,
      enter = enter,
      config = config,
    })
    return bufnr + 10
  end
  vim.api.nvim_win_set_cursor = function(_, cursor)
    cursor_set = cursor
    return true
  end

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard_win = 10,
    },
    is_valid_win = function(win)
      return win == 10
    end,
    is_loaded_buf = function()
      return true
    end,
    get_window_config = function()
      return { col = 0, row = 0 }
    end,
    get_window_width = function()
      return 80
    end,
    get_window_height = function()
      return 10
    end,
    ui = {
      create_scratch_buffer = function()
        created = created + 1
        return created == 1 and 31 or 32
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function(win, opts)
        window_options[win] = opts
      end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, _, lhs, rhs)
      bound[lhs] = rhs
    end,
  })
  function controller:start_selected_mission(mission)
    ran_action = "start:" .. tostring(mission.name)
    return true
  end

  assert_true(controller:open_action_palette_for({ name = "Alpha" }, "mission"))
  assert_equal(opened[1].bufnr, 31)
  assert_false(opened[1].enter)
  assert_false(opened[1].config.focusable)
  assert_equal(opened[2].bufnr, 32)
  assert_true(opened[2].enter)
  assert_equal(window_options[41].cursorline, false)
  assert_contains(window_options[41].winhighlight, "Cursor:CoduxActionPaletteCursor")
  assert_equal(cursor_set, nil)
  assert_equal(bound["<CR>"], nil)
  assert_equal(bound.j, nil)
  assert_equal(bound.k, nil)
  assert_true(type(bound.s) == "function")
  assert_true(bound.s())
  assert_equal(ran_action, "start:Alpha")
  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_win_set_cursor = old_win_set_cursor
end

do
  local old_mouse = vim.o.mouse
  vim.o.mouse = "a"
  local controller = mission_control_mod.new({ state = {} })

  assert_true(controller:lock_dashboard_mouse())
  assert_equal(vim.o.mouse, "")
  assert_equal(controller.state.mission_dashboard_saved_mouse, "a")

  vim.o.mouse = "n"
  assert_true(controller:lock_dashboard_mouse())
  assert_equal(vim.o.mouse, "")
  assert_equal(controller.state.mission_dashboard_saved_mouse, "a")

  assert_true(controller:restore_dashboard_mouse())
  assert_equal(vim.o.mouse, "a")
  assert_nil(controller.state.mission_dashboard_saved_mouse)
  vim.o.mouse = old_mouse
end

if type(vim.api) == "table" then
  local old_mouse = vim.o.mouse
  local old_open_win = vim.api.nvim_open_win
  local deleted_buf
  vim.o.mouse = "a"
  vim.api.nvim_open_win = function()
    error("open failed")
  end

  local controller = mission_control_mod.new({
    notify = function() end,
    ui = {
      create_scratch_buffer = function()
        return 33
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function(bufnr)
        deleted_buf = bufnr
      end,
    },
  })
  function controller:mission_count()
    return 1
  end
  function controller:dashboard_lines()
    return { "Mission" }, {}, {}, nil
  end
  function controller:highlight_dashboard() end

  assert_false(controller:open_dashboard("/repo"))
  assert_equal(vim.o.mouse, "a")
  assert_nil(controller.state.mission_dashboard_saved_mouse)
  assert_equal(deleted_buf, 33)

  vim.api.nvim_open_win = old_open_win
  vim.o.mouse = old_mouse
end

if type(vim.api) == "table" then
  local old_mouse = vim.o.mouse
  local controller = mission_control_mod.new({ state = {} })
  vim.o.mouse = "a"

  assert_true(controller:lock_dashboard_mouse())
  assert_equal(vim.o.mouse, "")
  assert_true(controller:close_dashboard())
  assert_equal(vim.o.mouse, "a")
  assert_nil(controller.state.mission_dashboard_saved_mouse)
  vim.o.mouse = old_mouse
end

print("mission_control_preview_actions_spec.lua: ok")
