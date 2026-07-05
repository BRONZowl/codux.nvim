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

function M.controller(opts)
  opts = type(opts) == "table" and opts or {}
  local ctx = {
    bufnr = opts.bufnr or M.output_buffer(),
    rendered_lines = nil,
  }

  local controller_opts = extend({
    namespace = opts.namespace,
    state = extend({
      mission_dashboard_output_buf = ctx.bufnr,
      mission_dashboard_output_win = opts.output_win or 13,
    }, opts.state),
    is_loaded_buf = function(target)
      return target == ctx.bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        ctx.rendered_lines = lines
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
