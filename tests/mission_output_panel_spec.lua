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
      mission_dashboard = {
        buf = 10,
        win = 11,
        output_buf = bufnr,
        output_win = 13,
        items = {
        [3] = { kind = "mission", mission = { roles = { { safe_name = "alpha-builder", mission_role = "Builder" } } } },
        [5] = { kind = "role", entry = { safe_name = "alpha-reviewer", mission_role = "Reviewer", status = "idle" } },
      },
        selectable_rows = { 3, 5 },
        search_confirmed = true,
        selected_row = 5,
      }},
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
  assert_equal(controller.state.mission_dashboard.output_job, 77)
  assert_equal(vim.api.nvim_get_option_value("filetype", { buf = controller.state.mission_dashboard.output_buf }), "codux")
  assert_contains(table.concat(ctx.rendered_lines, "\n"), "Output: Reviewer")
  assert_equal(table.concat(ctx.rendered_lines, "\n"):find("Ctrl-o workspace", 1, true), nil)
  assert_equal(table.concat(ctx.rendered_lines, "\n"):find("Ctrl-q", 1, true), nil)
  output_fixtures.delete_buffer(bufnr)
end

do
  -- Mission row resolves to Manager role for output preview/control.
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard = {
        items = {
        [2] = {
          kind = "mission",
          mission = {
            roles = {
              {
                safe_name = "alpha-manager",
                mission_role = "Manager",
                name = "Manager",
                status = "idle",
              },
              {
                safe_name = "alpha-agent",
                mission_role = "Agent",
                status = "idle",
              },
            },
          },
        },
        [4] = {
          kind = "role",
          entry = { safe_name = "alpha-agent", mission_role = "Agent", status = "idle" },
        },
      },
        selected_row = 2,
        selectable_rows = { 2, 4 },
        search_confirmed = true,
      }},
  })
  local entry = controller:selected_output_entry()
  assert_equal(entry.safe_name, "alpha-manager")
  assert_equal(entry.mission_role, "Manager")

  controller.state.mission_dashboard.selected_row = 4
  entry = controller:selected_output_entry()
  assert_equal(entry.safe_name, "alpha-agent")
end

do
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard = {
        items = {
        [2] = {
          kind = "mission",
          mission = {
            roles = {
              { safe_name = "alpha-builder", mission_role = "Builder", status = "active" },
            },
          },
        },
      },
        selected_row = 2,
        selectable_rows = { 2 },
        search_confirmed = true,
      }},
  })
  assert_nil(controller:selected_output_entry(), "legacy mission without Manager has no console entry")
  local lines = controller:output_panel_lines(nil)
  assert_contains(table.concat(lines, "\n"), "no Manager role")
end

if type(vim.api) == "table" then
  -- Mission compact must not attach Manager preview; Manager role row must attach cleanly.
  local manager = {
    safe_name = "alpha-manager",
    mission_role = "Manager",
    status = "idle",
    project_root = "/wt/manager",
    worktree_path = "/wt/manager",
  }
  local agent = {
    safe_name = "alpha-agent",
    mission_role = "Agent",
    status = "idle",
    project_root = "/wt/agent",
  }
  local preview_calls = {}
  local bufnr = output_fixtures.output_buffer()
  local controller, ctx = output_fixtures.controller({
    bufnr = bufnr,
    state = {
      mission_dashboard = {
        buf = 10,
        win = 11,
        output_buf = bufnr,
        output_win = 13,
        items = {
        [2] = {
          kind = "mission",
          mission = { name = "Alpha", roles = { manager, agent } },
        },
        [4] = { kind = "role", entry = manager, mission = { roles = { manager, agent } } },
        [5] = { kind = "role", entry = agent, mission = { roles = { manager, agent } } },
      },
        selectable_rows = { 2, 4, 5 },
        selected_row = 2,
        search_confirmed = true,
      }},
    workspace_interactive_preview = function(entry)
      table.insert(preview_calls, entry.safe_name)
      return output_fixtures.preview(), nil
    end,
    termopen = function()
      return 55
    end,
  })

  assert_equal(controller:selected_output_entry().safe_name, "alpha-manager")
  assert_equal(controller:dashboard_preview_mode(controller:selected_item()), "compact")
  assert_true(controller:render_output_panel())
  assert_equal(#preview_calls, 0, "mission compact must not attach interactive preview")
  assert_nil(controller.state.mission_dashboard.output_job)
  assert_nil(controller.state.mission_dashboard.output_key)
  assert_contains(table.concat(ctx.rendered_lines or {}, "\n"), "Output: Manager")
  assert_contains(table.concat(ctx.rendered_lines or {}, "\n"), "select role row to expand preview")

  -- First highlight of Manager role: full attach (no residual compact job).
  controller.state.mission_dashboard.selected_row = 4
  assert_equal(controller:dashboard_preview_mode(controller:selected_item()), "workspace")
  assert_true(controller:render_output_panel())
  assert_equal(#preview_calls, 1)
  assert_equal(preview_calls[1], "alpha-manager")
  assert_equal(controller.state.mission_dashboard.output_job, 55)
  assert_equal(controller.state.mission_dashboard.output_entry.safe_name, "alpha-manager")

  output_fixtures.delete_buffer(bufnr)
end

do
  local bound = {}
  local closed = false
  local focused = false
  local exited = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard = {
        output_entry = {
        name = "Builder",
        safe_name = "alpha-builder",
        project_root = "/repo",
        mission_role = "Builder",
        status = "idle",
      },
      }},
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
    self.state.mission_dashboard.output_control = false
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
  controller.state.mission_dashboard.output_control = true
  assert_true(bound["<C-o>"].rhs())
  assert_true(exited)
end

if type(vim.api) == "table" then
  local _, set_buffer_keymap, has_mapping = output_fixtures.keymap_capture()
  local controller, ctx = output_fixtures.controller({
    set_buffer_keymap = set_buffer_keymap,
  })

  assert_true(controller:prepare_output_terminal_buffer())
  assert_equal(vim.api.nvim_get_option_value("filetype", { buf = controller.state.mission_dashboard.output_buf }), "codux")
  assert_true(has_mapping("<CR>", "Submit Codux Prompt"))
  assert_true(has_mapping("<C-c>", "Interrupt Agent"))
  assert_true(has_mapping("<S-Tab>", "Switch Agent Mode"))
  assert_true(has_mapping("<C-o>", "Return to Codux Missions"))
  assert_true(has_mapping("<ScrollWheelDown>", "Scroll Codux Output"))
  assert_true(has_mapping("<ScrollWheelUp>", "Scroll Codux Output"))
  assert_false(has_mapping("q", "Close Codux Missions"))
  output_fixtures.delete_buffer(controller.state.mission_dashboard.output_buf)
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local bound, set_buffer_keymap = output_fixtures.keymap_capture()
  local sent_job
  local sent_sequence
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
      key = "chansend",
      value = function(job_id, sequence)
        sent_job = job_id
        sent_sequence = sequence
        return 1
      end,
    },
  }, function()
    local controller, ctx = output_fixtures.controller({
      state = {
        mission_dashboard = {
          output_job = 77,
        }},
      set_buffer_keymap = set_buffer_keymap,
    })

    assert_true(controller:prepare_output_terminal_buffer())
    local submit
    for _, mapping in ipairs(bound) do
      if mapping.lhs == "<CR>" and mapping.desc == "Submit Codux Prompt" then
        submit = mapping.rhs
      end
    end
    assert_true(type(submit) == "function")
    assert_true(submit())
    assert_equal(sent_job, 77)
    assert_equal(sent_sequence, "\r")
    output_fixtures.delete_buffer(controller.state.mission_dashboard.output_buf)
    output_fixtures.delete_buffer(ctx.bufnr)
  end)
end

if type(vim.api) == "table" then
  local sent_job
  local sent_sequence
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
        sent_job = job_id
        sent_sequence = sequence
        return 1
      end,
    },
  }, function()
    local controller, ctx = output_fixtures.controller({
      state = {
        mission_dashboard = {
          output_control = true,
          output_job = 77,
          output_win = 13,
        }},
    })

    assert_true(controller:send_output_terminal_mouse(65))
    assert_equal(sent_job, 77)
    assert_equal(sent_sequence, "\27[<65;9;4M")
    output_fixtures.delete_buffer(ctx.bufnr)
  end)
end

do
  local stopped_job
  local closed_preview
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard = {
        output_job = 77,
        output_preview = { preview_session = "codux-preview-test" },
      }},
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
  assert_nil(controller.state.mission_dashboard.output_job)
  assert_nil(controller.state.mission_dashboard.output_preview)
end

do
  local stopped_job
  local closed_preview
  local entry = {
    safe_name = "alpha-builder",
    mission_role = "Builder",
    project_root = "/repo",
  }
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard = {
        output_job = 77,
        output_preview = { preview_session = "codux-preview-test" },
      }},
    jobstop = function(job_id)
      stopped_job = job_id
      return true
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
  })
  controller.state.mission_dashboard.output_entry = entry
  controller.state.mission_dashboard.output_key = controller:output_entry_key(entry)
  controller.state.mission_dashboard.output_blocked_key = controller.state.mission_dashboard.output_key

  assert_true(controller:invalidate_output_preview_for_entry(entry))
  assert_equal(stopped_job, 77)
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard.output_entry)
  assert_nil(controller.state.mission_dashboard.output_key)
  assert_nil(controller.state.mission_dashboard.output_blocked_key)
  assert_nil(controller.state.mission_dashboard.output_job)
  assert_nil(controller.state.mission_dashboard.output_preview)
end

do
  local stopped_job
  local entry = {
    safe_name = "alpha-builder",
    mission_role = "Builder",
    project_root = "/repo",
  }
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard = {
        output_job = 77,
        output_preview = { preview_session = "codux-preview-test" },
      }},
    jobstop = function(job_id)
      stopped_job = job_id
      return true
    end,
  })
  controller.state.mission_dashboard.output_entry = entry
  controller.state.mission_dashboard.output_key = controller:output_entry_key(entry)
  controller.state.mission_dashboard.output_blocked_key = controller.state.mission_dashboard.output_key

  assert_false(controller:invalidate_output_preview_for_entry({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    project_root = "/repo",
  }))
  assert_nil(stopped_job)
  assert_equal(controller.state.mission_dashboard.output_key, controller:output_entry_key(entry))
  assert_equal(controller.state.mission_dashboard.output_job, 77)
  assert_equal(controller.state.mission_dashboard.output_preview.preview_session, "codux-preview-test")
end

if type(vim.api) == "table" then
  local old_defer_fn = vim.defer_fn
  local scheduled = {}
  vim.defer_fn = function(callback, delay)
    table.insert(scheduled, { callback = callback, delay = delay })
  end

  local entry = {
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    project_root = "/repo",
  }
  local controller, ctx = output_fixtures.controller({
    state = {
      mission_dashboard = {
        items = {
        [5] = { kind = "role", entry = entry },
      },
        selectable_rows = { 5 },
        search_confirmed = true,
        selected_row = 5,
      }},
    workspace_interactive_preview = function()
      return output_fixtures.preview(), nil
    end,
    termopen = function()
      return 77
    end,
  })
  controller.state.mission_dashboard.output_key = controller:output_entry_key(entry)
  controller.state.mission_dashboard.output_blocked_key = controller.state.mission_dashboard.output_key

  assert_true(controller:retry_output_preview_for_entry(entry, { delays = { 25, 50 } }))
  assert_equal(#scheduled, 1)
  assert_equal(scheduled[1].delay, 25)
  scheduled[1].callback()
  assert_equal(controller.state.mission_dashboard.output_job, 77)
  assert_nil(controller.state.mission_dashboard.output_blocked_key)
  assert_equal(#scheduled, 1)

  output_fixtures.delete_buffer(ctx.bufnr)
  vim.defer_fn = old_defer_fn
end

if type(vim.api) == "table" then
  local old_defer_fn = vim.defer_fn
  local scheduled = {}
  vim.defer_fn = function(callback, delay)
    table.insert(scheduled, { callback = callback, delay = delay })
  end

  local entry = {
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    project_root = "/repo",
  }
  local controller, ctx = output_fixtures.controller({
    state = {
      mission_dashboard = {
        output_control = true,
        items = {
        [5] = { kind = "role", entry = entry },
      },
        selectable_rows = { 5 },
        search_confirmed = true,
        selected_row = 5,
      }},
  })
  local rendered = false
  function controller:render_output_panel()
    rendered = true
    return true
  end

  assert_true(controller:retry_output_preview_for_entry(entry, { delays = { 25 } }))
  scheduled[1].callback()
  assert_false(rendered)

  output_fixtures.delete_buffer(ctx.bufnr)
  vim.defer_fn = old_defer_fn
end

if type(vim.api) == "table" then
  local old_defer_fn = vim.defer_fn
  local scheduled = {}
  vim.defer_fn = function(callback, delay)
    table.insert(scheduled, { callback = callback, delay = delay })
  end

  local entry = {
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    project_root = "/repo",
  }
  local controller, ctx = output_fixtures.controller({
    state = {
      mission_dashboard = {
        items = {
        [5] = { kind = "role", entry = entry },
      },
        selectable_rows = { 5 },
        search_confirmed = true,
        selected_row = 5,
      }},
    is_loaded_buf = function()
      return false
    end,
  })
  local rendered = false
  function controller:render_output_panel()
    rendered = true
    return true
  end

  assert_true(controller:retry_output_preview_for_entry(entry, { delays = { 25 } }))
  scheduled[1].callback()
  assert_false(rendered)

  output_fixtures.delete_buffer(ctx.bufnr)
  vim.defer_fn = old_defer_fn
end

if type(vim.api) == "table" then
  local old_defer_fn = vim.defer_fn
  local scheduled = {}
  vim.defer_fn = function(callback, delay)
    table.insert(scheduled, { callback = callback, delay = delay })
  end

  local entry = {
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    project_root = "/repo",
  }
  local controller, ctx = output_fixtures.controller({
    state = {
      mission_dashboard = {
        items = {
        [5] = { kind = "role", entry = entry },
      },
        selectable_rows = { 5 },
        search_confirmed = true,
        selected_row = 5,
        output_job = 77,
      }},
  })
  local rendered = false
  function controller:output_preview_running()
    return true
  end
  function controller:render_output_panel()
    rendered = true
    return true
  end

  assert_true(controller:retry_output_preview_for_entry(entry, { delays = { 25 } }))
  scheduled[1].callback()
  assert_false(rendered)

  output_fixtures.delete_buffer(ctx.bufnr)
  vim.defer_fn = old_defer_fn
end

if type(vim.api) == "table" then
  local old_defer_fn = vim.defer_fn
  local scheduled = {}
  vim.defer_fn = function(callback, delay)
    table.insert(scheduled, { callback = callback, delay = delay })
  end

  local builder = {
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    project_root = "/repo",
  }
  local reviewer = {
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
    project_root = "/repo",
  }
  local controller, ctx = output_fixtures.controller({
    state = {
      mission_dashboard = {
        items = {
        [5] = { kind = "role", entry = reviewer },
      },
        selectable_rows = { 5 },
        search_confirmed = true,
        selected_row = 5,
      }},
  })
  local rendered = false
  function controller:render_output_panel()
    rendered = true
    return true
  end

  assert_true(controller:retry_output_preview_for_entry(builder, { delays = { 25 } }))
  scheduled[1].callback()
  assert_false(rendered)

  output_fixtures.delete_buffer(ctx.bufnr)
  vim.defer_fn = old_defer_fn
end

if type(vim.api) == "table" then
  local old_defer_fn = vim.defer_fn
  local scheduled = {}
  vim.defer_fn = function(callback, delay)
    table.insert(scheduled, { callback = callback, delay = delay })
  end

  local entry = {
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    project_root = "/repo",
  }
  local preview_calls = 0
  local controller, ctx = output_fixtures.controller({
    state = {
      mission_dashboard = {
        items = {
        [5] = { kind = "role", entry = entry },
      },
        selectable_rows = { 5 },
        search_confirmed = true,
        selected_row = 5,
      }},
    workspace_interactive_preview = function()
      preview_calls = preview_calls + 1
      return nil, "workspace agent session is not running"
    end,
  })
  controller.state.mission_dashboard.output_key = controller:output_entry_key(entry)
  controller.state.mission_dashboard.output_blocked_key = controller.state.mission_dashboard.output_key

  assert_true(controller:retry_output_preview_for_entry(entry, { delays = { 25, 50 } }))
  assert_equal(#scheduled, 1)
  scheduled[1].callback()
  assert_equal(preview_calls, 1)
  assert_equal(#scheduled, 2)
  assert_equal(scheduled[2].delay, 50)
  scheduled[2].callback()
  assert_equal(preview_calls, 2)
  assert_equal(#scheduled, 2)
  assert_equal(controller.state.mission_dashboard.output_blocked_key, controller:output_entry_key(entry))
  assert_contains(table.concat(ctx.rendered_lines, "\n"), "workspace agent session is not running")

  output_fixtures.delete_buffer(ctx.bufnr)
  vim.defer_fn = old_defer_fn
end

do
  local closed_win
  local deleted_buf
  local stopped_job
  local closed_preview
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard = {
        output_win = 13,
        output_buf = 14,
        output_entry = { safe_name = "alpha-builder" },
        output_key = "key",
        output_blocked_key = "blocked",
        output_job = 77,
        output_preview = { preview_session = "codux-preview-test" },
        output_buf_kind = "terminal",
        output_control = true,
        output_control_key = "control",
      }},
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
  assert_nil(controller.state.mission_dashboard.output_win)
  assert_nil(controller.state.mission_dashboard.output_buf)
  assert_nil(controller.state.mission_dashboard.output_entry)
  assert_nil(controller.state.mission_dashboard.output_key)
  assert_nil(controller.state.mission_dashboard.output_blocked_key)
  assert_nil(controller.state.mission_dashboard.output_job)
  assert_nil(controller.state.mission_dashboard.output_preview)
  assert_nil(controller.state.mission_dashboard.output_buf_kind)
  assert_false(controller.state.mission_dashboard.output_control)
  assert_nil(controller.state.mission_dashboard.output_control_key)
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
