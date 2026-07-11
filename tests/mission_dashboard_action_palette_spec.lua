local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local mission_control_mod = require("codux.mission_control")

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
      mission_dashboard = {
        win = 10,
      }},
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

print("mission_dashboard_action_palette_spec.lua: ok")
