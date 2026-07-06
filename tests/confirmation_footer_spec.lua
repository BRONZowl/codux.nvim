local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local confirmation_footer = require("codux.confirmation_footer")
local workspace_ui = require("codux.workspace_ui")

local segments = {
  { key = "enter", desc = "create" },
  { key = "e", desc = "edit mission" },
  { key = "<c-q>", desc = "cancel" },
}

do
  local rendered
  local highlights = {}
  local controller = {
    namespace = 91,
    workspace_ui = workspace_ui,
    is_loaded_buf = function(bufnr)
      return bufnr == 12
    end,
    ui = {
      set_lines = function(bufnr, lines)
        assert_equal(bufnr, 12)
        rendered = lines[1]
      end,
    },
  }

  h.with_vim_api({
    nvim_buf_clear_namespace = function(bufnr, namespace)
      assert_equal(bufnr, 12)
      assert_equal(namespace, 91)
    end,
    nvim_buf_add_highlight = function(_, _, group, _, start_col, end_col)
      table.insert(highlights, group .. ":" .. tostring(start_col) .. ":" .. tostring(end_col))
    end,
  }, function()
    assert_true(confirmation_footer.render(controller, 12, {
      width = 50,
      segments = segments,
    }))
  end)

  assert_contains(rendered, "enter create")
  assert_contains(rendered, "e edit mission")
  assert_contains(rendered, "<c-q> cancel")
  assert_equal(highlights[1], "WhichKey:4:9")
  assert_equal(highlights[2], "WhichKeySeparator:9:16")
end

do
  local controller = {
    workspace_ui = workspace_ui,
    is_loaded_buf = function()
      return false
    end,
    ui = {
      set_lines = function()
        error("unloaded footer buffers should not render")
      end,
    },
  }

  assert_false(confirmation_footer.render(controller, 99, {
    width = 20,
    segments = segments,
  }))
end

if type(vim.api) == "table" then
  local opened
  local rendered
  local controller = {
    namespace = 7,
    workspace_ui = workspace_ui,
    is_valid_win = function(win)
      return win == 20
    end,
    is_loaded_buf = function(bufnr)
      return bufnr == 31
    end,
    ui = {
      create_scratch_buffer = function(opts)
        assert_equal(opts.filetype, "codux-test-footer")
        return 31
      end,
      set_lines = function(bufnr, lines)
        assert_equal(bufnr, 31)
        rendered = lines[1]
      end,
      delete_buffer = function()
        error("opened footer should not delete its buffer")
      end,
    },
  }

  h.with_vim_api({
    nvim_win_get_height = function(win)
      assert_equal(win, 20)
      return 6
    end,
    nvim_win_get_width = function(win)
      assert_equal(win, 20)
      return 50
    end,
    nvim_open_win = function(bufnr, enter, config)
      opened = {
        bufnr = bufnr,
        enter = enter,
        config = config,
      }
      return 41
    end,
    nvim_buf_clear_namespace = function() end,
    nvim_buf_add_highlight = function() end,
  }, function()
    local bufnr, win = confirmation_footer.open(controller, 20, {
      filetype = "codux-test-footer",
      zindex = 55,
      segments = segments,
    })

    assert_equal(bufnr, 31)
    assert_equal(win, 41)
  end)

  assert_equal(opened.bufnr, 31)
  assert_false(opened.enter)
  assert_equal(opened.config.relative, "win")
  assert_equal(opened.config.win, 20)
  assert_equal(opened.config.row, 5)
  assert_equal(opened.config.width, 50)
  assert_equal(opened.config.zindex, 55)
  assert_contains(rendered, "e edit mission")
end

if type(vim.api) == "table" then
  local deleted
  local controller = {
    workspace_ui = workspace_ui,
    is_valid_win = function()
      return true
    end,
    ui = {
      create_scratch_buffer = function()
        return 44
      end,
      delete_buffer = function(bufnr)
        deleted = bufnr
      end,
    },
  }

  h.with_vim_api({
    nvim_win_get_height = function()
      return 4
    end,
    nvim_win_get_width = function()
      return 20
    end,
    nvim_open_win = function()
      error("open failed")
    end,
  }, function()
    local bufnr, win = confirmation_footer.open(controller, 10, {
      filetype = "codux-test-footer",
      zindex = 1,
      segments = segments,
    })

    assert_nil(bufnr)
    assert_nil(win)
  end)

  assert_equal(deleted, 44)
end

do
  local controller = {
    workspace_ui = workspace_ui,
    is_valid_win = function()
      return false
    end,
    ui = {
      create_scratch_buffer = function()
        error("invalid owner windows should not create footer buffers")
      end,
    },
  }

  local bufnr, win = confirmation_footer.open(controller, 10, {
    filetype = "codux-test-footer",
    zindex = 1,
    segments = segments,
  })
  assert_nil(bufnr)
  assert_nil(win)
end

print("confirmation_footer_spec.lua: ok")
