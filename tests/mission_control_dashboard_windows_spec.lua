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

do
  local current_win = 20
  local cursors = {}
  local render_count = 0
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_search_win = 20,
      mission_dashboard_command_win = 30,
      mission_dashboard_items = {
        [4] = { kind = "mission", mission = { name = "Alpha" } },
        [7] = { kind = "role", mission = { name = "Alpha" }, entry = { name = "alpha-builder" } },
        [8] = { kind = "role", mission = { name = "Alpha" }, entry = { name = "alpha-reviewer" } },
      },
      mission_dashboard_selectable_rows = { 4, 7, 8 },
      mission_dashboard_best_match_row = 7,
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 7,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20 or win == 30
    end,
    get_current_win = function()
      return current_win
    end,
    set_current_win = function(win)
      current_win = win
      return true
    end,
    set_window_cursor = function(win, cursor)
      cursors[win] = cursor
      return true
    end,
  })
  function controller:render_dashboard()
    render_count = render_count + 1
    return true
  end

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 30)
  assert_nil(cursors[10])

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 20)

  assert_true(controller:move_mission_selection(1))
  assert_equal(controller.state.mission_dashboard_selected_row, 8)
  assert_nil(cursors[10])
  assert_equal(controller:selected_item().entry.name, "alpha-reviewer")

  assert_true(controller:move_mission_selection(1))
  assert_equal(controller.state.mission_dashboard_selected_row, 8)

  assert_true(controller:move_mission_selection(-1))
  assert_equal(controller.state.mission_dashboard_selected_row, 7)
  assert_equal(controller:selected_item().entry.name, "alpha-builder")
  assert_equal(controller:selected_mission().name, "Alpha")
  assert_equal(render_count, 3)
end

do
  local current_win = nil
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_search_win = 20,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20
    end,
    set_current_win = function(win)
      current_win = win
      return true
    end,
  })

  assert_true(controller:open_search_input({ focus = false }))
  assert_nil(current_win)
  assert_true(controller:open_search_input())
  assert_equal(current_win, 20)
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_create_augroup = vim.api.nvim_create_augroup
  local old_create_autocmd = vim.api.nvim_create_autocmd
  local enter_rhs
  local focused_win
  vim.api.nvim_open_win = function()
    return 20
  end
  vim.api.nvim_create_augroup = function()
    return 91
  end
  vim.api.nvim_create_autocmd = function() end

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_command_win = 30,
      mission_dashboard_best_match_row = 7,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20 or win == 30
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
    ui = {
      create_scratch_buffer = function()
        return 31
      end,
      printable_prompt_keys = function()
        return {}
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, _, lhs, rhs)
      if lhs == "<CR>" then
        enter_rhs = rhs
      end
    end,
    set_current_win = function(win)
      focused_win = win
      return true
    end,
  })
  function controller:render_dashboard()
    return true
  end

  assert_true(controller:open_search_input())
  assert_true(enter_rhs())
  assert_equal(controller.state.mission_dashboard_selected_row, 7)
  assert_equal(focused_win, 10)

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_create_augroup = vim.api.nvim_create_augroup
  local old_create_autocmd = vim.api.nvim_create_autocmd
  local search_config
  vim.api.nvim_open_win = function(_, _, config)
    search_config = config
    return 20
  end
  vim.api.nvim_create_augroup = function()
    return 91
  end
  vim.api.nvim_create_autocmd = function() end

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard_win = 10,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20
    end,
    is_loaded_buf = function()
      return true
    end,
    get_window_config = function()
      return { col = 5, row = 10, width = 88, height = 8 }
    end,
    get_window_width = function()
      return 88
    end,
    ui = {
      create_scratch_buffer = function()
        return 31
      end,
      printable_prompt_keys = function()
        return {}
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function() end,
  })

  assert_true(controller:open_search_input())
  assert_equal(search_config.title, " Search Codux missions: ")
  assert_equal(search_config.width, 88)
  assert_equal(search_config.height, 1)
  assert_equal(search_config.col, 5)
  assert_equal(search_config.row, 7)

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local window_config
  local window_enter
  vim.api.nvim_open_win = function(_, enter, config)
    window_enter = enter
    window_config = config
    return 40
  end

  local controller = mission_control_mod.new({
    state = {},
    is_loaded_buf = function()
      return true
    end,
    ui = {
      create_scratch_buffer = function()
        return 31
      end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function() end,
  })

  assert_true(controller:open_command_sink())
  assert_true(window_enter)
  assert_equal(window_config.focusable, true)
  vim.api.nvim_open_win = old_open_win
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_create_augroup = vim.api.nvim_create_augroup
  local old_create_autocmd = vim.api.nvim_create_autocmd
  local window_config
  local rendered_lines
  vim.api.nvim_open_win = function(_, _, config)
    window_config = config
    return 42
  end
  vim.api.nvim_create_augroup = function()
    return 93
  end
  vim.api.nvim_create_autocmd = function() end

  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
    },
    is_loaded_buf = function(bufnr)
      return bufnr == 32
    end,
    is_valid_win = function(win)
      return win == 10 or win == 42
    end,
    get_window_config = function()
      return { col = 2, row = 3 }
    end,
    get_window_height = function()
      return 8
    end,
    get_window_width = function()
      return 140
    end,
    ui = {
      create_scratch_buffer = function()
        return 32
      end,
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
  })

  assert_true(controller:open_command_bar())
  assert_equal(window_config.title, " Commands ")
  assert_equal(window_config.focusable, false)
  assert_equal(controller.state.mission_dashboard_command_bar_buf, 32)
  assert_equal(controller.state.mission_dashboard_command_bar_win, 42)
  local command_text = table.concat(rendered_lines, "\n")
  assert_contains(command_text, "Tab search")
  assert_equal(command_text:find("O preview", 1, true), nil)
  assert_equal(command_text:find("e edit", 1, true), nil)
  assert_equal(command_text:find("x close", 1, true), nil)
  assert_equal(command_text:find("d delete", 1, true), nil)
  assert_equal(command_text:find("q close", 1, true), nil)

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
end

if type(vim.api) == "table" then
  local old_mouse = vim.o.mouse
  local old_guicursor = vim.o.guicursor
  local old_open_win = vim.api.nvim_open_win
  local old_create_augroup = vim.api.nvim_create_augroup
  local old_create_autocmd = vim.api.nvim_create_autocmd
  local old_set_hl = vim.api.nvim_set_hl
  local old_schedule = vim.schedule
  local output_entry = "unset"
  local token_refreshes = {}
  local search_opened = false
  local dashboard_enter
  local dashboard_options
  local dashboard_cursor_highlight
  local highlighted_selected_row
  vim.o.mouse = "a"
  vim.o.guicursor = "n-v-c:block"
  vim.api.nvim_open_win = function(_, enter)
    dashboard_enter = enter
    return 20
  end
  vim.api.nvim_set_hl = function(_, name, opts)
    if name == "CoduxDashboardCursor" then
      dashboard_cursor_highlight = opts
    end
  end
  vim.api.nvim_create_augroup = function()
    return 91
  end
  vim.api.nvim_create_autocmd = function() end
  vim.schedule = function(callback)
    return callback()
  end

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {},
    is_valid_win = function(win)
      return win == 20
    end,
    is_loaded_buf = function(bufnr)
      return bufnr == 31
    end,
    get_window_config = function()
      return { col = 0, row = 0, width = 80, height = 8 }
    end,
    get_window_height = function()
      return 8
    end,
    get_window_width = function()
      return 80
    end,
    ui = {
      create_scratch_buffer = function()
        return 31
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function(_, opts)
        dashboard_options = opts
      end,
    },
    set_buffer_keymap = function() end,
    set_window_cursor = function()
      error("dashboard cursor should not follow selection")
    end,
    refresh_token_usage = function(force)
      table.insert(token_refreshes, force)
      return true
    end,
  })
  function controller:mission_count()
    return 1
  end
  function controller:dashboard_lines()
    return {
      "1 mission | 1 role | active 1 | question 0 | idle 0",
      "",
      "Alpha",
      "role",
      "Builder",
    }, {
      [3] = {
        kind = "mission",
        mission = {
          name = "Alpha",
          roles = {
            { safe_name = "alpha-builder", mission_role = "Builder", status = "active" },
          },
        },
      },
      [5] = {
        kind = "role",
        entry = { safe_name = "alpha-builder", mission_role = "Builder", status = "active" },
      },
    }, { 3, 5 }, nil
  end
  function controller:highlight_dashboard()
    highlighted_selected_row = controller.state.mission_dashboard_selected_row
  end
  function controller:bind_dashboard_commands() end
  function controller:open_command_bar()
    return true
  end
  function controller:open_output_panel(entry)
    output_entry = entry
    return true
  end
  function controller:open_command_sink()
    return true
  end
  function controller:start_monitor_timer()
    return true
  end
  function controller:open_search_input()
    search_opened = true
    return true
  end

  assert_true(controller:open_dashboard("/repo"))
  assert_equal(controller.state.mission_dashboard_selected_row, 3)
  assert_equal(highlighted_selected_row, 3)
  assert_false(dashboard_enter)
  assert_nil(output_entry)
  assert_false(dashboard_options.cursorline)
  assert_contains(dashboard_options.winhighlight, "Cursor:CoduxDashboardCursor")
  assert_contains(dashboard_options.winhighlight, "CursorIM:CoduxDashboardCursor")
  assert_equal(dashboard_cursor_highlight.fg, "NONE")
  assert_equal(dashboard_cursor_highlight.bg, "NONE")
  assert_equal(dashboard_cursor_highlight.blend, 100)
  assert_equal(controller.state.mission_dashboard_saved_guicursor, "n-v-c:block")
  assert_equal(vim.o.guicursor, "a:CoduxDashboardCursor")
  assert_equal(#token_refreshes, 1)
  assert_true(token_refreshes[1])
  assert_true(search_opened)
  controller:close_dashboard()
  assert_equal(vim.o.mouse, "a")
  assert_equal(vim.o.guicursor, "n-v-c:block")
  assert_nil(controller.state.mission_dashboard_saved_guicursor)

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
  vim.api.nvim_set_hl = old_set_hl
  vim.schedule = old_schedule
  vim.o.mouse = old_mouse
  vim.o.guicursor = old_guicursor
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

do
  local old_guicursor = vim.o.guicursor
  vim.o.guicursor = "n-v-c:block"
  local controller = mission_control_mod.new({ state = {} })

  assert_true(controller:lock_dashboard_cursor())
  assert_equal(vim.o.guicursor, "a:CoduxDashboardCursor")
  assert_equal(controller.state.mission_dashboard_saved_guicursor, "n-v-c:block")

  vim.o.guicursor = "i:ver25"
  assert_true(controller:lock_dashboard_cursor())
  assert_equal(vim.o.guicursor, "a:CoduxDashboardCursor")
  assert_equal(controller.state.mission_dashboard_saved_guicursor, "n-v-c:block")

  assert_true(controller:restore_dashboard_cursor())
  assert_equal(vim.o.guicursor, "n-v-c:block")
  assert_nil(controller.state.mission_dashboard_saved_guicursor)
  vim.o.guicursor = old_guicursor
end

if type(vim.api) == "table" then
  local old_mouse = vim.o.mouse
  local old_guicursor = vim.o.guicursor
  local old_open_win = vim.api.nvim_open_win
  local deleted_buf
  vim.o.mouse = "a"
  vim.o.guicursor = "n-v-c:block"
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
  assert_equal(vim.o.guicursor, "n-v-c:block")
  assert_nil(controller.state.mission_dashboard_saved_mouse)
  assert_nil(controller.state.mission_dashboard_saved_guicursor)
  assert_equal(deleted_buf, 33)

  vim.api.nvim_open_win = old_open_win
  vim.o.mouse = old_mouse
  vim.o.guicursor = old_guicursor
end

if type(vim.api) == "table" then
  local old_mouse = vim.o.mouse
  local old_guicursor = vim.o.guicursor
  local controller = mission_control_mod.new({ state = {} })
  vim.o.mouse = "a"
  vim.o.guicursor = "n-v-c:block"

  assert_true(controller:lock_dashboard_mouse())
  assert_true(controller:lock_dashboard_cursor())
  assert_equal(vim.o.mouse, "")
  assert_equal(vim.o.guicursor, "a:CoduxDashboardCursor")
  assert_true(controller:enable_output_control_mouse())
  assert_true(controller:enable_output_control_cursor())
  assert_equal(vim.o.mouse, "a")
  assert_equal(vim.o.guicursor, "n-v-c:block")
  assert_true(controller.state.mission_dashboard_output_control_cursor)
  assert_true(controller:close_dashboard())
  assert_equal(vim.o.mouse, "a")
  assert_equal(vim.o.guicursor, "n-v-c:block")
  assert_nil(controller.state.mission_dashboard_saved_mouse)
  assert_nil(controller.state.mission_dashboard_saved_guicursor)
  assert_nil(controller.state.mission_dashboard_output_control_mouse)
  assert_nil(controller.state.mission_dashboard_output_control_cursor)
  vim.o.mouse = old_mouse
  vim.o.guicursor = old_guicursor
end

if type(vim.api) == "table" then
  local stopped_job
  local closed_preview
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = 14,
      mission_dashboard_output_win = 13,
      mission_dashboard_output_entry = { safe_name = "alpha-builder" },
      mission_dashboard_output_key = "key",
      mission_dashboard_output_blocked_key = "blocked",
      mission_dashboard_output_job = 77,
      mission_dashboard_output_preview = { preview_session = "codux-preview-test" },
      mission_dashboard_output_buf_kind = "terminal",
      mission_dashboard_output_control = true,
      mission_dashboard_output_control_key = "control",
    },
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
    },
    jobstop = function(job_id)
      stopped_job = job_id
      return true
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
  })

  assert_true(controller:close_dashboard())
  assert_equal(stopped_job, 77)
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_buf)
  assert_nil(controller.state.mission_dashboard_output_win)
  assert_nil(controller.state.mission_dashboard_output_entry)
  assert_nil(controller.state.mission_dashboard_output_key)
  assert_nil(controller.state.mission_dashboard_output_blocked_key)
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
  assert_nil(controller.state.mission_dashboard_output_buf_kind)
  assert_false(controller.state.mission_dashboard_output_control)
  assert_nil(controller.state.mission_dashboard_output_control_key)
end



print("mission_control_dashboard_windows_spec.lua: ok")
