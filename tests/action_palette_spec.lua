local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_true = h.assert_true

local action_palette_mod = require("codux.action_palette")

do
  local old_api = vim.api
  local highlights = {}
  vim.api = {
    nvim_buf_clear_namespace = function(bufnr, namespace, start_line, end_line)
      table.insert(highlights, {
        group = "clear",
        bufnr = bufnr,
        namespace = namespace,
        start_line = start_line,
        end_line = end_line,
      })
    end,
    nvim_buf_add_highlight = function(bufnr, namespace, group, row, start_col, end_col)
      table.insert(highlights, {
        bufnr = bufnr,
        namespace = namespace,
        group = group,
        row = row,
        start_col = start_col,
        end_col = end_col,
      })
    end,
  }

  action_palette_mod.highlight_action_lines(12, 99, {
    { key = "r", label = "Rename" },
  })

  assert_equal(highlights[1].group, "clear")
  assert_equal(highlights[2].group, "WhichKey")
  assert_equal(highlights[2].start_col, 0)
  assert_equal(highlights[2].end_col, 1)
  assert_equal(highlights[3].group, "Normal")
  assert_equal(highlights[3].start_col, 1)
  assert_equal(highlights[3].end_col, 3)
  assert_equal(highlights[4].group, "Normal")
  assert_equal(highlights[4].start_col, 3)
  assert_equal(highlights[4].end_col, -1)
  vim.api = old_api
end

do
  local old_api = vim.api
  local opened_config
  local cursor_set
  vim.api = {
    nvim_open_win = function(bufnr, enter, config)
      assert_equal(bufnr, 31)
      assert_true(enter)
      opened_config = config
      return 41
    end,
    nvim_win_set_cursor = function(win, cursor)
      assert_equal(win, 41)
      cursor_set = cursor
      return true
    end,
    nvim_buf_clear_namespace = function() end,
    nvim_buf_add_highlight = function() end,
  }

  local state = {}
  local rendered_lines
  local window_options
  local deleted_buf
  local closed_win
  local close_desc
  local close_opts
  local bound = {}
  local cursor = { 1, 0 }
  local ran_action
  local controller = action_palette_mod.new({
    state = state,
    win_key = "action_win",
    buf_key = "action_buf",
    items_key = "action_items",
    target_key = "action_target",
    namespace = 55,
    ui = {
      create_scratch_buffer = function(options)
        assert_equal(options.filetype, "codux-test-actions")
        return 31
      end,
      set_lines = function(bufnr, lines)
        assert_equal(bufnr, 31)
        rendered_lines = lines
        return true
      end,
      set_window_options = function(win, options)
        assert_equal(win, 41)
        window_options = options
      end,
      close_window = function(win)
        closed_win = win
      end,
      delete_buffer = function(bufnr)
        deleted_buf = bufnr
      end,
    },
    is_valid_win = function(win)
      return win == 41
    end,
    is_loaded_buf = function(bufnr)
      return bufnr == 31
    end,
    get_window_cursor = function()
      return cursor
    end,
    set_window_cursor = function(_, next_cursor)
      cursor_set = next_cursor
      cursor = next_cursor
      return true
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
    create_buffer_options = {
      bufhidden = "wipe",
      filetype = "codux-test-actions",
      buftype = "nofile",
      swapfile = false,
      modifiable = false,
    },
    items = function()
      return {
        { key = "r", action = "rename", label = "Rename Workspace" },
        { key = "d", action = "delete", label = "Delete Workspace" },
      }
    end,
    line_for = function(item)
      return item.key .. "  " .. item.label
    end,
    width = function()
      return 40
    end,
    window_config = function(_, item_count)
      assert_equal(item_count, 2)
      return { height = item_count }
    end,
    action_label = "Workspace",
    run_action = function(action, target)
      ran_action = tostring(action) .. ":" .. tostring(target.name)
      return true
    end,
  })

  assert_true(controller:open({ name = "review" }))
  assert_equal(state.action_win, 41)
  assert_equal(state.action_buf, 31)
  assert_equal(state.action_target.name, "review")
  assert_equal(rendered_lines[1], "r  Rename Workspace")
  assert_equal(opened_config.height, 2)
  assert_equal(window_options.winhighlight, "FloatBorder:WhichKey,FloatTitle:WhichKey")
  assert_equal(close_desc, "Close Codux Workspace Actions")
  assert_true(close_opts.escape)
  assert_true(close_opts.q)
  assert_equal(bound["<CR>"].desc, "Run Codux Workspace Action")
  assert_equal(bound.j.desc, "Next Codux Workspace Action")
  assert_true(bound.j.opts.nowait)
  assert_equal(bound.k.desc, "Previous Codux Workspace Action")
  assert_equal(bound.r.desc, "Rename Workspace Codux Workspace")
  assert_equal(cursor_set[1], 1)

  assert_true(controller:move_cursor(1))
  assert_equal(cursor[1], 2)
  assert_true(bound["<CR>"].rhs())
  assert_equal(ran_action, "delete:review")
  assert_true(bound.r.rhs())
  assert_equal(ran_action, "rename:review")
  assert_true(bound.close())
  assert_equal(closed_win, 41)
  assert_equal(deleted_buf, 31)
  assert_equal(state.action_win, nil)
  assert_equal(state.action_buf, nil)
  assert_equal(#state.action_items, 0)
  assert_equal(state.action_target, nil)

  assert_false(controller:run_highlighted())
  vim.api = old_api
end

do
  local old_api = vim.api
  local opened = {}
  local cursor_set
  local cursor_highlight
  vim.api = {
    nvim_open_win = function(bufnr, enter, config)
      table.insert(opened, {
        bufnr = bufnr,
        enter = enter,
        config = config,
      })
      return bufnr + 100
    end,
    nvim_win_set_cursor = function(_, cursor)
      cursor_set = cursor
      return true
    end,
    nvim_set_hl = function(_, name, opts)
      if name == "CoduxActionPaletteCursor" then
        cursor_highlight = opts
      end
    end,
    nvim_buf_clear_namespace = function() end,
    nvim_buf_add_highlight = function() end,
  }

  local state = {}
  local window_options = {}
  local closed = {}
  local deleted = {}
  local bound = {}
  local create_count = 0
  local ran_action
  local controller = action_palette_mod.new({
    state = state,
    win_key = "action_win",
    buf_key = "action_buf",
    sink_win_key = "action_sink_win",
    sink_buf_key = "action_sink_buf",
    items_key = "action_items",
    target_key = "action_target",
    namespace = 56,
    key_only = true,
    ui = {
      create_scratch_buffer = function(options)
        create_count = create_count + 1
        if create_count == 1 then
          assert_equal(options.filetype, "codux-test-actions")
          return 31
        end
        assert_equal(options.filetype, "codux-actions-sink")
        return 32
      end,
      set_lines = function() end,
      set_window_options = function(win, options)
        window_options[win] = options
      end,
      close_window = function(win)
        table.insert(closed, win)
      end,
      delete_buffer = function(bufnr)
        table.insert(deleted, bufnr)
      end,
    },
    is_valid_win = function(win)
      return win == 131
    end,
    is_loaded_buf = function(bufnr)
      return bufnr == 31
    end,
    set_window_cursor = function(_, cursor)
      cursor_set = cursor
      return true
    end,
    set_buffer_keymap = function(bufnr, mode, lhs, rhs, desc, opts)
      assert_equal(bufnr, 32)
      assert_equal(mode, "n")
      bound[lhs] = { rhs = rhs, desc = desc, opts = opts }
    end,
    bind_close_keys = function(bufnr, close_fn, _, _, opts)
      assert_equal(bufnr, 32)
      bound.close = close_fn
      assert_true(opts.escape)
      assert_true(opts.q)
    end,
    create_buffer_options = {
      bufhidden = "wipe",
      filetype = "codux-test-actions",
      buftype = "nofile",
      swapfile = false,
      modifiable = false,
    },
    items = function()
      return {
        { key = "r", action = "rename", label = "Rename Workspace" },
      }
    end,
    line_for = function(item)
      return item.key .. "  " .. item.label
    end,
    window_config = function()
      return { height = 1 }
    end,
    action_label = "Workspace",
    run_action = function(action, target)
      ran_action = tostring(action) .. ":" .. tostring(target.name)
      return true
    end,
  })

  assert_true(controller:open({ name = "review" }))
  assert_equal(opened[1].bufnr, 31)
  assert_false(opened[1].enter)
  assert_false(opened[1].config.focusable)
  assert_equal(opened[2].bufnr, 32)
  assert_true(opened[2].enter)
  assert_equal(window_options[131].cursorline, false)
  assert_equal(window_options[131].winhighlight, "FloatBorder:WhichKey,FloatTitle:WhichKey,Cursor:CoduxActionPaletteCursor,CursorIM:CoduxActionPaletteCursor")
  assert_equal(cursor_highlight.blend, 100)
  assert_equal(cursor_set, nil)
  assert_equal(bound["<CR>"], nil)
  assert_equal(bound.j, nil)
  assert_equal(bound.k, nil)
  assert_equal(bound["<Down>"], nil)
  assert_equal(bound["<Up>"], nil)
  assert_equal(bound.r.desc, "Rename Workspace Codux Workspace")
  assert_false(controller:move_cursor(1))
  assert_false(controller:run_highlighted())
  assert_true(bound.r.rhs())
  assert_equal(ran_action, "rename:review")
  assert_true(bound.close())
  assert_equal(closed[1], 131)
  assert_equal(closed[2], 132)
  assert_equal(deleted[1], 31)
  assert_equal(deleted[2], 32)
  assert_equal(state.action_win, nil)
  assert_equal(state.action_buf, nil)
  assert_equal(state.action_sink_win, nil)
  assert_equal(state.action_sink_buf, nil)
  vim.api = old_api
end

print("action_palette_spec.lua: ok")
