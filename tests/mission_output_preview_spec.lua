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


print("mission_output_preview_spec.lua: ok")
