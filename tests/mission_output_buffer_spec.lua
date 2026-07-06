local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local mission_control_mod = require("codux.mission_control")
local output_fixtures = require("tests.mission_output_fixtures")
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
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-f", "read-only", "-t", "codux-preview-test" },
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


print("mission_output_buffer_spec.lua: ok")
