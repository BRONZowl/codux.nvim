local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_nil = h.assert_nil
local assert_true = h.assert_true

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
  local rendered_lines
  local window_config
  local window_options
  local keymaps = {}
  local close_key
  local deleted_buf
  local closed_win
  local selected_choice

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
      assert_equal(options.filetype, "codux-open-profile")
      return 42
    end,
    set_lines = function(bufnr, lines)
      assert_equal(bufnr, 42)
      rendered_lines = lines
      return true
    end,
    open_win = function(bufnr, enter, config)
      assert_equal(bufnr, 42)
      assert_true(enter)
      window_config = config
      return 84
    end,
    set_window_options = function(win, options)
      assert_equal(win, 84)
      window_options = options
    end,
    bind_close_keys = function(bufnr, close_fn, desc, modes, opts)
      assert_equal(bufnr, 42)
      assert_equal(desc, "Cancel Codux Open")
      assert_equal(modes, "n")
      assert_true(opts.escape)
      assert_true(opts.q)
      close_key = close_fn
    end,
    set_buffer_keymap = function(bufnr, mode, lhs, rhs, desc, opts)
      assert_equal(bufnr, 42)
      assert_equal(mode, "n")
      keymaps[lhs] = { rhs = rhs, desc = desc, opts = opts }
    end,
    close_window = function(win)
      closed_win = win
    end,
    delete_buffer = function(bufnr)
      deleted_buf = bufnr
    end,
  }))

  assert_equal(rendered_lines[1], "d - default")
  assert_equal(rendered_lines[2], "a - auto")
  assert_equal(rendered_lines[3], "f - full")
  assert_equal(window_config.title, " Codex permission profile ")
  assert_equal(window_config.height, 3)
  assert_equal(window_options.winhighlight, "FloatBorder:WhichKey,FloatTitle:WhichKey")
  assert_equal(keymaps.d.desc, "Open Codex Default")
  assert_true(keymaps.d.opts.nowait)
  assert_equal(keymaps.a.desc, "Open Codex Auto")
  assert_equal(keymaps.f.desc, "Open Codex Full Access")
  assert_true(keymaps.a.rhs())
  assert_equal(selected_choice.profile, "auto")
  assert_equal(closed_win, 84)
  assert_equal(deleted_buf, 42)
  assert_false(close_key())
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
      return 43
    end,
    set_lines = function()
      return true
    end,
    open_win = function()
      return 85
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

print("ui_spec.lua: ok")
