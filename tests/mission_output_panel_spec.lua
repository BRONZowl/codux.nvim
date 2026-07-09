local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local mission_control_mod = require("codux.mission_control")
local output_fixtures = require("tests.mission_output_fixtures")

if type(vim.api) == "table" then
  local bufnr = output_fixtures.output_buffer()
  local preview_entry
  local term_command
  local modified_at_termopen
  local controller, ctx = output_fixtures.controller({
    bufnr = bufnr,
    namespace = vim.api.nvim_create_namespace("codux.mission_output.test"),
    state = {
      mission_dashboard_buf = 10,
      mission_dashboard_win = 11,
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
      mission_dashboard_items = {
        [3] = { kind = "mission", mission = { roles = { { safe_name = "alpha-builder", mission_role = "Builder" } } } },
        [5] = { kind = "role", entry = { safe_name = "alpha-reviewer", mission_role = "Reviewer", status = "idle" } },
      },
      mission_dashboard_selectable_rows = { 3, 5 },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 5,
    },
    is_loaded_buf = function(bufnr)
      return bufnr == 10 or vim.api.nvim_buf_is_loaded(bufnr)
    end,
    is_valid_win = function(win)
      return win == 11 or win == 13
    end,
    get_window_width = function()
      return 80
    end,
    get_window_height = function()
      return 6
    end,
    workspace_interactive_preview = function(entry)
      preview_entry = entry
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-f", "read-only", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function(command)
      term_command = command
      modified_at_termopen = vim.api.nvim_get_option_value("modified", { buf = vim.api.nvim_get_current_buf() })
      return 77
    end,
  })

  assert_equal(controller:selected_output_entry().safe_name, "alpha-reviewer")
  assert_true(controller:render_output_panel())
  assert_equal(preview_entry.safe_name, "alpha-reviewer")
  local command_text = table.concat(term_command, " ")
  assert_equal(command_text, "env -u TMUX tmux attach-session -f read-only -t codux-preview-test")
  assert_equal(command_text:find(" -r ", 1, true), nil)
  assert_equal(command_text:find("ignore-size", 1, true), nil)
  assert_false(modified_at_termopen)
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  assert_equal(vim.api.nvim_get_option_value("filetype", { buf = controller.state.mission_dashboard_output_buf }), "codux")
  assert_contains(table.concat(ctx.rendered_lines, "\n"), "Output: Reviewer")
  assert_equal(table.concat(ctx.rendered_lines, "\n"):find("Ctrl-o workspace", 1, true), nil)
  assert_equal(table.concat(ctx.rendered_lines, "\n"):find("Ctrl-q", 1, true), nil)
  output_fixtures.delete_buffer(bufnr)
end

do
  local bound = {}
  local closed = false
  local focused = false
  local exited = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_entry = {
        name = "Builder",
        safe_name = "alpha-builder",
        project_root = "/repo",
        mission_role = "Builder",
        status = "idle",
      },
    },
    set_buffer_keymap = function(_, mode, lhs, rhs, desc)
      local modes = type(mode) == "table" and table.concat(mode, ",") or mode
      if modes:find("n", 1, true) or modes:find("t", 1, true) then
        bound[lhs] = { rhs = rhs, desc = desc, mode = modes }
      end
    end,
  })
  function controller:close_dashboard()
    closed = true
    return true
  end
  function controller:render_output_panel()
    return true
  end
  function controller:focus_mission_list()
    focused = true
    return true
  end
  function controller:exit_output_control()
    exited = true
    self.state.mission_dashboard_output_control = false
    return true
  end

  controller:bind_output_panel_commands(12)
  assert_equal(bound["<C-q>"].desc, "Close Codux Missions")
  assert_equal(bound["<C-o>"].desc, "Return to Codux Missions")
  assert_nil(bound["<Esc>"])
  assert_nil(bound.r)
  assert_nil(bound.o)
  assert_nil(bound.p)
  assert_nil(bound.e)
  assert_nil(bound.x)
  assert_nil(bound.d)
  assert_nil(bound.n)
  assert_nil(bound.w)
  assert_true(bound["<C-q>"].rhs())
  assert_true(closed)
  assert_true(bound["<C-o>"].rhs())
  assert_true(focused)
  controller.state.mission_dashboard_output_control = true
  assert_true(bound["<C-o>"].rhs())
  assert_true(exited)
end

if type(vim.api) == "table" then
  local bound = {}
  local controller, ctx = output_fixtures.controller({
    set_buffer_keymap = function(_, mode, lhs, rhs, desc)
      table.insert(bound, {
        mode = type(mode) == "table" and table.concat(mode, ",") or mode,
        lhs = lhs,
        rhs = rhs,
        desc = desc,
      })
    end,
  })

  local function has_mapping(lhs, desc)
    for _, mapping in ipairs(bound) do
      if mapping.lhs == lhs and mapping.desc == desc then
        return true
      end
    end
    return false
  end

  assert_true(controller:prepare_output_terminal_buffer())
  assert_equal(vim.api.nvim_get_option_value("filetype", { buf = controller.state.mission_dashboard_output_buf }), "codux")
  assert_true(has_mapping("<CR>", "Submit Codux Prompt"))
  assert_true(has_mapping("<C-c>", "Interrupt Codex"))
  assert_true(has_mapping("<S-Tab>", "Switch Codex Mode"))
  assert_true(has_mapping("<C-o>", "Return to Codux Missions"))
  assert_true(has_mapping("<ScrollWheelDown>", "Scroll Codux Output"))
  assert_true(has_mapping("<ScrollWheelUp>", "Scroll Codux Output"))
  assert_false(has_mapping("q", "Close Codux Missions"))
  output_fixtures.delete_buffer(controller.state.mission_dashboard_output_buf)
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  h.with_stubs({
    {
      target = vim.fn,
      key = "jobwait",
      value = function()
        return { -1 }
      end,
    },
    {
      target = vim.fn,
      key = "getmousepos",
      value = function()
        return {
          winid = 13,
          winrow = 4,
          wincol = 9,
        }
      end,
    },
    {
      target = vim.fn,
      key = "chansend",
      value = function(job_id, sequence)
        vim.g.codux_output_scroll_job = job_id
        vim.g.codux_output_scroll_sequence = sequence
        return 1
      end,
    },
  }, function()
    local controller, ctx = output_fixtures.controller({
      state = {
        mission_dashboard_output_control = true,
        mission_dashboard_output_job = 77,
        mission_dashboard_output_win = 13,
      },
    })

    assert_true(controller:send_output_terminal_mouse(65))
    assert_equal(vim.g.codux_output_scroll_job, 77)
    assert_equal(vim.g.codux_output_scroll_sequence, "\27[<65;9;4M")
    vim.g.codux_output_scroll_job = nil
    vim.g.codux_output_scroll_sequence = nil
    output_fixtures.delete_buffer(ctx.bufnr)
  end)
end

do
  local stopped_job
  local closed_preview
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_job = 77,
      mission_dashboard_output_preview = { preview_session = "codux-preview-test" },
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

  controller:close_output_preview()
  assert_equal(stopped_job, 77)
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
end

do
  local closed_win
  local deleted_buf
  local stopped_job
  local closed_preview
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_win = 13,
      mission_dashboard_output_buf = 14,
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
      close_window = function(win)
        closed_win = win
      end,
      delete_buffer = function(buf)
        deleted_buf = buf
      end,
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

  assert_true(controller:close_output_panel())
  assert_equal(closed_win, 13)
  assert_equal(deleted_buf, 14)
  assert_equal(stopped_job, 77)
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_win)
  assert_nil(controller.state.mission_dashboard_output_buf)
  assert_nil(controller.state.mission_dashboard_output_entry)
  assert_nil(controller.state.mission_dashboard_output_key)
  assert_nil(controller.state.mission_dashboard_output_blocked_key)
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
  assert_nil(controller.state.mission_dashboard_output_buf_kind)
  assert_false(controller.state.mission_dashboard_output_control)
  assert_nil(controller.state.mission_dashboard_output_control_key)
end

do
  local old_api = vim.api
  local highlights = {}
  vim.api = {
    nvim_buf_clear_namespace = function() end,
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

  local controller = mission_control_mod.new({ namespace = 99 })
  controller:highlight_output_panel(12, { "Output: Reviewer", "  opening workspace session preview..." })

  local output_line_comment = false
  local output_line_accent = false
  local indented_line_comment = false
  for _, highlight in ipairs(highlights) do
    if highlight.row == 0 and highlight.group == "Comment" and highlight.start_col == 0 and highlight.end_col == -1 then
      output_line_comment = true
    end
    if highlight.row == 0 and highlight.group == "WhichKeyDesc" then
      output_line_accent = true
    end
    if highlight.row == 1 and highlight.group == "Comment" and highlight.start_col == 0 and highlight.end_col == -1 then
      indented_line_comment = true
    end
  end

  assert_true(output_line_comment)
  assert_false(output_line_accent)
  assert_true(indented_line_comment)

  vim.api = old_api
end

print("mission_output_panel_spec.lua: ok")
