local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local mission_control_mod = require("codux.mission_control")

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local preview_entry
  local term_command
  local modified_at_termopen
  local controller = mission_control_mod.new({
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
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function(entry)
      preview_entry = entry
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function(command)
      term_command = command
      modified_at_termopen = vim.api.nvim_get_option_value("modified", { buf = bufnr })
      return 77
    end,
  })

  assert_equal(controller:selected_output_entry().safe_name, "alpha-reviewer")
  assert_true(controller:render_output_panel())
  assert_equal(preview_entry.safe_name, "alpha-reviewer")
  assert_equal(table.concat(term_command, " "), "env -u TMUX tmux attach-session -t codux-preview-test")
  assert_false(modified_at_termopen)
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  assert_contains(table.concat(rendered_lines, "\n"), "Output: Reviewer")
  assert_equal(table.concat(rendered_lines, "\n"):find("Ctrl-o workspace", 1, true), nil)
  assert_equal(table.concat(rendered_lines, "\n"):find("Ctrl-q", 1, true), nil)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local old_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, { "opening workspace session preview..." })
  local win = vim.api.nvim_open_win(old_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 40,
    height = 3,
    style = "minimal",
  })
  vim.api.nvim_set_option_value("winfixbuf", true, { win = win })

  local visible_buf_at_termopen
  local winfixbuf_at_termopen
  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_output.winfixbuf.test"),
    state = {
      mission_dashboard_output_buf = old_buf,
      mission_dashboard_output_win = win,
      mission_dashboard_output_buf_kind = "status",
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function()
      visible_buf_at_termopen = vim.api.nvim_win_get_buf(win)
      winfixbuf_at_termopen = vim.api.nvim_get_option_value("winfixbuf", { win = win })
      return 77
    end,
  })
  controller:attach_output_buffer_autocmd(old_buf)

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  assert_equal(vim.api.nvim_win_get_buf(win), controller.state.mission_dashboard_output_buf)
  assert_equal(visible_buf_at_termopen, controller.state.mission_dashboard_output_buf)
  assert_false(winfixbuf_at_termopen)
  assert_false(vim.api.nvim_get_option_value("winfixbuf", { win = win }))
  assert_true(vim.api.nvim_win_is_valid(controller.state.mission_dashboard_output_win))
  assert_false(vim.api.nvim_buf_is_valid(old_buf))
  assert_nil(controller.state.mission_dashboard_output_replacing_buf)
  local output_buf = controller.state.mission_dashboard_output_buf
  vim.api.nvim_win_close(win, true)
  if vim.api.nvim_buf_is_valid(output_buf) then
    vim.api.nvim_buf_delete(output_buf, { force = true })
  end
end

if type(vim.api) == "table" then
  local output_buf = vim.api.nvim_create_buf(false, true)
  local other_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, { "other buffer" })
  local win = vim.api.nvim_open_win(output_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 40,
    height = 3,
    style = "minimal",
  })
  vim.api.nvim_set_option_value("winfixbuf", true, { win = win })

  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = output_buf,
      mission_dashboard_output_win = win,
      mission_dashboard_output_job = 77,
    },
  })

  assert_true(controller:focus_output_panel())
  assert_false(vim.api.nvim_get_option_value("winfixbuf", { win = win }))
  local ok, error_message = pcall(vim.cmd, "buffer " .. tostring(other_buf))
  assert_true(ok, tostring(error_message))
  assert_equal(vim.api.nvim_win_get_buf(win), other_buf)

  vim.api.nvim_win_close(win, true)
  if vim.api.nvim_buf_is_valid(output_buf) then
    vim.api.nvim_buf_delete(output_buf, { force = true })
  end
  if vim.api.nvim_buf_is_valid(other_buf) then
    vim.api.nvim_buf_delete(other_buf, { force = true })
  end
end

if type(vim.api) == "table" then
  local old_buf = vim.api.nvim_create_buf(false, true)
  local deleted = {}
  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_output.swap_failure.test"),
    state = {
      mission_dashboard_output_buf = old_buf,
      mission_dashboard_output_win = 13,
      mission_dashboard_output_buf_kind = "status",
    },
    ui = {
      create_scratch_buffer = function(options)
        local bufnr = vim.api.nvim_create_buf(false, true)
        for option, value in pairs(options or {}) do
          pcall(vim.api.nvim_set_option_value, option, value, { buf = bufnr })
        end
        return bufnr
      end,
      set_lines = function(target, lines)
        vim.api.nvim_set_option_value("modifiable", true, { buf = target })
        vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
        vim.api.nvim_set_option_value("modifiable", false, { buf = target })
        return true
      end,
      delete_buffer = function(target)
        table.insert(deleted, target)
        if vim.api.nvim_buf_is_valid(target) then
          vim.api.nvim_buf_delete(target, { force = true })
        end
      end,
    },
    set_buffer_keymap = function()
      return true
    end,
  })
  function controller:set_output_window_buffer()
    return false
  end

  assert_false(controller:replace_output_buffer("terminal"))
  assert_equal(controller.state.mission_dashboard_output_buf, old_buf)
  assert_equal(controller.state.mission_dashboard_output_buf_kind, "status")
  assert_nil(controller.state.mission_dashboard_output_replacing_buf)
  assert_equal(#deleted, 1)
  assert_true(deleted[1] ~= old_buf)
  assert_true(vim.api.nvim_buf_is_valid(old_buf))
  assert_false(vim.api.nvim_buf_is_valid(deleted[1]))
  vim.api.nvim_buf_delete(old_buf, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local modified_at_termopen
  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_output.modified.test"),
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(target, lines, opts)
        opts = type(opts) == "table" and opts or {}
        if opts.modifiable then
          vim.api.nvim_set_option_value("modifiable", true, { buf = target })
        end
        vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
        if opts.modifiable then
          vim.api.nvim_set_option_value("modifiable", false, { buf = target })
        end
        return true
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function()
      modified_at_termopen = vim.api.nvim_get_option_value("modified", { buf = bufnr })
      return 77
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_false(modified_at_termopen)
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local preview_called = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_buf = 10,
      mission_dashboard_win = 11,
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
      mission_dashboard_items = {
        [3] = {
          kind = "mission",
          mission = {
            roles = {
              { safe_name = "alpha-builder", mission_role = "Builder", status = "inactive" },
              { safe_name = "alpha-reviewer", mission_role = "Reviewer", status = "idle" },
            },
          },
        },
      },
      mission_dashboard_selectable_rows = { 3 },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 3,
    },
    is_loaded_buf = function(target)
      return target == 10 or (target == bufnr and vim.api.nvim_buf_is_loaded(target))
    end,
    is_valid_win = function(win)
      return win == 11 or win == 13
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function(entry)
      preview_called = true
      assert_equal(entry.safe_name, "alpha-reviewer")
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function()
      return 77
    end,
  })

  assert_nil(controller:selected_output_entry())
  assert_true(controller:render_output_panel())
  assert_false(preview_called)
  assert_equal(table.concat(rendered_lines, "\n"), "Output: select a workspace row to preview its Codux session")
  assert_nil(controller.state.mission_dashboard_output_entry)
  assert_nil(controller.state.mission_dashboard_output_job)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local preview_entry
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_buf = 10,
      mission_dashboard_win = 11,
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
      mission_dashboard_items = {
        [3] = {
          kind = "mission",
          mission = {
            roles = {
              { safe_name = "alpha-architect", mission_role = "Architect", status = "active" },
              { safe_name = "alpha-reviewer", mission_role = "Reviewer", status = "question" },
            },
          },
        },
      },
      mission_dashboard_selectable_rows = { 3 },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 3,
    },
    is_loaded_buf = function(target)
      return target == 10 or (target == bufnr and vim.api.nvim_buf_is_loaded(target))
    end,
    is_valid_win = function(win)
      return win == 11 or win == 13
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
        return true
      end,
    },
    workspace_interactive_preview = function(entry)
      preview_entry = entry
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function()
      return 77
    end,
  })

  assert_nil(controller:selected_output_entry())
  assert_true(controller:render_output_panel())
  assert_nil(preview_entry)
  assert_equal(table.concat(rendered_lines, "\n"), "Output: select a workspace row to preview its Codux session")
  assert_nil(controller.state.mission_dashboard_output_entry)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local preview_called = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_buf = 10,
      mission_dashboard_win = 11,
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
      mission_dashboard_items = {
        [3] = {
          kind = "mission",
          mission = {
            roles = {
              { safe_name = "alpha-builder", mission_role = "Builder", status = "inactive" },
              { safe_name = "alpha-reviewer", mission_role = "Reviewer", status = "inactive" },
            },
          },
        },
      },
      mission_dashboard_selectable_rows = { 3 },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 3,
    },
    is_loaded_buf = function(target)
      return target == 10 or (target == bufnr and vim.api.nvim_buf_is_loaded(target))
    end,
    is_valid_win = function(win)
      return win == 11 or win == 13
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      preview_called = true
      return nil, "should not be called"
    end,
  })

  assert_nil(controller:selected_output_entry())
  assert_true(controller:render_output_panel())
  assert_false(preview_called)
  assert_equal(table.concat(rendered_lines, "\n"), "Output: select a workspace row to preview its Codux session")
  assert_nil(controller.state.mission_dashboard_output_entry)
  assert_nil(controller.state.mission_dashboard_output_job)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local closed_preview
  local termopen_calls = 0
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
    termopen = function()
      termopen_calls = termopen_calls + 1
      error("permission denied")
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  local rendered_text = table.concat(rendered_lines, "\n")
  assert_contains(rendered_text, "failed to attach workspace session preview: ")
  assert_contains(rendered_text, "permission denied")
  assert_contains(rendered_text, "env -u TMUX tmux attach-session -t codux-preview-test")
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
  assert_equal(termopen_calls, 1)
  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(termopen_calls, 1)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local on_exit
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function(_, opts)
      on_exit = opts.on_exit
      return 77
    end,
    jobstop = function()
      return true
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_true(controller:render_output_panel({
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "inactive",
  }))
  on_exit(77, 2)
  assert_equal(table.concat(rendered_lines, "\n"), "Output: workspace inactive")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local closed_preview
  local termopen_calls = 0
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
    termopen = function()
      termopen_calls = termopen_calls + 1
      return 0
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  local rendered_text = table.concat(rendered_lines, "\n")
  assert_contains(rendered_text, "failed to attach workspace session preview: invalid job id 0")
  assert_contains(rendered_text, "env -u TMUX tmux attach-session -t codux-preview-test")
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
  assert_equal(termopen_calls, 1)
  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(termopen_calls, 1)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local closed_preview
  local on_exit
  local termopen_calls = 0
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
    termopen = function(_, opts)
      termopen_calls = termopen_calls + 1
      on_exit = opts.on_exit
      return 77
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  on_exit(77, 2)
  assert_contains(table.concat(rendered_lines, "\n"), "workspace preview exited with code 2")
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
  assert_equal(termopen_calls, 1)
  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(termopen_calls, 1)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local preview_called = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      preview_called = true
      return nil, "should not be called"
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "inactive",
  }))
  assert_false(preview_called)
  local rendered_text = table.concat(rendered_lines, "\n")
  assert_contains(rendered_text, "Output: workspace inactive")
  assert_equal(rendered_text:find("Output: Reviewer", 1, true), nil)
  assert_equal(rendered_text:find("alpha-reviewer", 1, true), nil)
  assert_equal(rendered_text:find("Ctrl-o workspace", 1, true), nil)
  assert_equal(rendered_text:find("Ctrl-q", 1, true), nil)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local terminal_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_call(terminal_buf, function()
    vim.fn.termopen({ "sh", "-c", "printf stale-terminal; exit 0" })
  end)
  vim.wait(100)

  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_output.replace_terminal.test"),
    state = {
      mission_dashboard_output_buf = terminal_buf,
      mission_dashboard_output_win = 13,
      mission_dashboard_output_buf_kind = "terminal",
    },
    is_valid_win = function()
      return false
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "inactive",
  }))
  assert_true(controller.state.mission_dashboard_output_buf ~= terminal_buf)
  assert_equal(vim.api.nvim_get_option_value("buftype", { buf = controller.state.mission_dashboard_output_buf }), "nofile")
  local lines = vim.api.nvim_buf_get_lines(controller.state.mission_dashboard_output_buf, 0, -1, false)
  assert_equal(table.concat(lines, "\n"), "Output: workspace inactive")
  assert_false(vim.api.nvim_buf_is_valid(terminal_buf))
  vim.api.nvim_buf_delete(controller.state.mission_dashboard_output_buf, { force = true })
end

do
  local bound = {}
  local closed = false
  local opened_name
  local opened_root
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
  controller.open_saved_workspace = function(name, root)
    opened_name = name
    opened_root = root
    return true
  end

  controller:bind_output_panel_commands(12)
  assert_equal(bound["<C-q>"].desc, "Close Codux Missions")
  assert_nil(bound["<C-o>"])
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
  assert_nil(opened_name)
  assert_nil(opened_root)
end

do
  local closed = false
  local opened_name
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_items = {
        [5] = {
          kind = "role",
          entry = {
            name = "Builder",
            safe_name = "alpha-builder",
            project_root = "/repo",
            mission_role = "Builder",
            status = "idle",
          },
        },
      },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 5,
      mission_dashboard_output_entry = {
        name = "Stale",
        safe_name = "stale-builder",
        project_root = "/repo",
      },
    },
    open_saved_workspace = function(name)
      opened_name = name
      return true
    end,
  })
  function controller:close_dashboard()
    closed = true
    return true
  end

  assert_true(controller:open_output_workspace())
  assert_equal(opened_name, "alpha-builder")
  assert_true(closed)
end

do
  local closed = false
  local opened_name
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_entry = {
        name = "Builder",
        safe_name = "alpha-builder",
        project_root = "/repo",
      },
    },
    open_saved_workspace = function(name)
      opened_name = name
      return false
    end,
  })
  function controller:close_dashboard()
    closed = true
    return true
  end

  assert_false(controller:open_output_workspace())
  assert_equal(opened_name, "alpha-builder")
  assert_false(closed)
end

do
  local notifications = {}
  local controller = mission_control_mod.new({
    state = {},
    notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end,
  })

  assert_false(controller:open_output_workspace())
  assert_equal(notifications[1].message, "No Codux workspace selected")
  assert_equal(notifications[1].level, vim.log.levels.WARN)
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
