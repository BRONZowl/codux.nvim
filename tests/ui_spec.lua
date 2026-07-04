local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_contains = h.assert_contains

local ui = require("codux.ui")

do
  local checked_bufnr
  local ok = ui.disable_buffer_completion(99, {
    is_loaded_buf = function(bufnr)
      checked_bufnr = bufnr
      return false
    end,
  })

  assert_false(ok)
  assert_equal(checked_bufnr, 99)
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("completefunc", "v:lua.SomeComplete", { buf = bufnr })
  vim.api.nvim_set_option_value("omnifunc", "v:lua.SomeOmni", { buf = bufnr })

  assert_true(ui.disable_buffer_completion(bufnr))
  assert_equal(vim.api.nvim_get_option_value("completefunc", { buf = bufnr }), "")
  assert_equal(vim.api.nvim_get_option_value("omnifunc", { buf = bufnr }), "")
  assert_equal(vim.b[bufnr].codux_disable_completion, true)
  assert_equal(vim.b[bufnr].blink_cmp_enabled, false)
  assert_equal(vim.b[bufnr].cmp_enabled, false)
  assert_equal(vim.b[bufnr].copilot_enabled, false)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

do
  local created_options
  local opened_config
  local opened_enter
  local window_options
  local bound_bufnr
  local bufnr, win, err = ui.open_hidden_command_sink({
    ui = {
      create_scratch_buffer = function(options)
        created_options = options
        return 51
      end,
      delete_buffer = function() end,
      set_window_options = function(target_win, options)
        assert_equal(target_win, 71)
        window_options = options
      end,
    },
    filetype = "codux-test-sink",
    enter = true,
    focusable = true,
    open_win = function(target_bufnr, enter, config)
      assert_equal(target_bufnr, 51)
      opened_enter = enter
      opened_config = config
      return 71
    end,
    bind = function(target_bufnr)
      bound_bufnr = target_bufnr
    end,
  })

  assert_equal(bufnr, 51)
  assert_equal(win, 71)
  assert_nil(err)
  assert_equal(created_options.filetype, "codux-test-sink")
  assert_true(opened_enter)
  assert_true(opened_config.focusable)
  assert_equal(opened_config.width, 1)
  assert_equal(opened_config.height, 1)
  assert_equal(window_options.signcolumn, "no")
  assert_equal(bound_bufnr, 51)
end

do
  local deleted_bufnr
  local bufnr, win, err = ui.open_hidden_command_sink({
    ui = {
      create_scratch_buffer = function()
        return 52
      end,
      delete_buffer = function(target_bufnr)
        deleted_bufnr = target_bufnr
      end,
      set_window_options = function()
        error("window options should not be set after open failure")
      end,
    },
    filetype = "codux-test-sink",
    open_win = function()
      error("open failed")
    end,
  })

  assert_nil(bufnr)
  assert_nil(win)
  assert_equal(err, "open")
  assert_equal(deleted_bufnr, 52)
end

do
  local lines = ui.key_choice_lines({
    { key = "d", label = "default" },
    { key = "a", label = "auto" },
    { key = "f", label = "full" },
  })

  assert_equal(lines[1], "d - default")
  assert_equal(lines[2], "a - auto")
  assert_equal(lines[3], "f - full")
end

do
  local old_api = vim.api
  local rendered_lines
  local window_config
  local sink_config
  local window_options
  local sink_options
  local keymaps = {}
  local close_key
  local deleted_bufs = {}
  local closed_wins = {}
  local selected_choice
  local cursor_highlight
  local create_count = 0

  if type(vim.api) == "table" then
    vim.api = {}
    for key, value in pairs(old_api) do
      vim.api[key] = value
    end
  else
    vim.api = {}
  end
  vim.api.nvim_set_hl = function(_, name, opts)
    if name == "CoduxKeyChoiceCursor" then
      cursor_highlight = opts
    end
  end

  assert_true(ui.key_choice_menu({
    title = " Codex permission profile ",
    choices = {
      { key = "d", label = "default", profile = "default", desc = "Open Codex Default" },
      { key = "a", label = "auto", profile = "auto", desc = "Open Codex Auto" },
      { key = "f", label = "full", profile = "danger", desc = "Open Codex Full Access" },
    },
    filetype = "codux-open-profile",
    cancel_desc = "Cancel Codux Open",
  }, function(choice)
    selected_choice = choice
  end, {
    create_scratch_buffer = function(options)
      create_count = create_count + 1
      if create_count == 1 then
        assert_equal(options.filetype, "codux-open-profile")
        return 42
      end
      assert_equal(options.filetype, "codux-open-profile-sink")
      return 43
    end,
    set_lines = function(bufnr, lines)
      assert_equal(bufnr, 42)
      rendered_lines = lines
      return true
    end,
    open_win = function(bufnr, enter, config)
      if bufnr == 42 then
        assert_false(enter)
        window_config = config
        return 84
      end
      assert_equal(bufnr, 43)
      assert_true(enter)
      sink_config = config
      return 85
    end,
    set_window_options = function(win, options)
      if win == 84 then
        window_options = options
      elseif win == 85 then
        sink_options = options
      else
        error("unexpected window " .. tostring(win))
      end
    end,
    bind_close_keys = function(bufnr, close_fn, desc, modes, opts)
      assert_equal(bufnr, 43)
      assert_equal(desc, "Cancel Codux Open")
      assert_equal(modes, "n")
      assert_true(opts.escape)
      assert_true(opts.q)
      close_key = close_fn
    end,
    set_buffer_keymap = function(bufnr, mode, lhs, rhs, desc, opts)
      assert_equal(bufnr, 43)
      assert_equal(mode, "n")
      keymaps[lhs] = { rhs = rhs, desc = desc, opts = opts }
    end,
    close_window = function(win)
      table.insert(closed_wins, win)
    end,
    delete_buffer = function(bufnr)
      table.insert(deleted_bufs, bufnr)
    end,
  }))

  assert_equal(rendered_lines[1], "d - default")
  assert_equal(rendered_lines[2], "a - auto")
  assert_equal(rendered_lines[3], "f - full")
  assert_equal(window_config.title, " Codex permission profile ")
  assert_equal(window_config.height, 3)
  assert_false(window_config.focusable)
  assert_equal(sink_config.width, 1)
  assert_equal(sink_config.height, 1)
  assert_equal(sink_config.focusable, true)
  assert_equal(sink_options.signcolumn, "no")
  assert_contains(window_options.winhighlight, "FloatBorder:WhichKey")
  assert_contains(window_options.winhighlight, "FloatTitle:WhichKey")
  assert_contains(window_options.winhighlight, "Cursor:CoduxKeyChoiceCursor")
  assert_contains(window_options.winhighlight, "CursorIM:CoduxKeyChoiceCursor")
  assert_equal(cursor_highlight.fg, "NONE")
  assert_equal(cursor_highlight.bg, "NONE")
  assert_equal(cursor_highlight.blend, 100)
  assert_equal(keymaps.d.desc, "Open Codex Default")
  assert_true(keymaps.d.opts.nowait)
  assert_equal(keymaps.a.desc, "Open Codex Auto")
  assert_equal(keymaps.f.desc, "Open Codex Full Access")
  assert_true(keymaps.a.rhs())
  assert_equal(selected_choice.profile, "auto")
  assert_equal(closed_wins[1], 84)
  assert_equal(closed_wins[2], 85)
  assert_equal(deleted_bufs[1], 42)
  assert_equal(deleted_bufs[2], 43)
  assert_false(close_key())
  vim.api = old_api
end

do
  local selected_choice = "not called"
  local close_key

  assert_true(ui.key_choice_menu({
    title = " Codex permission profile ",
    choices = {
      { key = "d", label = "default", profile = "default" },
    },
  }, function(choice)
    selected_choice = choice
  end, {
    create_scratch_buffer = function()
      return 44
    end,
    set_lines = function()
      return true
    end,
    open_win = function(bufnr)
      return bufnr + 100
    end,
    set_window_options = function() end,
    bind_close_keys = function(_, close_fn)
      close_key = close_fn
    end,
    set_buffer_keymap = function() end,
    close_window = function() end,
    delete_buffer = function() end,
  }))

  assert_true(close_key())
  assert_nil(selected_choice)
end

do
  local old_api = vim.api
  local old_create_scratch_buffer = ui.create_scratch_buffer
  local old_set_lines = ui.set_lines
  local old_buffer_lines = ui.buffer_lines
  local old_is_loaded_buf = ui.is_loaded_buf
  local old_is_valid_win = ui.is_valid_win
  local old_set_window_options = ui.set_window_options
  local old_close_window = ui.close_window
  local old_delete_buffer = ui.delete_buffer
  local old_g = vim.g
  local keymaps = {}
  local created_options
  local rendered
  local direct_line
  local submitted
  local started_command

  vim.g = vim.g or {}
  local old_mapleader = vim.g.mapleader
  vim.g.mapleader = " "
  vim.api = vim.api or {}
  local old_open_win = vim.api.nvim_open_win
  local old_win_set_cursor = vim.api.nvim_win_set_cursor
  local old_cmd = vim.cmd
  vim.api.nvim_open_win = function()
    return 202
  end
  vim.api.nvim_win_set_cursor = function() end
  vim.cmd = function(command)
    started_command = command
  end

  ui.create_scratch_buffer = function(options)
    created_options = options
    return 101
  end
  ui.set_lines = function(_, lines)
    rendered = lines[1]
    return true
  end
  ui.buffer_lines = function()
    if direct_line ~= nil then
      return { direct_line }
    end
    return nil
  end
  ui.is_loaded_buf = function(bufnr)
    return bufnr == 101
  end
  ui.is_valid_win = function(win)
    return win == 202
  end
  ui.set_window_options = function() end
  ui.close_window = function() end
  ui.delete_buffer = function() end

  assert_true(ui.single_line_prompt({
    prompt = "Plan option Builder: ",
    allowed_chars = "1234",
    max_length = 1,
  }, function(value)
    submitted = value
  end, {
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, _, lhs, rhs, _, opts)
      keymaps[lhs] = { rhs = rhs, opts = opts }
    end,
  }))

  assert_true(created_options.modifiable)
  assert_equal(rendered, " ")
  assert_true(keymaps["<Leader>"].opts.nowait)
  assert_true(keymaps.a.rhs())
  assert_equal(rendered, " ")
  assert_true(keymaps["<Leader>"].rhs())
  assert_equal(rendered, " ")
  assert_true(keymaps["2"].rhs())
  assert_equal(rendered, "2 ")
  assert_true(keymaps["3"].rhs())
  assert_equal(rendered, "2 ")
  assert_true(keymaps["<CR>"].rhs())
  assert_equal(submitted, "2")

  keymaps = {}
  created_options = nil
  rendered = nil
  direct_line = nil
  submitted = nil
  assert_true(ui.single_line_prompt({
    prompt = "Note Builder: ",
  }, function(value)
    submitted = value
  end, {
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, _, lhs, rhs, _, opts)
      keymaps[lhs] = { rhs = rhs, opts = opts }
    end,
  }))

  assert_true(created_options.modifiable)
  assert_true(keymaps["<Space>"].opts.nowait)
  assert_true(keymaps["<Leader>"].opts.nowait)
  assert_true(keymaps.s.rhs())
  assert_equal(rendered, "s ")
  assert_true(keymaps["<Leader>"].rhs())
  assert_equal(rendered, "s  ")
  assert_true(keymaps["<Space>"].rhs())
  assert_equal(rendered, "s   ")
  assert_true(keymaps.h.rhs())
  assert_equal(rendered, "s  h ")
  assert_true(keymaps["<CR>"].rhs())
  assert_equal(submitted, "s  h")

  keymaps = {}
  direct_line = nil
  submitted = nil
  assert_true(ui.single_line_prompt({
    prompt = "Note Builder: ",
  }, function(value)
    submitted = value
  end, {
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, _, lhs, rhs, _, opts)
      keymaps[lhs] = { rhs = rhs, opts = opts }
    end,
  }))

  direct_line = "raw pasted note "
  assert_true(keymaps["<CR>"].rhs())
  assert_equal(submitted, "raw pasted note")

  keymaps = {}
  direct_line = nil
  submitted = nil
  started_command = nil
  assert_true(ui.single_line_prompt({
    prompt = "Note Builder: ",
    insert_input = true,
  }, function(value)
    submitted = value
  end, {
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, modes, lhs, rhs, _, opts)
      keymaps[lhs] = { modes = modes, rhs = rhs, opts = opts }
    end,
  }))

  assert_true(created_options.modifiable)
  assert_nil(keymaps["<Space>"])
  assert_nil(keymaps["<Leader>"])
  assert_equal(keymaps["<CR>"].modes[1], "n")
  assert_equal(keymaps["<CR>"].modes[2], "i")
  assert_equal(started_command, "startinsert")
  direct_line = "ship this plan with context "
  assert_true(keymaps["<CR>"].rhs())
  assert_equal(submitted, "ship this plan with context")

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_win_set_cursor = old_win_set_cursor
  vim.api = old_api
  vim.cmd = old_cmd
  if old_g == nil then
    vim.g = nil
  else
    vim.g = old_g
    vim.g.mapleader = old_mapleader
  end
  ui.create_scratch_buffer = old_create_scratch_buffer
  ui.set_lines = old_set_lines
  ui.buffer_lines = old_buffer_lines
  ui.is_loaded_buf = old_is_loaded_buf
  ui.is_valid_win = old_is_valid_win
  ui.set_window_options = old_set_window_options
  ui.close_window = old_close_window
  ui.delete_buffer = old_delete_buffer
end

print("ui_spec.lua: ok")
