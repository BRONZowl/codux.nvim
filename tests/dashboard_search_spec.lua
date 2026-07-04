local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_nil = h.assert_nil
local assert_true = h.assert_true

local dashboard_search_mod = require("codux.dashboard_search")

do
  local state = {
    search_buf = 31,
    search_win = 41,
    query = "ab",
    selected = 2,
    focus_match = false,
    confirmed = true,
  }
  local lines_set
  local cursor_set
  local render_count = 0
  local controller = dashboard_search_mod.new({
    state = state,
    ui = {
      set_lines = function(bufnr, lines, opts)
        assert_equal(bufnr, 31)
        assert_true(opts.modifiable)
        lines_set = lines
        return true
      end,
    },
    is_loaded_buf = function(bufnr)
      return bufnr == 31
    end,
    is_valid_win = function(win)
      return win == 41
    end,
    set_window_cursor = function(win, cursor)
      assert_equal(win, 41)
      cursor_set = cursor
      return true
    end,
    cursor_width = function()
      return 8
    end,
    render_owner = function()
      render_count = render_count + 1
      return true
    end,
    win_key = "search_win",
    buf_key = "search_buf",
    query_key = "query",
    selected_key = "selected",
    best_match_key = "best_match",
    focus_match_key = "focus_match",
    confirmed_key = "confirmed",
  })

  assert_true(controller:render())
  assert_equal(lines_set[1], "ab ")
  assert_equal(cursor_set[1], 1)
  assert_equal(cursor_set[2], 2)

  assert_true(controller:append_query("c"))
  assert_equal(state.query, "abc")
  assert_nil(state.selected)
  assert_true(state.focus_match)
  assert_false(state.confirmed)
  assert_equal(render_count, 1)
  assert_equal(lines_set[1], "abc ")

  assert_true(controller:delete_query_char())
  assert_equal(state.query, "ab")
  assert_true(controller:clear_query())
  assert_equal(state.query, "")
  assert_equal(render_count, 3)
  assert_true(controller:clear_query())
  assert_equal(render_count, 3)
end

do
  local old_api = vim.api
  local autocmd_callback
  vim.api = {
    nvim_create_augroup = function(name, opts)
      assert_equal(name, "codux-test-search-32")
      assert_true(opts.clear)
      return 91
    end,
    nvim_create_autocmd = function(events, opts)
      assert_equal(events[1], "BufWipeout")
      assert_equal(events[2], "BufDelete")
      assert_equal(opts.group, 91)
      assert_equal(opts.buffer, 32)
      autocmd_callback = opts.callback
    end,
    nvim_del_augroup_by_id = function(group)
      assert_equal(group, 91)
      return true
    end,
  }

  local state = {
    main_win = 10,
    best_match = 4,
  }
  local opened_enter
  local opened_config
  local window_options
  local deleted_buf
  local bound = {}
  local close_desc
  local close_opts
  local focused_win
  local focused_list = 0
  local closed = 0
  local render_count = 0
  local updated_config
  local after_create_bufnr
  local notifications = {}
  local controller = dashboard_search_mod.new({
    state = state,
    ui = {
      create_scratch_buffer = function(options)
        assert_equal(options.filetype, "codux-test-search")
        return 32
      end,
      printable_prompt_keys = function()
        return {
          { "a", "a" },
        }
      end,
      set_lines = function()
        return true
      end,
      set_window_options = function(win, options)
        assert_equal(win, 20)
        window_options = options
      end,
      delete_buffer = function(bufnr)
        deleted_buf = bufnr
      end,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20
    end,
    is_loaded_buf = function(bufnr)
      return bufnr == 32
    end,
    set_current_win = function(win)
      focused_win = win
      return true
    end,
    get_current_win = function()
      return focused_win
    end,
    set_window_cursor = function()
      return true
    end,
    set_window_config = function(win, config)
      assert_equal(win, 20)
      updated_config = config
      return true
    end,
    open_win = function(bufnr, enter, config)
      assert_equal(bufnr, 32)
      opened_enter = enter
      opened_config = config
      return 20
    end,
    set_buffer_keymap = function(_, mode, lhs, rhs, desc, opts)
      assert_equal(mode, "n")
      bound[lhs] = { rhs = rhs, desc = desc, opts = opts }
    end,
    bind_close_keys = function(_, close_fn, desc, modes, opts)
      assert_equal(modes, "n")
      bound.close = close_fn
      close_desc = desc
      close_opts = opts
    end,
    notify = function(message)
      table.insert(notifications, message)
    end,
    main_win = function()
      return state.main_win
    end,
    window_config = function()
      return { title = " Search " }
    end,
    render_owner = function()
      render_count = render_count + 1
      return true
    end,
    focus_list = function()
      focused_list = focused_list + 1
      return true
    end,
    close_owner = function()
      closed = closed + 1
      return true
    end,
    after_create_buffer = function(bufnr)
      after_create_bufnr = bufnr
    end,
    create_buffer_options = {
      filetype = "codux-test-search",
    },
    win_key = "search_win",
    buf_key = "search_buf",
    query_key = "query",
    selected_key = "selected",
    best_match_key = "best_match",
    focus_match_key = "focus_match",
    confirmed_key = "confirmed",
    close_desc = "Close Codux Test",
    focus_list_desc = "Focus Codux Test List",
    select_desc = "Select Codux Test",
    select_error = "No Codux test selected",
    delete_desc = "Delete Codux Test Search Character",
    clear_desc = "Clear Codux Test Search",
    search_desc = "Search Codux Tests",
    augroup_prefix = "codux-test-search-",
  })

  assert_true(controller:open({ focus = false }))
  assert_false(opened_enter)
  assert_equal(opened_config.title, " Search ")
  assert_equal(after_create_bufnr, 32)
  assert_equal(state.search_buf, 32)
  assert_equal(state.search_win, 20)
  assert_equal(window_options.winhighlight, "FloatBorder:WhichKey,FloatTitle:WhichKey")
  assert_equal(close_desc, "Close Codux Test")
  assert_true(close_opts.escape)
  assert_equal(bound["<Tab>"].desc, "Focus Codux Test List")
  assert_equal(bound["<CR>"].desc, "Select Codux Test")
  assert_equal(bound["<BS>"].desc, "Delete Codux Test Search Character")
  assert_true(bound["<BS>"].opts.nowait)
  assert_equal(bound["<C-u>"].desc, "Clear Codux Test Search")
  assert_equal(bound.a.desc, "Search Codux Tests")

  assert_true(bound.a.rhs())
  assert_equal(state.query, "a")
  assert_true(bound["<CR>"].rhs())
  assert_equal(state.selected, 4)
  assert_true(state.confirmed)
  assert_false(state.focus_match)
  assert_equal(focused_win, 10)
  assert_equal(render_count, 2)
  assert_true(bound["<Tab>"].rhs())
  assert_equal(focused_list, 1)
  assert_true(bound.close())
  assert_equal(closed, 1)

  focused_win = nil
  assert_true(controller:open({ focus = false }))
  assert_nil(focused_win)
  assert_equal(updated_config.title, " Search ")
  assert_true(controller:open())
  assert_equal(focused_win, 20)

  autocmd_callback()
  assert_nil(state.search_buf)
  assert_nil(state.search_win)

  state.best_match = nil
  assert_false(controller:select_best_match())
  assert_equal(notifications[#notifications], "No Codux test selected")

  local failing = dashboard_search_mod.new({
    state = { main_win = 10 },
    ui = {
      create_scratch_buffer = function()
        return 33
      end,
      delete_buffer = function(bufnr)
        deleted_buf = bufnr
      end,
    },
    is_valid_win = function(win)
      return win == 10
    end,
    open_win = function()
      error("open failed")
    end,
    notify = function(message)
      table.insert(notifications, message)
    end,
    main_win = function()
      return 10
    end,
    win_key = "search_win",
    buf_key = "search_buf",
    query_key = "query",
    selected_key = "selected",
    best_match_key = "best_match",
    focus_match_key = "focus_match",
    confirmed_key = "confirmed",
    open_error = "Failed to open Codux test search",
  })

  assert_false(failing:open())
  assert_equal(deleted_buf, 33)
  assert_equal(notifications[#notifications], "Failed to open Codux test search")

  vim.api = old_api
end

print("dashboard_search_spec.lua: ok")
