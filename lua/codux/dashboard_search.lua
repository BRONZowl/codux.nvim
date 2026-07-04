local M = {}
M.__index = M

local ui = require("codux.ui")

local function noop() end

local function api_function(name)
  return vim.api and type(vim.api[name]) == "function" and vim.api[name] or nil
end

local function value_from(value, ...)
  if type(value) == "function" then
    return value(...)
  end
  return value
end

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local controller = {
    state = type(opts.state) == "table" and opts.state or {},
    ui = type(opts.ui) == "table" and opts.ui or ui,
    is_valid_win = type(opts.is_valid_win) == "function" and opts.is_valid_win or ui.is_valid_win,
    is_loaded_buf = type(opts.is_loaded_buf) == "function" and opts.is_loaded_buf or ui.is_loaded_buf,
    set_current_win = type(opts.set_current_win) == "function" and opts.set_current_win or function(win)
      local set_current_win = api_function("nvim_set_current_win")
      return set_current_win and pcall(set_current_win, win) or false
    end,
    get_current_win = type(opts.get_current_win) == "function" and opts.get_current_win or function()
      local get_current_win = api_function("nvim_get_current_win")
      if not get_current_win then
        return nil
      end
      local ok, win = pcall(get_current_win)
      return ok and win or nil
    end,
    set_window_cursor = type(opts.set_window_cursor) == "function" and opts.set_window_cursor or function(win, cursor)
      local set_cursor = api_function("nvim_win_set_cursor")
      return set_cursor and pcall(set_cursor, win, cursor) or false
    end,
    set_window_config = type(opts.set_window_config) == "function" and opts.set_window_config or function(win, config)
      local set_config = api_function("nvim_win_set_config")
      return set_config and pcall(set_config, win, config) or false
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
    notify = type(opts.notify) == "function" and opts.notify or noop,
    main_win = type(opts.main_win) == "function" and opts.main_win or function()
      return nil
    end,
    cursor_width = type(opts.cursor_width) == "function" and opts.cursor_width or function()
      return 1
    end,
    window_config = type(opts.window_config) == "function" and opts.window_config or function()
      return {}
    end,
    render_owner = type(opts.render_owner) == "function" and opts.render_owner or noop,
    focus_list = type(opts.focus_list) == "function" and opts.focus_list or noop,
    close_owner = type(opts.close_owner) == "function" and opts.close_owner or noop,
    after_create_buffer = type(opts.after_create_buffer) == "function" and opts.after_create_buffer or nil,
    create_buffer_options = opts.create_buffer_options,
    win_key = opts.win_key,
    buf_key = opts.buf_key,
    query_key = opts.query_key,
    selected_key = opts.selected_key,
    best_match_key = opts.best_match_key,
    focus_match_key = opts.focus_match_key,
    confirmed_key = opts.confirmed_key,
    create_error = opts.create_error or "Failed to create Codux search",
    open_error = opts.open_error or "Failed to open Codux search",
    close_desc = opts.close_desc or "Close Codux",
    focus_list_desc = opts.focus_list_desc or "Focus Codux List",
    select_desc = opts.select_desc or "Select Codux Item",
    select_error = opts.select_error or "No Codux item selected",
    delete_desc = opts.delete_desc or "Delete Codux Search Character",
    clear_desc = opts.clear_desc or "Clear Codux Search",
    search_desc = opts.search_desc or "Search Codux",
    augroup_prefix = opts.augroup_prefix or "codux-search-",
    update_existing_config = opts.update_existing_config ~= false,
  }

  return setmetatable(controller, M)
end

function M:win()
  return self.state[self.win_key]
end

function M:buf()
  return self.state[self.buf_key]
end

function M:query()
  return tostring(self.state[self.query_key] or "")
end

function M:render()
  local bufnr = self:buf()
  if not self.is_loaded_buf(bufnr) then
    return false
  end

  local query = self:query()
  self.ui.set_lines(bufnr, { query .. " " }, { modifiable = true })

  local win = self:win()
  if self.is_valid_win(win) then
    local width = self.cursor_width() or 1
    self.set_window_cursor(win, { 1, math.min(#query, math.max(0, width - 1)) })
  end

  return true
end

function M:update_query(query)
  self.state[self.query_key] = tostring(query or "")
  self.state[self.selected_key] = nil
  self.state[self.focus_match_key] = true
  self.state[self.confirmed_key] = false
  self.render_owner()
  self:render()
  return true
end

function M:append_query(input)
  return self:update_query(self:query() .. tostring(input or ""))
end

function M:delete_query_char()
  local query = self:query()
  if query == "" then
    return true
  end

  local length = vim.fn.strchars(query)
  return self:update_query(vim.fn.strcharpart(query, 0, math.max(0, length - 1)))
end

function M:clear_query()
  if self:query() == "" then
    return true
  end

  return self:update_query("")
end

function M:focus()
  if self.is_valid_win(self:win()) then
    return self.set_current_win(self:win())
  end

  return self:open()
end

function M:toggle_list_focus()
  if self.is_valid_win(self:win()) and self.get_current_win() == self:win() then
    return self.focus_list()
  end

  return self:focus()
end

function M:select_best_match()
  local best_match = self.state[self.best_match_key]
  if not best_match then
    self.notify(self.select_error, vim.log.levels.WARN)
    return false
  end

  self.state[self.confirmed_key] = true
  self.state[self.selected_key] = best_match
  self.state[self.focus_match_key] = false
  self.render_owner()

  local main_win = self.main_win()
  if self.is_valid_win(main_win) then
    self.set_current_win(main_win)
  end
  return true
end

function M:clear_open_state(bufnr)
  if self:buf() == bufnr then
    self.state[self.buf_key] = nil
    self.state[self.win_key] = nil
  end
end

function M:bind_keys(bufnr)
  self.bind_close_keys(bufnr, function()
    return self.close_owner()
  end, self.close_desc, "n", { escape = true })
  self.set_buffer_keymap(bufnr, "n", "<Tab>", function()
    return self.focus_list()
  end, self.focus_list_desc, {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "<CR>", function()
    return self:select_best_match()
  end, self.select_desc)
  self.set_buffer_keymap(bufnr, "n", "<BS>", function()
    return self:delete_query_char()
  end, self.delete_desc, {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "<C-h>", function()
    return self:delete_query_char()
  end, self.delete_desc, {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "<C-u>", function()
    return self:clear_query()
  end, self.clear_desc, {
    nowait = true,
  })
  for _, key in ipairs(self.ui.printable_prompt_keys()) do
    local lhs = key[1]
    local input = key[2]
    self.set_buffer_keymap(bufnr, "n", lhs, function()
      return self:append_query(input)
    end, self.search_desc, {
      nowait = true,
    })
  end
end

function M:open(opts)
  opts = type(opts) == "table" and opts or {}
  local focus = opts.focus ~= false
  if not self.is_valid_win(self.main_win()) then
    return false
  end

  if self.is_valid_win(self:win()) then
    if self.update_existing_config then
      pcall(self.set_window_config, self:win(), self.window_config())
    end
    if focus then
      return self.set_current_win(self:win())
    end
    return true
  end

  local bufnr = self.ui.create_scratch_buffer(value_from(self.create_buffer_options) or {
    bufhidden = "wipe",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    self.notify(self.create_error, vim.log.levels.ERROR)
    return false
  end
  if self.after_create_buffer then
    self.after_create_buffer(bufnr)
  end

  local win_ok, win = pcall(self.open_win, bufnr, focus, self.window_config())
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify(self.open_error, vim.log.levels.ERROR)
    return false
  end

  self.state[self.buf_key] = bufnr
  self.state[self.win_key] = win
  self.ui.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  self:render()

  local create_augroup = api_function("nvim_create_augroup")
  local create_autocmd = api_function("nvim_create_autocmd")
  if create_augroup and create_autocmd then
    local group = create_augroup(self.augroup_prefix .. tostring(bufnr), { clear = true })
    create_autocmd({ "BufWipeout", "BufDelete" }, {
      group = group,
      buffer = bufnr,
      callback = function()
        self:clear_open_state(bufnr)
        local del_augroup = api_function("nvim_del_augroup_by_id")
        if del_augroup then
          pcall(del_augroup, group)
        end
      end,
    })
  end

  self:bind_keys(bufnr)
  self:render()
  return true
end

return M
