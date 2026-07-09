local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local mission_control_mod = require("codux.mission_control")
local output_fixtures = require("tests.mission_output_fixtures")
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
      return output_fixtures.preview(), nil
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
  local preview_entry
  local controller, ctx = output_fixtures.controller({
    controller = {
      reconcile_workspace_entry = function(entry)
        local updated = vim.deepcopy(entry)
        updated.project_root = "/new"
        updated.worktree_path = "/new"
        return updated, nil
      end,
    },
    workspace_interactive_preview = function(entry)
      preview_entry = entry
      return output_fixtures.preview(), nil
    end,
    termopen = function()
      return 77
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    project_root = "/old",
    worktree_path = "/old",
    workspace_kind = "worktree",
    worktree_branch = "dev/alpha-builder",
  }))
  assert_equal(preview_entry.project_root, "/new")
  assert_equal(controller.state.mission_dashboard_output_entry.project_root, "/new")
  assert_equal(controller.state.mission_dashboard_output_key, controller:output_entry_key(preview_entry))
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local preview_called = false
  local controller, ctx = output_fixtures.controller({
    state = output_fixtures.dashboard_state_for_roles({
      output_fixtures.role("alpha-builder", "Builder", "inactive"),
      output_fixtures.role("alpha-reviewer", "Reviewer", "idle"),
    }),
    workspace_interactive_preview = function(entry)
      preview_called = true
      assert_equal(entry.safe_name, "alpha-reviewer")
      return output_fixtures.preview(), nil
    end,
    termopen = function()
      return 77
    end,
  })

  assert_nil(controller:selected_output_entry())
  assert_true(controller:render_output_panel())
  assert_false(preview_called)
  assert_equal(table.concat(ctx.rendered_lines, "\n"), "Output: select a workspace row to preview its Codux session")
  assert_nil(controller.state.mission_dashboard_output_entry)
  assert_nil(controller.state.mission_dashboard_output_job)
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local preview_entry
  local controller, ctx = output_fixtures.controller({
    state = output_fixtures.dashboard_state_for_roles({
      output_fixtures.role("alpha-architect", "Architect", "active"),
      output_fixtures.role("alpha-reviewer", "Reviewer", "question"),
    }),
    workspace_interactive_preview = function(entry)
      preview_entry = entry
      return output_fixtures.preview(), nil
    end,
    termopen = function()
      return 77
    end,
  })

  assert_nil(controller:selected_output_entry())
  assert_true(controller:render_output_panel())
  assert_nil(preview_entry)
  assert_equal(table.concat(ctx.rendered_lines, "\n"), "Output: select a workspace row to preview its Codux session")
  assert_nil(controller.state.mission_dashboard_output_entry)
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local preview_called = false
  local controller, ctx = output_fixtures.controller({
    state = output_fixtures.dashboard_state_for_roles({
      output_fixtures.role("alpha-builder", "Builder", "inactive"),
      output_fixtures.role("alpha-reviewer", "Reviewer", "inactive"),
    }),
    workspace_interactive_preview = function()
      preview_called = true
      return nil, "should not be called"
    end,
  })

  assert_nil(controller:selected_output_entry())
  assert_true(controller:render_output_panel())
  assert_false(preview_called)
  assert_equal(table.concat(ctx.rendered_lines, "\n"), "Output: select a workspace row to preview its Codux session")
  assert_nil(controller.state.mission_dashboard_output_entry)
  assert_nil(controller.state.mission_dashboard_output_job)
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local closed_preview
  local termopen_calls = 0
  local controller, ctx = output_fixtures.controller({
    workspace_interactive_preview = function()
      return output_fixtures.preview(), nil
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
  local rendered_text = table.concat(ctx.rendered_lines, "\n")
  assert_contains(rendered_text, "failed to attach workspace session preview: ")
  assert_contains(rendered_text, "permission denied")
  assert_contains(rendered_text, "env -u TMUX tmux attach-session -f read-only -t codux-preview-test")
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
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local on_exit
  local controller, ctx = output_fixtures.controller({
    workspace_interactive_preview = function()
      return output_fixtures.preview(), nil
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
  assert_equal(table.concat(ctx.rendered_lines, "\n"), "Output: workspace inactive")
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local closed_preview
  local stopped_job
  local preview_calls = 0
  local preview_entries = {}
  local controller, ctx = output_fixtures.controller({
    workspace_interactive_preview = function(entry)
      preview_calls = preview_calls + 1
      table.insert(preview_entries, entry)
      return output_fixtures.preview(), nil
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
    jobstop = function(job_id)
      stopped_job = job_id
      return true
    end,
    termopen = function()
      return 77
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
    window_id = "@1",
  }))
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "inactive",
    window_id = "@1",
  }))
  assert_equal(stopped_job, 77)
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_equal(preview_calls, 1)
  assert_equal(preview_entries[1].window_id, "@1")
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
  assert_equal(table.concat(ctx.rendered_lines, "\n"), "Output: workspace inactive")
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local closed_preview
  local stopped_jobs = {}
  local preview_entries = {}
  local next_job = 77
  local controller, ctx = output_fixtures.controller({
    workspace_interactive_preview = function(entry)
      table.insert(preview_entries, entry)
      return output_fixtures.preview(), nil
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
    jobstop = function(job_id)
      table.insert(stopped_jobs, job_id)
      return true
    end,
    termopen = function()
      local job = next_job
      next_job = next_job + 1
      return job
    end,
  })
  controller.output_preview_running = function()
    return true
  end

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
    window_id = "@1",
  }))
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
    window_id = "@2",
  }))
  assert_nil(stopped_jobs[1])
  assert_nil(closed_preview)
  assert_equal(#preview_entries, 1)
  assert_equal(preview_entries[1].window_id, "@1")
  assert_equal(controller.state.mission_dashboard_output_entry.window_id, "@2")
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  assert_contains(table.concat(ctx.rendered_lines, "\n"), "Output: Reviewer")
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local stopped_jobs = {}
  local preview_entries = {}
  local next_job = 77
  local controller, ctx = output_fixtures.controller({
    workspace_interactive_preview = function(entry)
      table.insert(preview_entries, entry)
      return output_fixtures.preview(), nil
    end,
    close_workspace_interactive_preview = function()
      return true
    end,
    jobstop = function(job_id)
      table.insert(stopped_jobs, job_id)
      return true
    end,
    termopen = function()
      local job = next_job
      next_job = next_job + 1
      return job
    end,
  })
  controller.output_preview_running = function()
    return true
  end

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
    window_name = "review",
    tmux_target = "session:review",
  }))
  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
    window_name = "review-next",
    tmux_target = "session:review-next",
  }))
  assert_nil(stopped_jobs[1])
  assert_equal(#preview_entries, 1)
  assert_equal(preview_entries[1].window_name, "review")
  assert_equal(controller.state.mission_dashboard_output_entry.window_name, "review-next")
  assert_equal(controller.state.mission_dashboard_output_entry.tmux_target, "session:review-next")
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  assert_contains(table.concat(ctx.rendered_lines, "\n"), "Output: Reviewer")
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local closed_preview
  local termopen_calls = 0
  local controller, ctx = output_fixtures.controller({
    workspace_interactive_preview = function()
      return output_fixtures.preview(), nil
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
  local rendered_text = table.concat(ctx.rendered_lines, "\n")
  assert_contains(rendered_text, "failed to attach workspace session preview: invalid job id 0")
  assert_contains(rendered_text, "env -u TMUX tmux attach-session -f read-only -t codux-preview-test")
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
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local closed_preview
  local on_exit
  local termopen_calls = 0
  local controller, ctx = output_fixtures.controller({
    workspace_interactive_preview = function()
      return output_fixtures.preview(), nil
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
  assert_contains(table.concat(ctx.rendered_lines, "\n"), "workspace preview exited with code 2")
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
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local preview_called = false
  local controller, ctx = output_fixtures.controller({
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
  local rendered_text = table.concat(ctx.rendered_lines, "\n")
  assert_contains(rendered_text, "Output: workspace inactive")
  assert_equal(rendered_text:find("Output: Reviewer", 1, true), nil)
  assert_equal(rendered_text:find("alpha-reviewer", 1, true), nil)
  assert_equal(rendered_text:find("Ctrl-o workspace", 1, true), nil)
  assert_equal(rendered_text:find("Ctrl-q", 1, true), nil)
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  h.with_stubs({
    {
      target = vim,
      key = "cmd",
      value = function(command)
        assert_equal(command, "startinsert")
      end,
    },
    {
      target = vim.o,
      key = "mouse",
      value = "",
    },
  }, function()
    local preview_opts = {}
    local stopped_jobs = {}
    local closed_previews = {}
    local focusable_values = {}
    local focused_win
    local monitor_stopped = false
    local monitor_started = false
    local dashboard_focused = false
    local highlight_refreshes = 0
    local next_job = 77
    local entry = {
      safe_name = "alpha-reviewer",
      mission_role = "Reviewer",
      status = "idle",
    }
    local controller, ctx = output_fixtures.controller({
      state = {
        mission_dashboard_buf = 10,
        mission_dashboard_win = 11,
        mission_dashboard_command_win = 12,
        mission_dashboard_items = {
          [5] = { kind = "role", entry = entry },
        },
        mission_dashboard_selectable_rows = { 5 },
        mission_dashboard_search_confirmed = true,
        mission_dashboard_selected_row = 5,
        mission_dashboard_output_job = 55,
        mission_dashboard_output_preview = { preview_session = "codux-preview-old" },
        mission_dashboard_saved_mouse = "n",
      },
      workspace_interactive_preview = function(_, opts)
        table.insert(preview_opts, opts or {})
        return output_fixtures.preview(), nil
      end,
      close_workspace_interactive_preview = function(preview)
        table.insert(closed_previews, preview)
        return true
      end,
      jobstop = function(job_id)
        table.insert(stopped_jobs, job_id)
        return true
      end,
      termopen = function()
        local job = next_job
        next_job = next_job + 1
        return job
      end,
      get_window_config = function()
        return { relative = "editor", focusable = false }
      end,
      set_window_config = function(_, config)
        table.insert(focusable_values, config.focusable)
        return true
      end,
      set_current_win = function(win)
        focused_win = win
        return true
      end,
    })
    function controller:stop_monitor_timer()
      monitor_stopped = true
      return true
    end
    function controller:start_monitor_timer()
      monitor_started = true
      return true
    end
    function controller:focus_mission_list()
      dashboard_focused = true
      return true
    end
    function controller:refresh_dashboard_highlight()
      highlight_refreshes = highlight_refreshes + 1
      return true
    end

    assert_true(controller:enter_output_control())
    assert_true(monitor_stopped)
    assert_true(controller.state.mission_dashboard_output_control)
    assert_true(preview_opts[1].control)
    assert_equal(stopped_jobs[1], 55)
    assert_equal(closed_previews[1].preview_session, "codux-preview-old")
    assert_equal(focusable_values[1], true)
    assert_equal(focused_win, 13)
    assert_equal(controller.state.mission_dashboard_output_job, 77)
    assert_equal(vim.o.mouse, "a")
    assert_equal(highlight_refreshes, 1)

    assert_true(controller:exit_output_control())
    assert_false(controller.state.mission_dashboard_output_control)
    assert_equal(stopped_jobs[2], 77)
    assert_equal(preview_opts[2].control, nil)
    assert_equal(focusable_values[2], false)
    assert_equal(vim.o.mouse, "")
    assert_true(monitor_started)
    assert_true(dashboard_focused)
    assert_equal(controller.state.mission_dashboard_output_job, 78)
    assert_equal(highlight_refreshes, 2)
    assert_contains(table.concat(ctx.rendered_lines, "\n"), "Output: Reviewer")
    output_fixtures.delete_buffer(ctx.bufnr)
  end)
end

if type(vim.api) == "table" then
  local preview_calls = 0
  local controller, ctx = output_fixtures.controller({
    state = {
      mission_dashboard_output_control = true,
    },
    workspace_interactive_preview = function()
      preview_calls = preview_calls + 1
      return output_fixtures.preview(), nil
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(preview_calls, 0)
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  h.with_stubs({
    {
      target = vim.o,
      key = "mouse",
      value = "a",
    },
  }, function()
    local preview_opts = {}
    local on_exit
    local focusable_values = {}
    local monitor_started = false
    local dashboard_focused = false
    local highlight_refreshes = 0
    local next_job = 77
    local entry = {
      safe_name = "alpha-reviewer",
      mission_role = "Reviewer",
      status = "idle",
    }
    local controller, ctx = output_fixtures.controller({
      state = {
        mission_dashboard_output_control = true,
        mission_dashboard_output_control_mouse = true,
        mission_dashboard_saved_mouse = "a",
      },
      workspace_interactive_preview = function(_, opts)
        table.insert(preview_opts, opts or {})
        local preview = output_fixtures.preview()
        preview.control = opts and opts.control == true
        return preview, nil
      end,
      close_workspace_interactive_preview = function()
        return true
      end,
      termopen = function(_, opts)
        on_exit = opts.on_exit
        local job = next_job
        next_job = next_job + 1
        return job
      end,
      get_window_config = function()
        return { relative = "editor", focusable = true }
      end,
      set_window_config = function(_, config)
        table.insert(focusable_values, config.focusable)
        return true
      end,
    })
    function controller:start_monitor_timer()
      monitor_started = true
      return true
    end
    function controller:focus_mission_list()
      dashboard_focused = true
      return true
    end
    function controller:refresh_dashboard_highlight()
      highlight_refreshes = highlight_refreshes + 1
      return true
    end

    assert_true(controller:start_output_preview(entry, { control = true }))
    assert_true(preview_opts[1].control)
    assert_equal(controller.state.mission_dashboard_output_job, 77)
    on_exit(77, 0)
    assert_false(controller.state.mission_dashboard_output_control)
    assert_equal(preview_opts[2].control, nil)
    assert_equal(focusable_values[1], false)
    assert_equal(vim.o.mouse, "")
    assert_true(monitor_started)
    assert_true(dashboard_focused)
    assert_equal(controller.state.mission_dashboard_output_job, 78)
    assert_equal(highlight_refreshes, 1)
    output_fixtures.delete_buffer(ctx.bufnr)
  end)
end

if type(vim.api) == "table" then
  local notifications = {}
  local controller, ctx = output_fixtures.controller({
    state = output_fixtures.dashboard_state_for_roles({
      output_fixtures.role("alpha-builder", "Builder", "idle"),
    }),
    notify = function(message)
      table.insert(notifications, message)
    end,
  })

  assert_false(controller:enter_output_control())
  assert_equal(notifications[1], "Select a workspace row to control its output")
  output_fixtures.delete_buffer(ctx.bufnr)
end

if type(vim.api) == "table" then
  local notifications = {}
  local controller, ctx = output_fixtures.controller({
    state = {
      mission_dashboard_items = {
        [5] = {
          kind = "role",
          entry = {
            safe_name = "alpha-builder",
            mission_role = "Builder",
            status = "inactive",
          },
        },
      },
      mission_dashboard_selectable_rows = { 5 },
      mission_dashboard_selected_row = 5,
    },
    notify = function(message)
      table.insert(notifications, message)
    end,
  })

  assert_false(controller:enter_output_control())
  assert_equal(notifications[1], "Workspace output is inactive")
  output_fixtures.delete_buffer(ctx.bufnr)
end


print("mission_output_preview_spec.lua: ok")
