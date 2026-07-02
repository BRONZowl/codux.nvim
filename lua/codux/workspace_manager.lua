local M = {}
M.__index = M

local ui = require("codux.ui")
local workspace_ui = require("codux.workspace_ui")

local function noop() end

function M.fuzzy_workspace_score(value, query)
  return workspace_ui.fuzzy_workspace_score(value, query)
end

function M.fuzzy_workspace_filter(entries, query)
  return workspace_ui.fuzzy_workspace_filter(entries, query)
end

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local controller = {
    state = type(opts.state) == "table" and opts.state or {},
    notify = type(opts.notify) == "function" and opts.notify or noop,
    trim = type(opts.trim) == "function" and opts.trim or function(value)
      return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end,
    ui = type(opts.ui) == "table" and opts.ui or ui,
    workspace_ui = type(opts.workspace_ui) == "table" and opts.workspace_ui or workspace_ui,
    is_valid_win = type(opts.is_valid_win) == "function" and opts.is_valid_win or ui.is_valid_win,
    is_loaded_buf = type(opts.is_loaded_buf) == "function" and opts.is_loaded_buf or ui.is_loaded_buf,
    window_buffer = type(opts.window_buffer) == "function" and opts.window_buffer or function()
      return nil
    end,
    buffer_filetype = type(opts.buffer_filetype) == "function" and opts.buffer_filetype or function()
      return nil
    end,
    get_window_config = type(opts.get_window_config) == "function" and opts.get_window_config or function(win)
      local ok, config = pcall(vim.api.nvim_win_get_config, win)
      return ok and type(config) == "table" and config or {}
    end,
    get_window_height = type(opts.get_window_height) == "function" and opts.get_window_height or function(win)
      local ok, height = pcall(vim.api.nvim_win_get_height, win)
      return ok and type(height) == "number" and height or nil
    end,
    get_window_width = type(opts.get_window_width) == "function" and opts.get_window_width or function(win)
      local ok, width = pcall(vim.api.nvim_win_get_width, win)
      return ok and type(width) == "number" and width or nil
    end,
    get_current_win = type(opts.get_current_win) == "function" and opts.get_current_win or function()
      local ok, win = pcall(vim.api.nvim_get_current_win)
      return ok and type(win) == "number" and win or nil
    end,
    set_current_win = type(opts.set_current_win) == "function" and opts.set_current_win or function(win)
      return pcall(vim.api.nvim_set_current_win, win)
    end,
    set_window_cursor = type(opts.set_window_cursor) == "function" and opts.set_window_cursor or function(win, cursor)
      return pcall(vim.api.nvim_win_set_cursor, win, cursor)
    end,
    set_window_config = type(opts.set_window_config) == "function" and opts.set_window_config or function(win, config)
      return pcall(vim.api.nvim_win_set_config, win, config)
    end,
    workspace_manager_max_height = type(opts.workspace_manager_max_height) == "function"
        and opts.workspace_manager_max_height
      or function()
        return nil
      end,
    workspace_entries_for_project = type(opts.workspace_entries_for_project) == "function"
        and opts.workspace_entries_for_project
      or function()
        return {}
      end,
    project_root = type(opts.project_root) == "function" and opts.project_root or function()
      return vim.loop.cwd()
    end,
    workspaces_enabled = type(opts.workspaces_enabled) == "function" and opts.workspaces_enabled or function()
      return true
    end,
    restore_workspaces = type(opts.restore_workspaces) == "function" and opts.restore_workspaces or noop,
    open_saved_workspace = type(opts.open_saved_workspace) == "function" and opts.open_saved_workspace or noop,
    rename_saved_workspace = type(opts.rename_saved_workspace) == "function" and opts.rename_saved_workspace or noop,
    edit_saved_workspace_instruction = type(opts.edit_saved_workspace_instruction) == "function"
        and opts.edit_saved_workspace_instruction
      or noop,
    delete_saved_workspace = type(opts.delete_saved_workspace) == "function" and opts.delete_saved_workspace or noop,
    close_saved_workspace_window = type(opts.close_saved_workspace_window) == "function"
        and opts.close_saved_workspace_window
      or noop,
    close_all_saved_workspace_windows = type(opts.close_all_saved_workspace_windows) == "function"
        and opts.close_all_saved_workspace_windows
      or noop,
    doctor = type(opts.doctor) == "function" and opts.doctor or noop,
    single_line_prompt = type(opts.single_line_prompt) == "function" and opts.single_line_prompt or noop,
    set_buffer_keymap = type(opts.set_buffer_keymap) == "function" and opts.set_buffer_keymap or ui.set_keymap,
    bind_close_keys = type(opts.bind_close_keys) == "function" and opts.bind_close_keys or ui.bind_close_keys,
    namespace = opts.namespace,
  }

  return setmetatable(controller, M)
end

function M:ns()
  if self.namespace then
    return self.namespace
  end
  return self.state.workspace_manager_ns
end

function M:stop_refresh_timer()
  local timer = self.state.workspace_manager_refresh_timer
  self.state.workspace_manager_refresh_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

function M:start_refresh_timer()
  if self.state.workspace_manager_refresh_timer then
    return
  end

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  self.state.workspace_manager_refresh_timer = timer
  timer:start(1000, 1000, vim.schedule_wrap(function()
    if not self.is_valid_win(self.state.workspace_manager_win) or not self.is_loaded_buf(self.state.workspace_manager_buf) then
      self:stop_refresh_timer()
      return
    end
    self:render()
  end))
end

function M:max_dashboard_height()
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local editor_max_height = math.max(1, total_height - 2)
  local codux_max_height = tonumber(self.workspace_manager_max_height())
  if codux_max_height and codux_max_height > 0 then
    return math.max(1, math.min(editor_max_height, math.floor(codux_max_height)))
  end
  return editor_max_height
end

function M:dashboard_height(line_count)
  local max_height = self:max_dashboard_height()
  local min_height = math.min(5, max_height)
  return math.min(max_height, math.max(min_height, line_count or 1))
end

function M:config(line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local max_width = math.max(1, total_width - 4)
  local width = math.min(max_width, math.max(80, math.min(88, math.floor(total_width * 0.75))))
  local height = self:dashboard_height(line_count)

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " current codux workspaces ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
  }
end

function M:close()
  self:stop_refresh_timer()

  local dashboard_filetypes = {
    ["codux-workspaces"] = true,
    ["codux-workspaces-footer"] = true,
    ["codux-workspaces-search"] = true,
    ["codux-workspaces-command"] = true,
    ["codux-workspaces-actions"] = true,
  }

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = self.window_buffer(win)
    if self.is_loaded_buf(bufnr) and dashboard_filetypes[self.buffer_filetype(bufnr)] then
      self.ui.close_window(win)
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if self.is_loaded_buf(bufnr) and dashboard_filetypes[self.buffer_filetype(bufnr)] then
      self.ui.delete_buffer(bufnr)
    end
  end

  self.state.workspace_manager_win = nil
  self.state.workspace_manager_buf = nil
  self.state.workspace_manager_footer_win = nil
  self.state.workspace_manager_footer_buf = nil
  self.state.workspace_manager_search_win = nil
  self.state.workspace_manager_search_buf = nil
  self.state.workspace_manager_command_win = nil
  self.state.workspace_manager_command_buf = nil
  self.state.workspace_manager_action_win = nil
  self.state.workspace_manager_action_buf = nil
  self.state.workspace_manager_action_items = {}
  self.state.workspace_manager_action_workspace = nil
  self.state.workspace_manager_items = {}
  self.state.workspace_manager_query = ""
  self.state.workspace_manager_best_match_index = nil
  self.state.workspace_manager_selected_index = nil
  self.state.workspace_manager_focus_match = false
  self.state.workspace_manager_search_confirmed = false
  self.state.workspace_manager_project_root = nil
end

function M:window_height()
  if not self.is_valid_win(self.state.workspace_manager_win) then
    return nil
  end

  local height = self.get_window_height(self.state.workspace_manager_win)
  if type(height) == "number" and height > 0 then
    return height
  end

  return nil
end

function M:window_width()
  if not self.is_valid_win(self.state.workspace_manager_win) then
    return nil
  end

  local width = self.get_window_width(self.state.workspace_manager_win)
  if type(width) == "number" and width > 0 then
    return width
  end

  return nil
end

function M:width_or_default()
  return self:window_width() or 58
end

function M:header_line()
  return self.workspace_ui.manager_header_line(self:width_or_default())
end

function M:manager_line(entry)
  return self.workspace_ui.manager_line(entry, self:width_or_default())
end

function M:footer_config()
  if not self.is_valid_win(self.state.workspace_manager_win) then
    return nil
  end

  local height = self:window_height() or 1
  local width = self:window_width() or 1
  return {
    relative = "win",
    win = self.state.workspace_manager_win,
    col = 0,
    row = height - 1,
    width = width,
    height = 1,
    border = "none",
    style = "minimal",
    zindex = 51,
  }
end

function M:position_footer()
  if not self.is_valid_win(self.state.workspace_manager_footer_win) then
    return false
  end
  local config = self:footer_config()
  if not config then
    return false
  end
  return self.set_window_config(self.state.workspace_manager_footer_win, config)
end

function M:resize_dashboard(line_count)
  if not self.is_valid_win(self.state.workspace_manager_win) then
    return false
  end

  local next_height = self:dashboard_height(line_count)
  if self:window_height() == next_height then
    self:position_footer()
    return true
  end

  local current = self.get_window_config(self.state.workspace_manager_win)
  local config = self:config(line_count)
  config.width = type(current.width) == "number" and current.width or config.width
  config.col = type(current.col) == "number" and current.col or config.col
  config.row = type(current.row) == "number" and current.row or config.row
  config.height = next_height

  local ok = self.set_window_config(self.state.workspace_manager_win, config)
  if ok then
    self:position_footer()
  end
  return ok
end

function M:render_footer()
  if not self.is_loaded_buf(self.state.workspace_manager_footer_buf) then
    return false
  end

  local width = self:window_width() or 1
  local segments = self.workspace_ui.manager_footer_segments({}, width)
  local line = self.workspace_ui.footer_line(segments)
  local padding = math.max(0, math.floor((width - #line) / 2))
  local text = string.rep(" ", padding) .. line
  local ns = self:ns()

  self.ui.set_lines(self.state.workspace_manager_footer_buf, { text }, { modifiable = true })
  pcall(vim.api.nvim_buf_clear_namespace, self.state.workspace_manager_footer_buf, ns, 0, -1)

  local col = padding
  for index, segment in ipairs(segments) do
    local key_end = col + #segment.key
    pcall(vim.api.nvim_buf_add_highlight, self.state.workspace_manager_footer_buf, ns, "WhichKey", 0, col, key_end)
    local desc_width = #tostring(segment.desc or "")
    local desc_end = key_end
    if desc_width > 0 then
      desc_end = key_end + 1 + desc_width
      pcall(vim.api.nvim_buf_add_highlight, self.state.workspace_manager_footer_buf, ns, "WhichKeySeparator", 0, key_end, desc_end)
    end
    col = desc_end
    if index < #segments then
      col = col + 2
    end
  end

  return true
end

function M:open_footer()
  if not self.is_valid_win(self.state.workspace_manager_win) then
    return false
  end

  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-workspaces-footer",
    modifiable = false,
  })
  if not bufnr then
    return false
  end

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, self:footer_config())
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    return false
  end

  self.state.workspace_manager_footer_buf = bufnr
  self.state.workspace_manager_footer_win = win
  self:render_footer()
  return true
end

function M:render()
  if not self.is_loaded_buf(self.state.workspace_manager_buf) then
    return false
  end

  local root = self.state.workspace_manager_project_root or self.project_root()
  local all_entries, error_message = self.workspace_entries_for_project(root)
  local query = tostring(self.state.workspace_manager_query or "")
  local entries = error_message and all_entries
    or (query ~= "" and self.workspace_ui.fuzzy_workspace_filter(all_entries, query))
    or self.workspace_ui.sort_entries(all_entries, "status_recent")
  local ns = self:ns()
  self.state.workspace_manager_items = entries
  self.state.workspace_manager_best_match_index = query ~= "" and #entries > 0 and 1 or nil

  local lines = { self:header_line() }
  if error_message then
    table.insert(lines, error_message)
  elseif #all_entries == 0 then
    table.insert(lines, "No saved Codux workspaces")
  elseif query ~= "" and #entries == 0 then
    table.insert(lines, "No matching Codux workspaces")
  else
    for _, entry in ipairs(entries) do
      table.insert(lines, self:manager_line(entry))
    end
  end

  table.insert(lines, "")
  local content_line_count = #lines
  self:resize_dashboard(content_line_count)
  local footer_line = math.max(1, self:window_height() or content_line_count)
  while #lines < footer_line do
    table.insert(lines, "")
  end

  self.ui.set_lines(self.state.workspace_manager_buf, lines, { modifiable = true })
  pcall(vim.api.nvim_buf_clear_namespace, self.state.workspace_manager_buf, ns, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, self.state.workspace_manager_buf, ns, "WhichKeyDesc", 0, 0, -1)
  local highlight_index = self.state.workspace_manager_search_confirmed and self.state.workspace_manager_selected_index
    or self.state.workspace_manager_best_match_index
  if highlight_index then
    local highlight_row = 2 + highlight_index - 1
    local match_highlight = self.state.workspace_manager_search_confirmed and "IncSearch" or "Visual"
    local full_line_ok = pcall(
      vim.api.nvim_buf_set_extmark,
      self.state.workspace_manager_buf,
      ns,
      highlight_row - 1,
      0,
      { line_hl_group = match_highlight }
    )
    if not full_line_ok then
      pcall(
        vim.api.nvim_buf_add_highlight,
        self.state.workspace_manager_buf,
        ns,
        match_highlight,
        highlight_row - 1,
        0,
        -1
      )
    end
  end
  if self.state.workspace_manager_focus_match and self.is_valid_win(self.state.workspace_manager_win) then
    local row = 1
    if #self.state.workspace_manager_items > 0 then
      row = 2 + (self.state.workspace_manager_best_match_index or 1) - 1
    end
    pcall(vim.api.nvim_win_set_cursor, self.state.workspace_manager_win, { row, 0 })
    self.state.workspace_manager_focus_match = false
  end
  self:render_footer()
  return true
end

function M:selected_item()
  if not self.is_valid_win(self.state.workspace_manager_win) then
    return nil
  end

  if self.state.workspace_manager_search_confirmed and self.state.workspace_manager_selected_index then
    return self.state.workspace_manager_items[self.state.workspace_manager_selected_index]
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, self.state.workspace_manager_win)
  if not ok then
    return nil
  end

  local index = cursor[1] - 1
  return self.state.workspace_manager_items[index]
end

function M:render_search()
  if not self.is_loaded_buf(self.state.workspace_manager_search_buf) then
    return false
  end

  local query = tostring(self.state.workspace_manager_query or "")
  self.ui.set_lines(self.state.workspace_manager_search_buf, { query .. " " }, { modifiable = true })

  if self.is_valid_win(self.state.workspace_manager_search_win) then
    local width = self:window_width() or 1
    pcall(vim.api.nvim_win_set_cursor, self.state.workspace_manager_search_win, { 1, math.min(#query, math.max(0, width - 1)) })
  end

  return true
end

function M:update_query(query)
  self.state.workspace_manager_query = tostring(query or "")
  self.state.workspace_manager_selected_index = nil
  self.state.workspace_manager_focus_match = true
  self.state.workspace_manager_search_confirmed = false
  self:render()
  self:render_search()
  return true
end

function M:append_query(input)
  return self:update_query(tostring(self.state.workspace_manager_query or "") .. tostring(input or ""))
end

function M:delete_query_char()
  local query = tostring(self.state.workspace_manager_query or "")
  if query == "" then
    return true
  end

  local length = vim.fn.strchars(query)
  return self:update_query(vim.fn.strcharpart(query, 0, math.max(0, length - 1)))
end

function M:clear_query()
  if self.state.workspace_manager_query == "" then
    return true
  end

  return self:update_query("")
end

function M:workspace_list_focus_row()
  if #self.state.workspace_manager_items == 0 then
    return 1
  end

  local index = self.state.workspace_manager_selected_index or self.state.workspace_manager_best_match_index or 1
  index = math.max(1, math.min(#self.state.workspace_manager_items, tonumber(index) or 1))
  return 2 + index - 1
end

function M:focus_workspace_list()
  if not self.is_valid_win(self.state.workspace_manager_win) then
    return false
  end

  self.state.workspace_manager_focus_match = false
  self.set_window_cursor(self.state.workspace_manager_win, { self:workspace_list_focus_row(), 0 })
  return self.set_current_win(self.state.workspace_manager_win)
end

function M:move_workspace_selection(delta)
  if not self.is_valid_win(self.state.workspace_manager_win) then
    return false
  end

  local count = #self.state.workspace_manager_items
  if count == 0 then
    return false
  end

  local current_index = self.state.workspace_manager_selected_index
    or self.state.workspace_manager_best_match_index
    or self:workspace_list_focus_row() - 1
  local next_index = math.max(1, math.min(count, (tonumber(current_index) or 1) + (tonumber(delta) or 0)))
  self.state.workspace_manager_selected_index = next_index
  self.state.workspace_manager_search_confirmed = true
  self.state.workspace_manager_focus_match = false
  self:render()
  self.set_window_cursor(self.state.workspace_manager_win, { 2 + next_index - 1, 0 })
  return true
end

function M:focus_search_input()
  if self.is_valid_win(self.state.workspace_manager_search_win) then
    return self.set_current_win(self.state.workspace_manager_search_win)
  end

  return self:open_search_input()
end

function M:toggle_search_list_focus()
  if
    self.is_valid_win(self.state.workspace_manager_search_win)
    and self.get_current_win() == self.state.workspace_manager_search_win
  then
    return self:focus_workspace_list()
  end

  return self:focus_search_input()
end

function M:open_search_input()
  if not self.is_valid_win(self.state.workspace_manager_win) then
    return false
  end

  if self.is_valid_win(self.state.workspace_manager_search_win) then
    return self.set_current_win(self.state.workspace_manager_search_win)
  end

  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-workspaces-search",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    self.notify("Failed to create Codux workspace search", vim.log.levels.ERROR)
    return false
  end

  local dashboard_config = vim.api.nvim_win_get_config(self.state.workspace_manager_win)
  local dashboard_width = self:window_width() or 58
  local width = math.max(20, dashboard_width)
  local col = type(dashboard_config.col) == "number" and dashboard_config.col or 0
  local row = math.max(0, (type(dashboard_config.row) == "number" and dashboard_config.row or 0) - 3)

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Codux workspace: ",
    title_pos = "center",
    width = width,
    height = 1,
    col = col,
    row = row,
    zindex = 60,
  })
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux workspace search", vim.log.levels.ERROR)
    return false
  end

  self.state.workspace_manager_search_buf = bufnr
  self.state.workspace_manager_search_win = win
  self.ui.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  self:render_search()

  local group = vim.api.nvim_create_augroup("codux-workspace-search-" .. tostring(bufnr), { clear = true })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if self.state.workspace_manager_search_buf == bufnr then
        self.state.workspace_manager_search_buf = nil
        self.state.workspace_manager_search_win = nil
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  self.bind_close_keys(bufnr, function()
    return self:close()
  end, "Close Codux Workspaces", "n", { escape = true })
  self.set_buffer_keymap(bufnr, "n", "<Tab>", function()
    return self:focus_workspace_list()
  end, "Focus Codux Workspace List", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "<CR>", function()
    if not self.state.workspace_manager_best_match_index then
      self.notify("No Codux workspace selected", vim.log.levels.WARN)
      return false
    end

    self.state.workspace_manager_search_confirmed = true
    self.state.workspace_manager_selected_index = self.state.workspace_manager_best_match_index
    self.state.workspace_manager_focus_match = false
    self:render()
    if self.is_valid_win(self.state.workspace_manager_command_win) then
      self.set_current_win(self.state.workspace_manager_command_win)
    elseif self.is_valid_win(self.state.workspace_manager_win) then
      self.set_current_win(self.state.workspace_manager_win)
    end
    return true
  end, "Select Codux Workspace")
  self.set_buffer_keymap(bufnr, "n", "<BS>", function()
    return self:delete_query_char()
  end, "Delete Codux Workspace Search Character", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "<C-h>", function()
    return self:delete_query_char()
  end, "Delete Codux Workspace Search Character", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "<C-u>", function()
    return self:clear_query()
  end, "Clear Codux Workspace Search", {
    nowait = true,
  })
  for _, key in ipairs(self.ui.printable_prompt_keys()) do
    local lhs = key[1]
    local input = key[2]
    self.set_buffer_keymap(bufnr, "n", lhs, function()
      return self:append_query(input)
    end, "Search Codux Workspaces", {
      nowait = true,
    })
  end

  self:render_search()
  return true
end

function M:selected_or_notify()
  local item = self:selected_item()
  if not item then
    self.notify("No Codux workspace selected", vim.log.levels.WARN)
    return nil
  end
  return item
end

function M:close_action_palette()
  self.ui.close_window(self.state.workspace_manager_action_win)
  self.ui.delete_buffer(self.state.workspace_manager_action_buf)
  self.state.workspace_manager_action_win = nil
  self.state.workspace_manager_action_buf = nil
  self.state.workspace_manager_action_items = {}
  self.state.workspace_manager_action_workspace = nil
  return true
end

function M:action_palette_width()
  local dashboard_width = self:window_width() or 58
  return math.min(math.max(32, dashboard_width - 8), 48)
end

function M:action_palette_config(item, item_count)
  local dashboard_config = self.is_valid_win(self.state.workspace_manager_win)
      and vim.api.nvim_win_get_config(self.state.workspace_manager_win)
    or {}
  local dashboard_width = self:window_width() or 58
  local dashboard_height = self:window_height() or math.max(1, item_count or 1)
  local width = self:action_palette_width()
  local height = math.max(1, item_count or 1)
  local col = type(dashboard_config.col) == "number" and dashboard_config.col or math.floor((vim.o.columns - dashboard_width) / 2)
  local row = type(dashboard_config.row) == "number" and dashboard_config.row or 0

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Codux actions: " .. self.workspace_ui.truncate_display_tail(item and item.name or "workspace", width - 16) .. " ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, col + math.floor((dashboard_width - width) / 2)),
    row = math.max(0, row + math.floor((dashboard_height - height) / 2)),
    zindex = 70,
  }
end

function M:render_action_palette()
  if not self.is_loaded_buf(self.state.workspace_manager_action_buf) then
    return false
  end

  local width = self:action_palette_width()
  local lines = {}
  for _, item in ipairs(self.state.workspace_manager_action_items or {}) do
    table.insert(lines, self.workspace_ui.manager_action_line(item, width))
  end

  self.ui.set_lines(self.state.workspace_manager_action_buf, lines, { modifiable = true })
  return true
end

function M:run_action(action, item)
  item = item or self.state.workspace_manager_action_workspace or self:selected_or_notify()
  if not item then
    return false
  end

  if action == "rename" then
    self:close_action_palette()
    return self:rename_selected_workspace(item)
  end
  if action == "edit_instructions" then
    self:close_action_palette()
    return self.edit_saved_workspace_instruction(item)
  end
  if action == "close_window" then
    self:close_action_palette()
    return self.close_saved_workspace_window(item)
  end
  if action == "close_all_windows" then
    self:close_action_palette()
    return self:close_all_workspace_windows()
  end
  if action == "delete" then
    self:close_action_palette()
    return self:delete_selected_workspace(item)
  end
  return false
end

function M:run_highlighted_action()
  if not self.is_valid_win(self.state.workspace_manager_action_win) then
    return false
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, self.state.workspace_manager_action_win)
  if not ok then
    return false
  end

  local action_item = self.state.workspace_manager_action_items[cursor[1]]
  if not action_item then
    return false
  end
  return self:run_action(action_item.action, self.state.workspace_manager_action_workspace)
end

function M:move_action_cursor(delta)
  if not self.is_valid_win(self.state.workspace_manager_action_win) then
    return false
  end

  local count = #self.state.workspace_manager_action_items
  if count == 0 then
    return false
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, self.state.workspace_manager_action_win)
  if not ok then
    return false
  end
  local row = ((cursor[1] - 1 + delta) % count) + 1
  pcall(vim.api.nvim_win_set_cursor, self.state.workspace_manager_action_win, { row, 0 })
  return true
end

function M:open_action_palette()
  local item = self:selected_or_notify()
  if not item then
    return false
  end

  self:close_action_palette()
  local action_items = self.workspace_ui.manager_action_items(item)
  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-workspaces-actions",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    self.notify("Failed to create Codux workspace actions", vim.log.levels.ERROR)
    return false
  end

  self.state.workspace_manager_action_buf = bufnr
  self.state.workspace_manager_action_items = action_items
  self.state.workspace_manager_action_workspace = item
  self:render_action_palette()

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:action_palette_config(item, #action_items))
  if not win_ok then
    self:close_action_palette()
    self.notify("Failed to open Codux workspace actions", vim.log.levels.ERROR)
    return false
  end

  self.state.workspace_manager_action_win = win
  self.ui.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    cursorline = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })

  self.bind_close_keys(bufnr, function()
    return self:close_action_palette()
  end, "Close Codux Workspace Actions", "n", { escape = true, q = true })
  self.set_buffer_keymap(bufnr, "n", "<CR>", function()
    return self:run_highlighted_action()
  end, "Run Codux Workspace Action")
  self.set_buffer_keymap(bufnr, "n", "j", function()
    return self:move_action_cursor(1)
  end, "Next Codux Workspace Action", { nowait = true })
  self.set_buffer_keymap(bufnr, "n", "<Down>", function()
    return self:move_action_cursor(1)
  end, "Next Codux Workspace Action", { nowait = true })
  self.set_buffer_keymap(bufnr, "n", "k", function()
    return self:move_action_cursor(-1)
  end, "Previous Codux Workspace Action", { nowait = true })
  self.set_buffer_keymap(bufnr, "n", "<Up>", function()
    return self:move_action_cursor(-1)
  end, "Previous Codux Workspace Action", { nowait = true })

  for _, action_item in ipairs(action_items) do
    local bound_action = action_item.action
    local bound_label = action_item.label
    self.set_buffer_keymap(bufnr, "n", action_item.key, function()
      return self:run_action(bound_action, item)
    end, bound_label .. " Codux Workspace", { nowait = true })
  end

  pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
  return true
end

function M:open_selected_workspace(item)
  item = item or self:selected_or_notify()
  if not item then
    return false
  end
  local root = self.state.workspace_manager_project_root
  self:close()
  return self.open_saved_workspace(item.name, root)
end

function M:rename_selected_workspace(item)
  item = item or self:selected_or_notify()
  if not item then
    return false
  end
  self.single_line_prompt({ prompt = "Rename Codux workspace: ", default = item.name }, function(input)
    local new_name = self.trim(input)
    if new_name == "" then
      return
    end
    self.rename_saved_workspace(item, new_name)
  end)
end

function M:delete_selected_workspace(item)
  item = item or self:selected_or_notify()
  if not item then
    return false
  end
  local choice = vim.fn.confirm("Delete Codux workspace " .. item.name .. "?", "&Yes\n&No", 2)
  if choice == 1 then
    self.delete_saved_workspace(item)
  end
end

function M:close_selected_workspace_window(item)
  item = item or self:selected_or_notify()
  if not item then
    return false
  end
  return self.close_saved_workspace_window(item)
end

function M:close_all_workspace_windows()
  local root = self.state.workspace_manager_project_root or self.project_root()
  local choice = vim.fn.confirm("Close all Codux workspaces for this project?", "&Yes\n&No", 2)
  if choice ~= 1 then
    return false
  end
  return self.close_all_saved_workspace_windows(root)
end

function M:open_codux_menu()
  self:close()
  vim.schedule(function()
    local leader = tostring(vim.g.mapleader or "\\")
    local keys = vim.api.nvim_replace_termcodes(leader .. "z", true, false, true)
    vim.api.nvim_feedkeys(keys, "m", false)
  end)
end

function M:bind_commands(target_bufnr)
  self.bind_close_keys(target_bufnr, function()
    return self:close()
  end, "Close Codux Workspaces", "n", { escape = true, q = true })
  self.set_buffer_keymap(target_bufnr, "n", "<leader>z", function()
    return self:open_codux_menu()
  end, "Open Codux Menu", {
    nowait = true,
  })
  self.set_buffer_keymap(target_bufnr, "n", "<Tab>", function()
    return self:toggle_search_list_focus()
  end, "Search/List Codux Workspaces", {
    nowait = true,
  })
  self.set_buffer_keymap(target_bufnr, "n", "m", function()
    return self:open_action_palette()
  end, "Open Codux Workspace Menu")
  self.set_buffer_keymap(target_bufnr, "n", "h", function()
    return self.doctor()
  end, "Run Codux Doctor")
  self.set_buffer_keymap(target_bufnr, "n", "j", function()
    return self:move_workspace_selection(1)
  end, "Next Codux Workspace", {
    nowait = true,
  })
  self.set_buffer_keymap(target_bufnr, "n", "k", function()
    return self:move_workspace_selection(-1)
  end, "Previous Codux Workspace", {
    nowait = true,
  })
  self.set_buffer_keymap(target_bufnr, "n", "<CR>", function()
    return self:open_selected_workspace()
  end, "Open Codux Workspace")
end

function M:open_command_sink()
  local sink_bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-workspaces-command",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not sink_bufnr then
    return false
  end

  local sink_win_ok, sink_win = pcall(vim.api.nvim_open_win, sink_bufnr, false, {
    relative = "editor",
    style = "minimal",
    border = "none",
    width = 1,
    height = 1,
    col = vim.o.columns + 1,
    row = vim.o.lines + 1,
    zindex = 1,
  })
  if not sink_win_ok then
    self.ui.delete_buffer(sink_bufnr)
    return false
  end

  self.state.workspace_manager_command_buf = sink_bufnr
  self.state.workspace_manager_command_win = sink_win
  self.ui.set_window_options(sink_win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
  })
  self:bind_commands(sink_bufnr)
  return true
end

function M:open()
  if not self.workspaces_enabled() then
    self.notify("Codux workspaces are disabled", vim.log.levels.ERROR)
    return false
  end

  self:close()
  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-workspaces",
    modifiable = false,
  })
  if not bufnr then
    self.notify("Failed to create Codux workspaces window", vim.log.levels.ERROR)
    return false
  end

  self.state.workspace_manager_buf = bufnr
  self.state.workspace_manager_project_root = self.project_root()
  self.restore_workspaces({ project_root = self.state.workspace_manager_project_root, silent = true })
  local preview_entries = self.workspace_entries_for_project(self.state.workspace_manager_project_root)
  local line_count = 1 + math.max(1, #preview_entries) + 1

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:config(line_count))
  if not win_ok then
    self.state.workspace_manager_buf = nil
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux workspaces window", vim.log.levels.ERROR)
    return false
  end

  self.state.workspace_manager_win = win
  self.ui.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    cursorline = true,
  })
  self:open_footer()
  self:bind_commands(bufnr)
  self:open_command_sink()

  self:render()
  self:start_refresh_timer()
  if #self.state.workspace_manager_items > 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { 2, 0 })
  end
  vim.schedule(function()
    if self.is_valid_win(self.state.workspace_manager_win) and self.is_loaded_buf(self.state.workspace_manager_buf) then
      self:open_search_input()
    end
  end)
  return true
end

return M
