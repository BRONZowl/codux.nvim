local mission_control_mod = require("codux.mission_control")

local M = {}

local function extend(target, source)
  target = type(target) == "table" and target or {}
  for key, value in pairs(type(source) == "table" and source or {}) do
    target[key] = value
  end
  return target
end

function M.output_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  if type(lines) == "table" then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end
  return bufnr
end

function M.preview()
  return {
    command = { "env", "-u", "TMUX", "tmux", "attach-session", "-f", "read-only", "-t", "codux-preview-test" },
    preview_session = "codux-preview-test",
  }
end

function M.role(safe_name, mission_role, status)
  return {
    safe_name = safe_name,
    mission_role = mission_role,
    status = status,
  }
end

function M.dashboard_state_for_roles(roles, opts)
  opts = type(opts) == "table" and opts or {}
  return extend({
    mission_dashboard_buf = 10,
    mission_dashboard_win = 11,
    mission_dashboard_items = {
      [3] = {
        kind = "mission",
        mission = {
          roles = roles,
        },
      },
    },
    mission_dashboard_selectable_rows = { 3 },
    mission_dashboard_search_confirmed = true,
    mission_dashboard_selected_row = 3,
  }, opts)
end

function M.set_lines_to_buffer(target, lines, opts)
  opts = type(opts) == "table" and opts or {}
  if opts.modifiable then
    vim.api.nvim_set_option_value("modifiable", true, { buf = target })
  end
  vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
  if opts.modifiable then
    vim.api.nvim_set_option_value("modifiable", false, { buf = target })
  end
  return true
end

function M.controller(opts)
  opts = type(opts) == "table" and opts or {}
  local ctx = {
    bufnr = opts.bufnr or M.output_buffer(),
    rendered_lines = nil,
  }

  local controller_state = extend({
    mission_dashboard_output_buf = ctx.bufnr,
    mission_dashboard_output_win = opts.output_win or 13,
  }, opts.state)

  local controller_opts = extend({
    namespace = opts.namespace,
    state = controller_state,
    is_loaded_buf = function(target)
      return (type(target) == "number" and vim.api.nvim_buf_is_loaded(target)) or target == controller_state.mission_dashboard_buf
    end,
    is_valid_win = function(win)
      return win == controller_state.mission_dashboard_win
        or win == controller_state.mission_dashboard_output_win
        or (type(win) == "number" and vim.api.nvim_win_is_valid(win))
    end,
    ui = {
      create_scratch_buffer = function(options)
        options = type(options) == "table" and options or {}
        local bufnr = vim.api.nvim_create_buf(false, true)
        for key, value in pairs(options) do
          pcall(vim.api.nvim_set_option_value, key, value, { buf = bufnr })
        end
        return bufnr
      end,
      set_lines = function(_, lines)
        ctx.rendered_lines = lines
        return true
      end,
      close_window = function(win)
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end,
      delete_buffer = function(bufnr)
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end,
      set_window_options = function(win, options)
        for key, value in pairs(type(options) == "table" and options or {}) do
          pcall(vim.api.nvim_set_option_value, key, value, { win = win })
        end
        return true
      end,
    },
  }, opts.controller)

  for _, key in ipairs({
    "namespace",
    "is_loaded_buf",
    "is_valid_win",
    "get_window_width",
    "get_window_height",
    "get_window_config",
    "set_window_config",
    "set_current_win",
    "workspace_interactive_preview",
    "close_workspace_interactive_preview",
    "termopen",
    "jobstop",
    "notify",
    "set_buffer_keymap",
  }) do
    if opts[key] ~= nil then
      controller_opts[key] = opts[key]
    end
  end

  if type(opts.state) == "table" then
    controller_opts.state = extend(controller_opts.state, opts.state)
  end
  if type(opts.ui) == "table" then
    controller_opts.ui = extend(controller_opts.ui, opts.ui)
  end

  return mission_control_mod.new(controller_opts), ctx
end

function M.delete_buffer(bufnr)
  if type(vim.api) == "table" and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

return M
