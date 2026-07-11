local M = {}
M.__index = M

local action_palette_mod = require("codux.action_palette")
local dashboard_search_mod = require("codux.dashboard_search")
local manager_actions = require("codux.workspace_manager_actions")
local manager_selection = require("codux.workspace_manager_selection")
local manager_windows = require("codux.workspace_manager_windows")
local text_util = require("codux.text")
local ui = require("codux.ui")
local util = require("codux.util")
local workspace_ui = require("codux.workspace_ui")

local noop = util.noop

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local controller = {
    state = type(opts.state) == "table" and opts.state or {},
    notify = type(opts.notify) == "function" and opts.notify or util.noop,
    trim = type(opts.trim) == "function" and opts.trim or text_util.trim,
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
    prompt_merged_workspaces = type(opts.prompt_merged_workspaces) == "function" and opts.prompt_merged_workspaces or noop,
    open_saved_workspace = type(opts.open_saved_workspace) == "function" and opts.open_saved_workspace or noop,
    start_saved_workspace = type(opts.start_saved_workspace) == "function" and opts.start_saved_workspace or noop,
    rename_saved_workspace = type(opts.rename_saved_workspace) == "function" and opts.rename_saved_workspace or noop,
    edit_saved_workspace_instruction = type(opts.edit_saved_workspace_instruction) == "function"
        and opts.edit_saved_workspace_instruction
      or noop,
    delete_saved_workspace = type(opts.delete_saved_workspace) == "function" and opts.delete_saved_workspace or noop,
    close_saved_workspace_window = type(opts.close_saved_workspace_window) == "function"
        and opts.close_saved_workspace_window
      or noop,
    select_provider_profile = type(opts.select_provider_profile) == "function" and opts.select_provider_profile or nil,
    switch_workspace_profile = type(opts.switch_workspace_profile) == "function" and opts.switch_workspace_profile or noop,
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

function M:action_palette_controller()
  if self._action_palette then
    return self._action_palette
  end

  self._action_palette = action_palette_mod.new({
    state = self.state,
    ui = self.ui,
    is_valid_win = self.is_valid_win,
    is_loaded_buf = self.is_loaded_buf,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
    notify = self.notify,
    namespace = function()
      return self:ns()
    end,
    win_key = "workspace_manager_action_win",
    buf_key = "workspace_manager_action_buf",
    items_key = "workspace_manager_action_items",
    target_key = "workspace_manager_action_workspace",
    create_buffer_options = {
      bufhidden = "wipe",
      filetype = "codux-workspaces-actions",
      buftype = "nofile",
      swapfile = false,
      modifiable = false,
    },
    items = function(item)
      return self.workspace_ui.manager_action_items(item)
    end,
    line_for = function(item, width)
      return self.workspace_ui.manager_action_line(item, width)
    end,
    width = function()
      return self:action_palette_width()
    end,
    window_config = function(item, item_count)
      return self:action_palette_config(item, item_count)
    end,
    action_label = "Workspace",
    create_error = "Failed to create Codux workspace actions",
    open_error = "Failed to open Codux workspace actions",
    run_action = function(action, item)
      return self:run_action(action, item)
    end,
  })
  return self._action_palette
end

function M:dashboard_search_controller()
  if self._search then
    return self._search
  end

  self._search = dashboard_search_mod.new({
    state = self.state,
    ui = self.ui,
    is_valid_win = self.is_valid_win,
    is_loaded_buf = self.is_loaded_buf,
    set_current_win = self.set_current_win,
    get_current_win = self.get_current_win,
    set_window_cursor = self.set_window_cursor,
    set_window_config = self.set_window_config,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
    notify = self.notify,
    main_win = function()
      return self.state.workspace_manager_win
    end,
    cursor_width = function()
      return self:window_width()
    end,
    window_config = function()
      return self:workspace_search_config()
    end,
    render_owner = function()
      return self:render()
    end,
    focus_list = function()
      return self:focus_workspace_list()
    end,
    close_owner = function()
      return self:close()
    end,
    create_buffer_options = {
      bufhidden = "wipe",
      filetype = "codux-workspaces-search",
      buftype = "nofile",
      swapfile = false,
      modifiable = false,
    },
    win_key = "workspace_manager_search_win",
    buf_key = "workspace_manager_search_buf",
    query_key = "workspace_manager_query",
    selected_key = "workspace_manager_selected_index",
    best_match_key = "workspace_manager_best_match_index",
    focus_match_key = "workspace_manager_focus_match",
    confirmed_key = "workspace_manager_search_confirmed",
    create_error = "Failed to create Codux workspace search",
    open_error = "Failed to open Codux workspace search",
    close_desc = "Close Codux Workspaces",
    focus_list_desc = "Focus Codux Workspace List",
    select_desc = "Select Codux Workspace",
    select_error = "No Codux workspace selected",
    delete_desc = "Delete Codux Workspace Search Character",
    clear_desc = "Clear Codux Workspace Search",
    search_desc = "Search Codux Workspaces",
    augroup_prefix = "codux-workspace-search-",
    update_existing_config = false,
  })
  return self._search
end

function M:stop_refresh_timer()
  return manager_windows.stop_refresh_timer(self)
end

function M:start_refresh_timer()
  return manager_windows.start_refresh_timer(self)
end

function M:max_dashboard_height()
  return manager_windows.max_dashboard_height(self)
end

function M:dashboard_height(line_count)
  return manager_windows.dashboard_height(self, line_count)
end

function M:config(line_count)
  return manager_windows.config(self, line_count)
end

function M:close()
  return manager_windows.close(self)
end

function M:window_height()
  return manager_windows.window_height(self)
end

function M:window_width()
  return manager_windows.window_width(self)
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
  return manager_windows.footer_config(self)
end

function M:position_footer()
  return manager_windows.position_footer(self)
end

function M:resize_dashboard(line_count)
  return manager_windows.resize_dashboard(self, line_count)
end

function M:render_footer()
  return manager_windows.render_footer(self)
end

function M:open_footer()
  return manager_windows.open_footer(self)
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
  return manager_selection.selected_item(self)
end

function M:render_search()
  return self:dashboard_search_controller():render()
end

function M:update_query(query)
  return self:dashboard_search_controller():update_query(query)
end

function M:append_query(input)
  return self:dashboard_search_controller():append_query(input)
end

function M:delete_query_char()
  return self:dashboard_search_controller():delete_query_char()
end

function M:clear_query()
  return self:dashboard_search_controller():clear_query()
end

function M:workspace_list_focus_row()
  return manager_selection.workspace_list_focus_row(self)
end

function M:focus_workspace_list()
  return manager_selection.focus_workspace_list(self)
end

function M:move_workspace_selection(delta)
  return manager_selection.move_workspace_selection(self, delta)
end

function M:focus_search_input()
  return self:dashboard_search_controller():focus()
end

function M:toggle_search_list_focus()
  return self:dashboard_search_controller():toggle_list_focus()
end

function M:workspace_search_config()
  local dashboard_config = vim.api.nvim_win_get_config(self.state.workspace_manager_win)
  local dashboard_width = self:window_width() or 58
  local width = math.max(20, dashboard_width)
  local col = type(dashboard_config.col) == "number" and dashboard_config.col or 0
  local row = math.max(0, (type(dashboard_config.row) == "number" and dashboard_config.row or 0) - 3)

  return {
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
  }
end

function M:open_search_input(opts)
  return self:dashboard_search_controller():open(opts)
end

function M:selected_or_notify()
  return manager_actions.selected_or_notify(self)
end

function M:close_action_palette()
  return manager_actions.close_action_palette(self)
end

function M:action_palette_width()
  return manager_actions.action_palette_width(self)
end

function M:action_palette_config(item, item_count)
  return manager_actions.action_palette_config(self, item, item_count)
end

function M:render_action_palette()
  return manager_actions.render_action_palette(self)
end

function M:run_action(action, item)
  return manager_actions.run_action(self, action, item)
end

function M:run_highlighted_action()
  return manager_actions.run_highlighted_action(self)
end

function M:move_action_cursor(delta)
  return manager_actions.move_action_cursor(self, delta)
end

function M:open_action_palette()
  return manager_actions.open_action_palette(self)
end

function M:open_selected_workspace(item)
  return manager_actions.open_selected_workspace(self, item)
end

function M:start_selected_workspace(item)
  return manager_actions.start_selected_workspace(self, item)
end

function M:rename_selected_workspace(item)
  return manager_actions.rename_selected_workspace(self, item)
end

function M:delete_selected_workspace(item)
  return manager_actions.delete_selected_workspace(self, item)
end

function M:close_selected_workspace_window(item)
  return manager_actions.close_selected_workspace_window(self, item)
end

function M:switch_selected_workspace_profile(item)
  return manager_actions.switch_selected_workspace_profile(self, item)
end

function M:close_all_workspace_windows()
  return manager_actions.close_all_workspace_windows(self)
end

function M:open_codux_menu()
  return manager_actions.open_codux_menu(self)
end

function M:bind_commands(target_bufnr)
  return manager_actions.bind_commands(self, target_bufnr)
end

function M:open_command_sink()
  return manager_windows.open_command_sink(self)
end

function M:open()
  return manager_windows.open(self)
end

return M
