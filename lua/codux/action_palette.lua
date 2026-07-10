local M = {}
M.__index = M

local ui = require("codux.ui")
local util = require("codux.util")

local api_function = util.api_function
local value_from = util.value_from

function M.palette_width(dashboard_width)
  dashboard_width = type(dashboard_width) == "number" and dashboard_width or 58
  return math.min(math.max(32, dashboard_width - 8), 48)
end

--- Build a centered floating action-palette window config over a parent dashboard.
--- @param opts table|nil
---   dashboard_width, dashboard_height, col, row, width, height, title, zindex
function M.centered_window_config(opts)
  opts = type(opts) == "table" and opts or {}
  local dashboard_width = type(opts.dashboard_width) == "number" and opts.dashboard_width or 58
  local dashboard_height = type(opts.dashboard_height) == "number" and opts.dashboard_height or 1
  local width = type(opts.width) == "number" and opts.width or M.palette_width(dashboard_width)
  local height = math.max(1, type(opts.height) == "number" and opts.height or 1)
  local col = type(opts.col) == "number" and opts.col or math.floor((vim.o.columns - dashboard_width) / 2)
  local row = type(opts.row) == "number" and opts.row or 0

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = opts.title or " ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, col + math.floor((dashboard_width - width) / 2)),
    row = math.max(0, row + math.floor((dashboard_height - height) / 2)),
    zindex = type(opts.zindex) == "number" and opts.zindex or 70,
  }
end

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local controller = {
    state = type(opts.state) == "table" and opts.state or {},
    ui = type(opts.ui) == "table" and opts.ui or ui,
    is_valid_win = type(opts.is_valid_win) == "function" and opts.is_valid_win or ui.is_valid_win,
    is_loaded_buf = type(opts.is_loaded_buf) == "function" and opts.is_loaded_buf or ui.is_loaded_buf,
    get_window_cursor = type(opts.get_window_cursor) == "function" and opts.get_window_cursor or function(win)
      local get_cursor = api_function("nvim_win_get_cursor")
      if not get_cursor then
        return nil
      end
      local ok, cursor = pcall(get_cursor, win)
      return ok and type(cursor) == "table" and cursor or nil
    end,
    set_window_cursor = type(opts.set_window_cursor) == "function" and opts.set_window_cursor or function(win, cursor)
      local set_cursor = api_function("nvim_win_set_cursor")
      if not set_cursor then
        return false
      end
      return pcall(set_cursor, win, cursor)
    end,
    open_win = type(opts.open_win) == "function" and opts.open_win or function(bufnr, enter, config)
      local open_win = api_function("nvim_open_win")
      if not open_win then
        error("nvim_open_win unavailable")
      end
      return open_win(bufnr, enter, config)
    end,
    set_buffer_keymap = type(opts.set_buffer_keymap) == "function" and opts.set_buffer_keymap or ui.set_keymap,
    bind_close_keys = type(opts.bind_close_keys) == "function" and opts.bind_close_keys or ui.bind_close_keys,
    notify = type(opts.notify) == "function" and opts.notify or util.noop,
    namespace = opts.namespace or 0,
    win_key = opts.win_key,
    buf_key = opts.buf_key,
    items_key = opts.items_key,
    target_key = opts.target_key,
    create_buffer_options = opts.create_buffer_options,
    items = type(opts.items) == "function" and opts.items or function()
      return {}
    end,
    line_for = type(opts.line_for) == "function" and opts.line_for or function(item)
      return tostring(item and item.label or "")
    end,
    width = type(opts.width) == "function" and opts.width or function()
      return 40
    end,
    window_config = type(opts.window_config) == "function" and opts.window_config or function()
      return {}
    end,
    target = type(opts.target) == "function" and opts.target or function(self)
      return self.state[self.target_key]
    end,
    assign_open_state = type(opts.assign_open_state) == "function" and opts.assign_open_state or function(self, target, _, items, bufnr)
      self.state[self.buf_key] = bufnr
      self.state[self.items_key] = items
      if self.target_key then
        self.state[self.target_key] = target
      end
    end,
    clear_state = type(opts.clear_state) == "function" and opts.clear_state or function(self)
      self.state[self.win_key] = nil
      self.state[self.buf_key] = nil
      self.state[self.items_key] = {}
      if self.target_key then
        self.state[self.target_key] = nil
      end
    end,
    action_label = opts.action_label or "Action",
    create_error = opts.create_error or "Failed to create Codux actions",
    open_error = opts.open_error or "Failed to open Codux actions",
    after_create_buffer = type(opts.after_create_buffer) == "function" and opts.after_create_buffer or nil,
    run_action = type(opts.run_action) == "function" and opts.run_action or util.noop,
    key_only = opts.key_only == true,
    sink_win_key = opts.sink_win_key or "__action_palette_sink_win",
    sink_buf_key = opts.sink_buf_key or "__action_palette_sink_buf",
  }

  return setmetatable(controller, M)
end

function M:win()
  return self.state[self.win_key]
end

function M:buf()
  return self.state[self.buf_key]
end

function M:items_list()
  return type(self.state[self.items_key]) == "table" and self.state[self.items_key] or {}
end

function M:ns(...)
  return value_from(self.namespace, ...)
end

function M:close()
  self.ui.close_window(self:win())
  self.ui.delete_buffer(self:buf())
  if self.key_only then
    self.ui.close_window(self.state[self.sink_win_key])
    self.ui.delete_buffer(self.state[self.sink_buf_key])
  end
  self:clear_state()
  if self.key_only then
    self.state[self.sink_win_key] = nil
    self.state[self.sink_buf_key] = nil
  end
  return true
end

function M.highlight_action_lines(bufnr, namespace, items)
  local clear_namespace = api_function("nvim_buf_clear_namespace")
  local add_highlight = api_function("nvim_buf_add_highlight")
  if clear_namespace then
    pcall(clear_namespace, bufnr, namespace, 0, -1)
  end
  if not add_highlight then
    return
  end
  for index, item in ipairs(type(items) == "table" and items or {}) do
    local key = tostring(item.key or "")
    if key ~= "" then
      local label_start = #key + 2
      pcall(add_highlight, bufnr, namespace, "WhichKey", index - 1, 0, #key)
      pcall(add_highlight, bufnr, namespace, "Normal", index - 1, #key, label_start)
      pcall(add_highlight, bufnr, namespace, "Normal", index - 1, label_start, -1)
    end
  end
end

function M:render(...)
  local bufnr = self:buf()
  if not self.is_loaded_buf(bufnr) then
    return false
  end

  local width = self.width(...)
  local items = self:items_list()
  local lines = {}
  for _, item in ipairs(items) do
    table.insert(lines, self.line_for(item, width, ...))
  end

  self.ui.set_lines(bufnr, lines, { modifiable = true })
  M.highlight_action_lines(bufnr, self:ns(...), items)
  return true
end

function M:run_highlighted()
  if self.key_only then
    return false
  end

  local win = self:win()
  if not self.is_valid_win(win) then
    return false
  end

  local cursor = self.get_window_cursor(win)
  if not cursor then
    return false
  end

  local action_item = self:items_list()[cursor[1]]
  if not action_item then
    return false
  end
  return self.run_action(action_item.action, self.target(self))
end

function M:move_cursor(delta)
  if self.key_only then
    return false
  end

  local win = self:win()
  if not self.is_valid_win(win) then
    return false
  end

  local count = #self:items_list()
  if count == 0 then
    return false
  end

  local cursor = self.get_window_cursor(win)
  if not cursor then
    return false
  end
  local row = ((cursor[1] - 1 + delta) % count) + 1
  self.set_window_cursor(win, { row, 0 })
  return true
end

function M:bind_keys(bufnr, target, context)
  local action_label = value_from(self.action_label, target, context)
  self.bind_close_keys(bufnr, function()
    return self:close()
  end, "Close Codux " .. action_label .. " Actions", "n", { escape = true, q = true })
  if not self.key_only then
    self.set_buffer_keymap(bufnr, "n", "<CR>", function()
      return self:run_highlighted()
    end, "Run Codux " .. action_label .. " Action")
    self.set_buffer_keymap(bufnr, "n", "j", function()
      return self:move_cursor(1)
    end, "Next Codux " .. action_label .. " Action", { nowait = true })
    self.set_buffer_keymap(bufnr, "n", "<Down>", function()
      return self:move_cursor(1)
    end, "Next Codux " .. action_label .. " Action", { nowait = true })
    self.set_buffer_keymap(bufnr, "n", "k", function()
      return self:move_cursor(-1)
    end, "Previous Codux " .. action_label .. " Action", { nowait = true })
    self.set_buffer_keymap(bufnr, "n", "<Up>", function()
      return self:move_cursor(-1)
    end, "Previous Codux " .. action_label .. " Action", { nowait = true })
  end

  for _, action_item in ipairs(self:items_list()) do
    local bound_action = action_item.action
    local bound_label = action_item.label
    self.set_buffer_keymap(bufnr, "n", action_item.key, function()
      return self.run_action(bound_action, target)
    end, bound_label .. " Codux " .. action_label, { nowait = true })
  end
end

function M:open(target, context)
  target = type(target) == "table" and target or nil
  if not target then
    return false
  end

  self:close()
  local action_items = self.items(target, context)
  local bufnr = self.ui.create_scratch_buffer(value_from(self.create_buffer_options, target, context) or {
    bufhidden = "wipe",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    self.notify(value_from(self.create_error, target, context), vim.log.levels.ERROR)
    return false
  end
  if self.after_create_buffer then
    self.after_create_buffer(bufnr, target, context)
  end

  self:assign_open_state(target, context, action_items, bufnr)
  self:render(target, context)

  local config = self.window_config(target, #action_items, context)
  config = type(config) == "table" and vim.deepcopy(config) or {}
  if self.key_only then
    config.focusable = false
  end
  local win_ok, win = pcall(self.open_win, bufnr, not self.key_only, config)
  if not win_ok then
    self:close()
    self.notify(value_from(self.open_error, target, context), vim.log.levels.ERROR)
    return false
  end

  self.state[self.win_key] = win
  self.ui.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    cursorline = not self.key_only,
    winhighlight = self.key_only
        and "FloatBorder:WhichKey,FloatTitle:WhichKey,Cursor:CoduxActionPaletteCursor,CursorIM:CoduxActionPaletteCursor"
      or "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  if self.key_only and vim.api and type(vim.api.nvim_set_hl) == "function" then
    pcall(vim.api.nvim_set_hl, 0, "CoduxActionPaletteCursor", { fg = "NONE", bg = "NONE", blend = 100 })
  end
  if self.key_only then
    local sink_buf, sink_win = ui.open_hidden_command_sink({
      ui = self.ui,
      filetype = "codux-actions-sink",
      enter = true,
      focusable = true,
      open_win = self.open_win,
      bind = function(target_bufnr)
        self:bind_keys(target_bufnr, target, context)
      end,
    })
    if not sink_buf then
      self:close()
      self.notify(value_from(self.open_error, target, context), vim.log.levels.ERROR)
      return false
    end
    self.state[self.sink_buf_key] = sink_buf
    self.state[self.sink_win_key] = sink_win
  else
    self:bind_keys(bufnr, target, context)
    self.set_window_cursor(win, { 1, 0 })
  end
  return true
end

return M
