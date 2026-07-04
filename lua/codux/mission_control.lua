local M = {}
M.__index = M

local action_palette_mod = require("codux.action_palette")
local dashboard_search_mod = require("codux.dashboard_search")
local mission_mod = require("codux.mission")
local ui = require("codux.ui")
local output_panel = require("codux.mission_output_panel")

local function noop() end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function available_dimension(total, margin)
  return math.max(1, total - margin)
end

local function bordered_float_outer_height(content_height)
  return math.max(1, tonumber(content_height) or 1) + 2
end

local function next_bordered_float_row(row, content_height)
  return math.max(0, tonumber(row) or 0) + bordered_float_outer_height(content_height)
end

local dashboard_command_items = {
  { key = "Tab", label = "search" },
  { key = "m", label = "menu" },
  { key = "a", label = "answer" },
  { key = "p", label = "prompt" },
  { key = "i", label = "interrupt" },
  { key = "s", label = "mode" },
}

local MISSION_ROLE_TABLE_MAX_WIDTH = 112
local MISSION_ROLE_TABLE_GAP = "  "
local MISSION_ROW_LEFT_OF_TABLE = 2

local function entry_key(entry)
  entry = type(entry) == "table" and entry or {}
  return tostring(entry.safe_name or entry.name or entry.mission_role or "")
end

local function pluralize(count, singular, plural)
  return tostring(count) .. " " .. (count == 1 and singular or plural)
end

local function center_display_line(display, text, width)
  text = tostring(text or "")
  width = tonumber(width) or 0
  local text_width = display.display_width(text)
  local padding = math.max(0, math.floor((width - text_width) / 2))
  return string.rep(" ", padding) .. text
end

local function mission_cache_key(root, mission)
  mission = type(mission) == "table" and mission or {}
  return tostring(root or "") .. "\0" .. tostring(mission.mission_id or mission.name or "")
end

local function role_cache_key(entry)
  entry = type(entry) == "table" and entry or {}
  return table.concat({
    tostring(entry.project_root or entry.worktree_path or ""),
    tostring(entry.safe_name or entry.name or entry.mission_role or ""),
    tostring(entry.worktree_branch or ""),
    tostring(entry.worktree_base or ""),
    tostring(entry.worktree_base_commit or ""),
  }, "\0")
end

local mission_control_filetypes = {
  ["codux-missions"] = true,
  ["codux-missions-search"] = true,
  ["codux-missions-command"] = true,
  ["codux-missions-commands"] = true,
  ["codux-missions-actions"] = true,
  ["codux-missions-output"] = true,
  ["codux-mission-preview"] = true,
  ["codux-mission-preview-sink"] = true,
  ["codux-mission-question-answer"] = true,
  ["codux-mission-question-answer-sink"] = true,
  ["codux-mission-question-note"] = true,
  ["codux-mission-question-option"] = true,
  ["codux-mission-objective-preview"] = true,
  ["codux-mission-objective"] = true,
  ["codux-mission-workspace-prompt"] = true,
}

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local controller = {
    state = type(opts.state) == "table" and opts.state or {},
    mission = type(opts.mission) == "table" and opts.mission or mission_mod,
    ui = type(opts.ui) == "table" and opts.ui or ui,
    workspace_ui = type(opts.workspace_ui) == "table" and opts.workspace_ui or require("codux.workspace_ui"),
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
    set_window_config = type(opts.set_window_config) == "function" and opts.set_window_config or function(win, config)
      return pcall(vim.api.nvim_win_set_config, win, config)
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
    get_window_cursor = type(opts.get_window_cursor) == "function" and opts.get_window_cursor or function(win)
      local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
      return ok and type(cursor) == "table" and cursor or nil
    end,
    set_current_win = type(opts.set_current_win) == "function" and opts.set_current_win or function(win)
      return pcall(vim.api.nvim_set_current_win, win)
    end,
    set_window_cursor = type(opts.set_window_cursor) == "function" and opts.set_window_cursor or function(win, cursor)
      return pcall(vim.api.nvim_win_set_cursor, win, cursor)
    end,
    notify = type(opts.notify) == "function" and opts.notify or noop,
    token_usage_label = type(opts.token_usage_label) == "function" and opts.token_usage_label or function()
      return ""
    end,
    refresh_token_usage = type(opts.refresh_token_usage) == "function" and opts.refresh_token_usage or noop,
    token_usage_refresh_ms = type(opts.token_usage_refresh_ms) == "function" and opts.token_usage_refresh_ms or function()
      return 60000
    end,
    token_usage_now_ms = type(opts.token_usage_now_ms) == "function" and opts.token_usage_now_ms or function()
      local loop = vim.uv or vim.loop
      if loop and type(loop.now) == "function" then
        return loop.now()
      end
      return os.time() * 1000
    end,
    create_mission = type(opts.create_mission) == "function" and opts.create_mission or noop,
    create_workspace_prompt = type(opts.create_workspace_prompt) == "function" and opts.create_workspace_prompt or noop,
    workspace_entries_for_project = type(opts.workspace_entries_for_project) == "function"
        and opts.workspace_entries_for_project
      or function()
        return {}
      end,
    edit_saved_workspace_instruction = type(opts.edit_saved_workspace_instruction) == "function"
        and opts.edit_saved_workspace_instruction
      or noop,
    delete_saved_workspace = type(opts.delete_saved_workspace) == "function" and opts.delete_saved_workspace or noop,
    close_saved_workspace_window = type(opts.close_saved_workspace_window) == "function"
        and opts.close_saved_workspace_window
      or noop,
    workspace_interactive_preview = type(opts.workspace_interactive_preview) == "function" and opts.workspace_interactive_preview
      or function()
        return nil, "workspace preview unavailable"
      end,
    close_workspace_interactive_preview = type(opts.close_workspace_interactive_preview) == "function"
        and opts.close_workspace_interactive_preview
      or noop,
    send_prompt_to_workspace = type(opts.send_prompt_to_workspace) == "function" and opts.send_prompt_to_workspace
      or function()
        return false, "workspace prompt unavailable"
      end,
    select_workspace_question_option = type(opts.select_workspace_question_option) == "function"
        and opts.select_workspace_question_option
      or function()
        return false, "workspace answer unavailable"
      end,
    submit_workspace_question_note = type(opts.submit_workspace_question_note) == "function"
        and opts.submit_workspace_question_note
      or function()
        return false, "workspace note unavailable"
      end,
    interrupt_workspace = type(opts.interrupt_workspace) == "function" and opts.interrupt_workspace or function()
      return false, "workspace interrupt unavailable"
    end,
    switch_workspace_mode = type(opts.switch_workspace_mode) == "function" and opts.switch_workspace_mode or function()
      return false, "workspace mode switch unavailable"
    end,
    update_mission_objective = type(opts.update_mission_objective) == "function"
        and opts.update_mission_objective
      or noop,
    mission_dirty_roles = type(opts.mission_dirty_roles) == "function" and opts.mission_dirty_roles or function()
      return {}
    end,
    workspace_branch_state = type(opts.workspace_branch_state) == "function" and opts.workspace_branch_state or function(entry)
      entry = type(entry) == "table" and entry or {}
      return {
        worktree = entry.workspace_kind == "worktree",
        branch = entry.worktree_branch,
        base = entry.worktree_base,
        ahead_count = 0,
        merged = false,
      }
    end,
    start_mission = type(opts.start_mission) == "function" and opts.start_mission or noop,
    close_mission = type(opts.close_mission) == "function" and opts.close_mission or noop,
    delete_mission = type(opts.delete_mission) == "function" and opts.delete_mission or noop,
    project_root = type(opts.project_root) == "function" and opts.project_root or function()
      return vim.loop.cwd()
    end,
    set_buffer_keymap = type(opts.set_buffer_keymap) == "function" and opts.set_buffer_keymap or ui.set_keymap,
    bind_close_keys = type(opts.bind_close_keys) == "function" and opts.bind_close_keys or ui.bind_close_keys,
    termopen = type(opts.termopen) == "function" and opts.termopen or function(command, term_opts)
      return vim.fn.termopen(command, term_opts)
    end,
    jobstop = type(opts.jobstop) == "function" and opts.jobstop or function(job_id)
      return vim.fn.jobstop(job_id)
    end,
    namespace = opts.namespace
      or (vim.api and vim.api.nvim_create_namespace and vim.api.nvim_create_namespace("codux.mission_control"))
      or 0,
  }

  return setmetatable(controller, M)
end

function M:action_palette_controller()
  return action_palette_mod.new({
    state = self.state,
    ui = self.ui,
    is_valid_win = self.is_valid_win,
    is_loaded_buf = self.is_loaded_buf,
    get_window_cursor = self.get_window_cursor,
    set_window_cursor = self.set_window_cursor,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
    notify = self.notify,
    namespace = self.namespace,
    win_key = "mission_dashboard_action_win",
    buf_key = "mission_dashboard_action_buf",
    sink_win_key = "mission_dashboard_action_sink_win",
    sink_buf_key = "mission_dashboard_action_sink_buf",
    items_key = "mission_dashboard_action_items",
    key_only = true,
    create_buffer_options = {
      bufhidden = "wipe",
      filetype = "codux-missions-actions",
      buftype = "nofile",
      swapfile = false,
      modifiable = false,
    },
    items = function(target, kind)
      if kind == "workspace" then
        return self.workspace_ui.role_workspace_action_items(target)
      end
      return self.workspace_ui.mission_action_items(target)
    end,
    line_for = function(item, width, target, kind)
      if kind == "workspace" then
        return self.workspace_ui.role_workspace_action_line(item, width)
      end
      return self.workspace_ui.mission_action_line(item, width)
    end,
    width = function()
      return self:action_palette_width()
    end,
    window_config = function(target, item_count, kind)
      return self:action_palette_config(target, item_count, kind)
    end,
    target = function()
      return self:action_palette_target()
    end,
    assign_open_state = function(palette, target, kind, action_items, bufnr)
      palette.state.mission_dashboard_action_buf = bufnr
      palette.state.mission_dashboard_action_items = action_items
      palette.state.mission_dashboard_action_mission = kind == "workspace" and nil or target
      palette.state.mission_dashboard_action_workspace = kind == "workspace" and target or nil
      palette.state.mission_dashboard_action_kind = kind
    end,
    clear_state = function(palette)
      palette.state.mission_dashboard_action_win = nil
      palette.state.mission_dashboard_action_buf = nil
      palette.state.mission_dashboard_action_sink_win = nil
      palette.state.mission_dashboard_action_sink_buf = nil
      palette.state.mission_dashboard_action_items = {}
      palette.state.mission_dashboard_action_mission = nil
      palette.state.mission_dashboard_action_workspace = nil
      palette.state.mission_dashboard_action_kind = nil
    end,
    action_label = function(_, kind)
      return kind == "workspace" and "Workspace" or "Mission"
    end,
    create_error = function(_, kind)
      local label = kind == "workspace" and "workspace" or "mission"
      return "Failed to create Codux " .. label .. " actions"
    end,
    open_error = function(_, kind)
      local label = kind == "workspace" and "workspace" or "mission"
      return "Failed to open Codux " .. label .. " actions"
    end,
    after_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
    end,
    run_action = function(action, target)
      return self:run_action(action, target)
    end,
  })
end

function M:dashboard_search_controller()
  return dashboard_search_mod.new({
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
      return self.state.mission_dashboard_win
    end,
    cursor_width = function()
      return self:window_width()
    end,
    window_config = function()
      return self:dashboard_search_config()
    end,
    render_owner = function()
      return self:render_dashboard()
    end,
    focus_list = function()
      return self:focus_mission_list()
    end,
    close_owner = function()
      return self:close_dashboard()
    end,
    after_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
    end,
    create_buffer_options = {
      bufhidden = "wipe",
      filetype = "codux-missions-search",
      buftype = "nofile",
      swapfile = false,
      modifiable = false,
    },
    win_key = "mission_dashboard_search_win",
    buf_key = "mission_dashboard_search_buf",
    query_key = "mission_dashboard_query",
    selected_key = "mission_dashboard_selected_row",
    best_match_key = "mission_dashboard_best_match_row",
    focus_match_key = "mission_dashboard_focus_match",
    confirmed_key = "mission_dashboard_search_confirmed",
    create_error = "Failed to create Codux mission search",
    open_error = "Failed to open Codux mission search",
    close_desc = "Close Codux Missions",
    focus_list_desc = "Focus Codux Mission List",
    select_desc = "Select Codux Mission",
    select_error = "No Codux mission selected",
    delete_desc = "Delete Codux Mission Search Character",
    clear_desc = "Clear Codux Mission Search",
    search_desc = "Search Codux Missions",
    augroup_prefix = "codux-mission-search-",
  })
end

function M:window_height()
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return nil
  end

  local height = self.get_window_height(self.state.mission_dashboard_win)
  if type(height) == "number" and height > 0 then
    return height
  end

  return nil
end

function M:window_width()
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return nil
  end

  local width = self.get_window_width(self.state.mission_dashboard_win)
  if type(width) == "number" and width > 0 then
    return width
  end

  return nil
end

function M:mission_filter_score(mission, query)
  mission = type(mission) == "table" and mission or {}
  query = tostring(query or "")
  if query == "" then
    return nil
  end

  local best = nil
  local best_kind = "mission"
  local best_entry = nil
  for _, value in ipairs({ mission.name, mission.mission_id }) do
    local score = self.workspace_ui.fuzzy_workspace_score(value, query)
    if score and (not best or score < best) then
      best = score
      best_kind = "mission"
      best_entry = nil
    end
  end

  for _, entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    for _, value in ipairs({ entry.mission_role, entry.name, entry.safe_name }) do
      local score = self.workspace_ui.fuzzy_workspace_score(value, query)
      if score and (not best or score < best) then
        best = score
        best_kind = "role"
        best_entry = entry
      end
    end
  end

  return best, best_kind, best_entry
end

function M:filter_missions(missions, query)
  missions = type(missions) == "table" and missions or {}
  query = tostring(query or "")
  if query == "" then
    return missions
  end

  local scored = {}
  for _, mission in ipairs(missions) do
    local score, match_kind, match_entry = self:mission_filter_score(mission, query)
    if score then
      table.insert(scored, {
        mission = mission,
        score = score,
        match_kind = match_kind,
        match_entry_key = match_entry and entry_key(match_entry) or nil,
      })
    end
  end

  table.sort(scored, function(left, right)
    if left.score == right.score then
      return tostring(left.mission.name or left.mission.mission_id):lower()
        < tostring(right.mission.name or right.mission.mission_id):lower()
    end
    return left.score < right.score
  end)

  local filtered = {}
  for _, item in ipairs(scored) do
    item.mission._codux_match_kind = item.match_kind
    item.mission._codux_match_entry_key = item.match_entry_key
    table.insert(filtered, item.mission)
  end
  return filtered
end

function M:objective_editor_config(line_count, opts)
  opts = type(opts) == "table" and opts or {}
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local max_width = available_dimension(total_width, 4)
  local max_height = available_dimension(total_height, 4)
  local width = math.min(max_width, math.min(96, math.max(58, math.floor(total_width * 0.72))))
  local height = math.min(max_height, math.max(10, line_count or 1))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = opts.title or " Codux Mission Objective ",
    title_pos = "center",
    footer = opts.footer or " Ctrl-s/:w preview | Ctrl-q cancel ",
    footer_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
  }
end

function M:preview_config(line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local max_width = available_dimension(total_width, 4)
  local max_height = available_dimension(total_height, 4)
  local width = math.min(max_width, math.min(92, math.max(56, math.floor(total_width * 0.68))))
  local height = math.min(max_height, math.max(12, (line_count or 1) + 1))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Codux Mission Control ",
    title_pos = "center",
    footer = " y yes | n no | e edit instruction ",
    footer_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
    focusable = false,
  }
end

function M:dashboard_workspace_preview_active(entry)
  if type(entry) ~= "table" then
    return false
  end
  local status = entry.status
  return status == "active" or status == "idle" or status == "question"
end

function M:dashboard_preview_mode(item)
  if type(item) == "table" and item.kind == "role" and self:dashboard_workspace_preview_active(item.entry) then
    return "workspace"
  end
  return "compact"
end

function M:dashboard_preview_height(total_height, command_height, mode, dashboard_min_height)
  total_height = math.max(1, tonumber(total_height) or (vim.o.lines - vim.o.cmdheight))
  command_height = math.max(0, tonumber(command_height) or 0)
  mode = mode == "workspace" and "workspace" or "compact"
  dashboard_min_height = math.max(1, tonumber(dashboard_min_height) or 1)

  if mode == "compact" then
    return 1
  end

  local target = math.min(40, math.max(14, math.floor(total_height * 0.80)))
  local reserved_gaps = (command_height > 0 and 1 or 0) + 1
  local content_capacity = available_dimension(total_height, 4)
  local preferred_available = content_capacity - command_height - reserved_gaps - dashboard_min_height
  if preferred_available >= 1 then
    return math.min(target, preferred_available)
  end

  local compact_available = content_capacity - command_height - reserved_gaps - dashboard_min_height
  return math.min(target, math.max(1, compact_available))
end

function M:dashboard_config(line_count, opts)
  opts = type(opts) == "table" and opts or {}
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local max_width = available_dimension(total_width, 4)
  local width = math.min(max_width, math.max(80, math.min(160, math.floor(total_width * 0.92))))
  local search_reserve = opts.reserve_search_input and bordered_float_outer_height(1) or 0
  local command_height = opts.reserve_command_bar and #self:dashboard_command_lines(width) or 0
  local preview_mode = opts.preview_mode or self:dashboard_preview_mode(opts.selected_item)
  local dashboard_min_height = math.max(1, tonumber(opts.dashboard_min_height) or 1)
  local preview_height = opts.reserve_output_panel
      and self:dashboard_preview_height(total_height, command_height, preview_mode, dashboard_min_height)
    or 0
  local command_reserve = command_height > 0 and bordered_float_outer_height(command_height) or 0
  local preview_reserve = preview_height > 0 and bordered_float_outer_height(preview_height) or 0
  local output_reserve = search_reserve + command_reserve + preview_reserve
  local max_height = output_reserve > 0 and math.max(dashboard_min_height, total_height - output_reserve - 2)
    or available_dimension(total_height, 4)
  local height = math.min(max_height, math.max(8, dashboard_min_height, line_count or 1))
  local stack_height = bordered_float_outer_height(height) + output_reserve
  local stack_top = math.max(0, math.floor((total_height - stack_height) / 2))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Mission Control ",
    title_pos = "center",
    footer = " Commands shown below ",
    footer_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = stack_top + search_reserve,
  }
end

function M:dashboard_search_config()
  local dashboard_config = {}
  if self.is_valid_win(self.state.mission_dashboard_win) then
    local ok, config = pcall(self.get_window_config, self.state.mission_dashboard_win)
    dashboard_config = ok and type(config) == "table" and config or {}
  end
  local width_ok, window_width = pcall(function()
    return self:window_width()
  end)
  local dashboard_width = width_ok and window_width or nil
  dashboard_width = dashboard_width or dashboard_config.width or self:dashboard_config(1).width
  local dashboard_col = type(dashboard_config.col) == "number" and dashboard_config.col or 0
  local dashboard_row = type(dashboard_config.row) == "number" and dashboard_config.row or 0
  local height = 1

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Codux mission: ",
    title_pos = "center",
    width = math.max(20, dashboard_width),
    height = height,
    col = math.max(0, dashboard_col),
    row = math.max(0, dashboard_row - bordered_float_outer_height(height)),
    zindex = 60,
  }
end

function M:dashboard_command_config(line_count)
  local dashboard_config = self.is_valid_win(self.state.mission_dashboard_win)
      and self.get_window_config(self.state.mission_dashboard_win)
    or {}
  local dashboard_width = self:window_width() or self:dashboard_config(1).width
  local dashboard_height = self:window_height() or 8
  local dashboard_col = type(dashboard_config.col) == "number"
      and dashboard_config.col
    or math.max(0, math.floor((math.max(1, vim.o.columns) - dashboard_width) / 2))
  local dashboard_row = type(dashboard_config.row) == "number" and dashboard_config.row or 0

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Commands ",
    title_pos = "center",
    width = dashboard_width,
    height = math.max(1, tonumber(line_count) or 1),
    col = math.max(0, dashboard_col),
    row = next_bordered_float_row(dashboard_row, dashboard_height),
    zindex = 54,
    focusable = false,
  }
end

function M:dashboard_output_config(line_count, opts)
  opts = type(opts) == "table" and opts or {}
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local dashboard_config = self.is_valid_win(self.state.mission_dashboard_win)
      and self.get_window_config(self.state.mission_dashboard_win)
    or {}
  local dashboard_width = self:window_width() or self:dashboard_config(1).width
  local dashboard_height = self:window_height() or 8
  local dashboard_col = type(dashboard_config.col) == "number"
      and dashboard_config.col
    or math.max(0, math.floor((math.max(1, vim.o.columns) - dashboard_width) / 2))
  local dashboard_row = type(dashboard_config.row) == "number" and dashboard_config.row or 0
  local command_config = self.is_valid_win(self.state.mission_dashboard_command_bar_win)
      and self.get_window_config(self.state.mission_dashboard_command_bar_win)
    or nil
  local command_height = self.is_valid_win(self.state.mission_dashboard_command_bar_win)
      and self.get_window_height(self.state.mission_dashboard_command_bar_win)
    or nil
  command_height = command_height or #self:dashboard_command_lines(dashboard_width)
  local row = command_config and type(command_config.row) == "number" and command_height
      and next_bordered_float_row(command_config.row, command_height)
    or next_bordered_float_row(dashboard_row, dashboard_height)
  local available_below = total_height - row - 2
  local preview_mode = opts.preview_mode or self:dashboard_preview_mode(opts.selected_item)
  local desired_height = self:dashboard_preview_height(
    total_height,
    command_height,
    preview_mode,
    opts.dashboard_min_height
  )
  local height = math.min(desired_height, math.max(1, available_below))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Output ",
    title_pos = "center",
    width = dashboard_width,
    height = height,
    col = math.max(0, dashboard_col),
    row = math.max(0, row),
    zindex = 55,
    focusable = false,
  }
end

function M:resize_dashboard_stack(line_count, opts)
  opts = type(opts) == "table" and opts or {}
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return false
  end

  local dashboard_config = self:dashboard_config(line_count, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    reserve_search_input = self.is_valid_win(self.state.mission_dashboard_search_win),
    selected_item = opts.selected_item,
    preview_mode = opts.preview_mode,
    dashboard_min_height = opts.dashboard_min_height,
  })
  local ok = self.set_window_config(self.state.mission_dashboard_win, dashboard_config)
  if not ok then
    return false
  end

  if self.is_valid_win(self.state.mission_dashboard_search_win) then
    ok = self.set_window_config(self.state.mission_dashboard_search_win, self:dashboard_search_config()) and ok
  end
  if self.is_valid_win(self.state.mission_dashboard_command_bar_win) then
    local command_lines = self:dashboard_command_lines(dashboard_config.width)
    ok = self.set_window_config(self.state.mission_dashboard_command_bar_win, self:dashboard_command_config(#command_lines))
      and ok
  end
  if self.is_valid_win(self.state.mission_dashboard_output_win) then
    ok = self.set_window_config(
      self.state.mission_dashboard_output_win,
      self:dashboard_output_config(line_count, {
        selected_item = opts.selected_item,
        preview_mode = opts.preview_mode,
        dashboard_min_height = opts.dashboard_min_height,
      })
    ) and ok
  end
  return ok
end

function M:open_objective_editor(name, default_objective, opts)
  opts = type(opts) == "table" and opts or {}
  local mission_name, name_error = self.mission.sanitize_mission_name(name)
  if not mission_name then
    self.notify(name_error, vim.log.levels.ERROR)
    return false
  end

  local bufnr = self.ui.create_scratch_buffer({
    buftype = "acwrite",
    bufhidden = "wipe",
    swapfile = false,
    filetype = "codux-mission-objective",
  })
  if not bufnr then
    self.notify("Failed to create Codux mission editor", vim.log.levels.ERROR)
    return false
  end

  pcall(vim.api.nvim_buf_set_name, bufnr, "codux://mission-objective/" .. tostring(bufnr))
  local objective_lines = vim.split(tostring(default_objective or ""), "\n", { plain = true })
  if #objective_lines == 0 then
    objective_lines = { "" }
  end
  self.ui.set_lines(bufnr, objective_lines)
  pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:objective_editor_config(#objective_lines, opts))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission editor", vim.log.levels.ERROR)
    return false
  end
  self.ui.set_window_options(win, {
    number = true,
    relativenumber = false,
    cursorline = true,
    signcolumn = "yes",
    winfixbuf = true,
    wrap = true,
    linebreak = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
  pcall(vim.cmd, "stopinsert")

  local closed = false
  local saved = false
  local autocmd_group = vim.api.nvim_create_augroup("codux-mission-objective-" .. tostring(bufnr), { clear = true })

  local function close_editor()
    closed = true
    self.ui.close_window(win)
    self.ui.delete_buffer(bufnr)
    pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
  end

  local function save_editor()
    local objective = trim(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"))
    if objective == "" then
      self.notify("Mission objective is required", vim.log.levels.WARN)
      return
    end

    if type(opts.on_save) == "function" then
      local ok = opts.on_save(mission_name, objective)
      if ok == false then
        return
      end

      saved = true
      pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
      close_editor()
      return
    end

    local mission, plan_error = self.mission.plan(mission_name, objective)
    if not mission then
      self.notify(plan_error, vim.log.levels.ERROR)
      return
    end

    saved = true
    pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
    close_editor()
    self:open_preview(mission)
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = autocmd_group,
    buffer = bufnr,
    callback = save_editor,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = autocmd_group,
    pattern = tostring(win),
    callback = function()
      if not closed and not saved then
        pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
      end
    end,
  })

  self.set_buffer_keymap(bufnr, "n", "<C-s>", save_editor, "Preview Codux Mission")
  self.set_buffer_keymap(bufnr, "i", "<C-s>", save_editor, "Preview Codux Mission")
  self.bind_close_keys(bufnr, close_editor, "Cancel Codux Mission", { "n", "i" })
  return true
end

function M:open_preview(mission)
  local preview_lines = self.mission.preview_lines(mission)
  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-mission-preview",
  })
  if not bufnr then
    self.notify("Failed to create Codux mission preview", vim.log.levels.ERROR)
    return false
  end
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })

  self.ui.set_lines(bufnr, preview_lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, self:preview_config(#preview_lines))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission preview", vim.log.levels.ERROR)
    return false
  end
  if vim.api and type(vim.api.nvim_set_hl) == "function" then
    pcall(vim.api.nvim_set_hl, 0, "CoduxMissionPreviewCursor", { fg = "NONE", bg = "NONE", blend = 100 })
  end
  self.ui.set_window_options(win, {
    wrap = true,
    linebreak = true,
    cursorline = false,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey,Cursor:CoduxMissionPreviewCursor,CursorIM:CoduxMissionPreviewCursor",
  })
  local sink_bufnr
  local sink_win
  local closed = false

  local function close_preview()
    if closed then
      return false
    end
    closed = true
    self.ui.close_window(win)
    self.ui.close_window(sink_win)
    self.ui.delete_buffer(bufnr)
    self.ui.delete_buffer(sink_bufnr)
    return true
  end

  local function defer_preview_action(action)
    local function run()
      if not close_preview() then
        return false
      end
      if type(action) == "function" then
        return action()
      end
      return true
    end

    if type(vim.schedule) == "function" then
      vim.schedule(run)
      return true
    end

    return run()
  end

  local function launch_mission()
    return defer_preview_action(function()
      if self.create_mission(mission) then
        return self:refresh_or_open_dashboard()
      end
      return false
    end)
  end

  local function edit_mission()
    return defer_preview_action(function()
      return self:open_objective_editor(mission.name, mission.objective)
    end)
  end

  local sink_error
  sink_bufnr, sink_win, sink_error = ui.open_hidden_command_sink({
    ui = self.ui,
    filetype = "codux-mission-preview-sink",
    enter = true,
    focusable = true,
    bind = function(target_bufnr)
      self.set_buffer_keymap(target_bufnr, "n", "y", launch_mission, "Launch Codux Mission", { nowait = true })
      self.set_buffer_keymap(target_bufnr, "n", "n", defer_preview_action, "Cancel Codux Mission", { nowait = true })
      self.set_buffer_keymap(target_bufnr, "n", "e", edit_mission, "Edit Codux Mission Instruction", { nowait = true })
      self.bind_close_keys(target_bufnr, defer_preview_action, "Cancel Codux Mission", "n", { escape = true, q = true })
    end,
  })
  if not sink_bufnr then
    self.ui.close_window(win)
    self.ui.delete_buffer(bufnr)
    self.notify(
      sink_error == "open" and "Failed to open Codux mission preview" or "Failed to create Codux mission preview",
      vim.log.levels.ERROR
    )
    return false
  end
  return true
end

function M:open_prompt()
  local prompt = require("codux.ui").single_line_prompt
  return prompt({ prompt = "Codux mission: " }, function(input)
    local name = trim(input)
    if name == "" then
      return
    end
    self:open_objective_editor(name)
  end, {
    notify = self.notify,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
  })
end

function M:dashboard_now(opts)
  opts = type(opts) == "table" and opts or {}
  return tonumber(opts.now) or os.time()
end

function M:cached_mission_dirty_roles(root, mission, now)
  local cache = type(self.state.mission_dashboard_dirty_cache) == "table" and self.state.mission_dashboard_dirty_cache or {}
  self.state.mission_dashboard_dirty_cache = cache
  local key = mission_cache_key(root, mission)
  local cached = cache[key]
  if type(cached) == "table" and now - (tonumber(cached.checked_at) or 0) <= 15 then
    return cached.roles, cached.error
  end

  local name = mission.name or mission.mission_id
  local roles, error_message = self.mission_dirty_roles(name, root)
  roles = type(roles) == "table" and roles or {}
  cache[key] = {
    checked_at = now,
    roles = roles,
    error = error_message,
  }
  return roles, error_message
end

function M:cached_workspace_branch_state(entry, now)
  local cache = type(self.state.mission_dashboard_branch_cache) == "table" and self.state.mission_dashboard_branch_cache or {}
  self.state.mission_dashboard_branch_cache = cache
  local key = role_cache_key(entry)
  local cached = cache[key]
  if type(cached) == "table" and now - (tonumber(cached.checked_at) or 0) <= 15 then
    return cached.state
  end

  local state = self.workspace_branch_state(entry)
  state = type(state) == "table" and state or {}
  cache[key] = {
    checked_at = now,
    state = state,
  }
  return state
end

function M:role_freshness(entry, now)
  entry = type(entry) == "table" and entry or {}
  if entry.status == "inactive" then
    return "--"
  end

  local timestamp = self.workspace_ui.activity_timestamp(entry)
  local seconds = self.workspace_ui.parse_timestamp(timestamp)
  if not seconds then
    return "stale"
  end

  local elapsed = math.max(0, now - seconds)
  if elapsed < 300 then
    return "live"
  end
  if elapsed < 1800 then
    return "quiet"
  end
  return "stale"
end

function M:mission_dirty_status_by_role(root, mission, now)
  local dirty_roles = self:cached_mission_dirty_roles(root, mission, now)
  local dirty_by_role = {}
  for _, role in ipairs(dirty_roles) do
    local label = type(role) == "table" and (role.name or role.safe_name or role.label) or role
    local reason = type(role) == "table" and role.reason or "dirty"
    dirty_by_role[tostring(label or "")] = reason
  end
  return dirty_by_role
end

function M:mission_workspace_details(entry, dirty_by_role, now)
  entry = type(entry) == "table" and entry or {}
  dirty_by_role = type(dirty_by_role) == "table" and dirty_by_role or {}
  local status = entry.status or "inactive"
  local dirty_status = dirty_by_role[tostring(entry.name or "")]
    or dirty_by_role[tostring(entry.safe_name or "")]
    or dirty_by_role[tostring(entry.mission_role or "")]
    or nil
  local branch_state = self:cached_workspace_branch_state(entry, now)
  local window_status = "not running"
  if status ~= "inactive" then
    window_status = type(entry.window_id) == "string" and entry.window_id ~= "" and "open" or "missing"
  end

  local worktree = "unknown"
  local worktree_status = "unknown"
  if entry.workspace_kind == "worktree" then
    worktree = "yes"
    worktree_status = dirty_status == "dirty" and "dirty" or dirty_status == "unknown" and "unknown" or "clean"
  elseif type(entry.workspace_kind) == "string" and entry.workspace_kind ~= "" then
    worktree = "no"
    worktree_status = "not a worktree"
  end

  local freshness = self:role_freshness(entry, now)
  local needs_review = status == "question"
    or dirty_status == "dirty"
    or dirty_status == "unknown"
    or ((status == "active" or status == "idle") and freshness == "stale")
    or (status ~= "inactive" and window_status == "missing")
    or branch_state.merged == true

  return {
    last_activity = self.workspace_ui.relative_age_label(self.workspace_ui.activity_timestamp(entry), now):gsub("^%-%-$", "unknown"),
    needs_review = needs_review and "yes" or "no",
    worktree_status = worktree_status,
    window_status = window_status,
    worktree = worktree,
    branch = entry.worktree_branch or entry.git_branch or "none",
    cleanup_status = branch_state.merged and "merged" or "not ready",
  }
end

function M:permission_profile_label(entry)
  entry = type(entry) == "table" and entry or {}
  local profile = entry.permission_profile or "default"
  if profile == "default" then
    return "Default"
  end
  if profile == "auto" then
    return "Autopilot"
  end
  if profile == "danger" then
    return "Full Access"
  end
  return tostring(profile)
end

function M:mission_mode_label(entry)
  entry = type(entry) == "table" and entry or {}
  if entry.status == "inactive" then
    return "not set"
  end
  if entry.codex_mode == "execute" then
    return "execute"
  end
  if entry.codex_mode == "plan" then
    return "plan"
  end
  return "not set"
end

function M:mission_dashboard_line(mission, counts, status, dashboard_width)
  local right = self.workspace_ui.pad_display_right(status, 8) .. "  " .. pluralize(counts.total, "role", "roles")
  local row_width = self:mission_role_table_width(dashboard_width)
  local name_width = math.min(34, math.max(16, row_width - self.workspace_ui.display_width(right) - 1))
  local mission_name = self.workspace_ui.pad_display_right(tostring(mission.name or mission.mission_id), name_width)
  local table_indent = math.max(0, math.floor(((tonumber(dashboard_width) or 0) - row_width) / 2))
  local padding = math.max(0, table_indent - MISSION_ROW_LEFT_OF_TABLE)
  return string.rep(" ", padding) .. mission_name .. " " .. right
end

function M:mission_role_header_line(dashboard_width)
  local columns = self:mission_role_column_widths(dashboard_width)
  return center_display_line(
    self.workspace_ui,
    self:mission_role_table_line(columns, {
      role = "role",
      status = "status",
      mode = "mode",
      profile = "profile",
      age = "age",
      review = "review",
      branch = "branch",
      cleanup = "cleanup",
      target = "target",
    }),
    dashboard_width
  )
end

function M:mission_role_table_width(dashboard_width)
  dashboard_width = math.max(1, tonumber(dashboard_width) or 80)
  return math.min(dashboard_width, MISSION_ROLE_TABLE_MAX_WIDTH)
end

function M:mission_role_column_widths(dashboard_width)
  local table_width = self:mission_role_table_width(dashboard_width)
  local columns = {
    role = 9,
    status = 8,
    mode = 7,
    profile = 9,
    age = 4,
    review = 6,
    cleanup = 9,
  }
  local fixed_width = columns.role
    + columns.status
    + columns.mode
    + columns.profile
    + columns.age
    + columns.review
    + columns.cleanup
    + (#MISSION_ROLE_TABLE_GAP * 8)
  local flexible_width = math.max(0, table_width - fixed_width)
  columns.branch = math.floor(flexible_width * 0.58)
  columns.target = flexible_width - columns.branch
  if flexible_width >= 12 then
    columns.branch = math.max(6, columns.branch)
    columns.target = flexible_width - columns.branch
    if columns.target < 6 then
      columns.target = 6
      columns.branch = flexible_width - columns.target
    end
  end
  return columns
end

function M:mission_role_table_line(columns, values)
  columns = type(columns) == "table" and columns or self:mission_role_column_widths(80)
  values = type(values) == "table" and values or {}
  return table.concat({
    self.workspace_ui.pad_display_right(values.role, columns.role),
    MISSION_ROLE_TABLE_GAP,
    self.workspace_ui.pad_display_right(values.status, columns.status),
    MISSION_ROLE_TABLE_GAP,
    self.workspace_ui.pad_display_right(values.mode, columns.mode),
    MISSION_ROLE_TABLE_GAP,
    self.workspace_ui.pad_display_right(values.profile, columns.profile),
    MISSION_ROLE_TABLE_GAP,
    self.workspace_ui.pad_display_right(values.age, columns.age),
    MISSION_ROLE_TABLE_GAP,
    self.workspace_ui.pad_display_right(values.review, columns.review),
    MISSION_ROLE_TABLE_GAP,
    self.workspace_ui.pad_display_right(values.branch, columns.branch),
    MISSION_ROLE_TABLE_GAP,
    self.workspace_ui.pad_display_right(values.cleanup, columns.cleanup),
    MISSION_ROLE_TABLE_GAP,
    self.workspace_ui.pad_display_right(values.target, columns.target),
  })
end

function M:mission_role_line(entry, dashboard_width, now, dirty_by_role)
  local role = entry.mission_role or entry.name or entry.safe_name
  local status = entry.status or "inactive"
  local mode = self:mission_mode_label(entry)
  local profile = self:permission_profile_label(entry)
  local details = self:mission_workspace_details(entry, dirty_by_role, now)
  local columns = self:mission_role_column_widths(dashboard_width)
  local target = type(entry.target_path) == "string" and entry.target_path ~= ""
      and vim.fn.fnamemodify(entry.target_path, ":t")
    or "none"
  return center_display_line(
    self.workspace_ui,
    self:mission_role_table_line(columns, {
      role = role,
      status = status,
      mode = mode,
      profile = profile,
      age = details.last_activity,
      review = details.needs_review,
      branch = details.branch,
      cleanup = details.cleanup_status,
      target = target,
    }),
    dashboard_width
  )
end

function M:dashboard_row_highlight_range(line)
  line = tostring(line or "")
  local start_col = line:find("%S")
  if not start_col then
    return 0, 0
  end
  return start_col - 1, #line
end

function M:dashboard_command_lines(dashboard_width)
  local width = math.max(40, tonumber(dashboard_width) or 80)
  local parts = {}
  for _, item in ipairs(dashboard_command_items) do
    table.insert(parts, item.key .. " " .. item.label)
  end
  local line = self.workspace_ui.truncate_display_tail(table.concat(parts, " "), width)
  return { center_display_line(self.workspace_ui, line, width) }
end

function M:dashboard_token_usage_line(dashboard_width)
  local usage = tostring(self.token_usage_label() or "")
  if usage == "" then
    return nil
  end
  return center_display_line(self.workspace_ui, usage, dashboard_width)
end

function M:dashboard_min_height_for_lines(lines)
  for _, line in ipairs(lines or {}) do
    if tostring(line):find("usage | ", 1, true) then
      return 2
    end
  end
  return 1
end

function M:refresh_dashboard_token_usage(force)
  local now = tonumber(self.token_usage_now_ms()) or (os.time() * 1000)
  local refresh_ms = tonumber(self.token_usage_refresh_ms()) or 60000
  refresh_ms = math.max(10000, refresh_ms)
  local last = tonumber(self.state.mission_dashboard_token_usage_refreshed_at)
  if not force and last and now - last < refresh_ms then
    return false
  end

  self.state.mission_dashboard_token_usage_refreshed_at = now
  return self.refresh_token_usage(force == true)
end

function M:missions_for_root(root)
  local entries, error_message = self.workspace_entries_for_project(root)
  if error_message then
    return nil, error_message
  end
  return self.mission.group_entries(entries)
end

function M:dashboard_lines(root, opts)
  opts = type(opts) == "table" and opts or {}
  local all_missions, error_message = self:missions_for_root(root)
  if error_message then
    return { error_message }, {}, {}
  end
  local query = tostring(opts.query or "")
  local missions = self:filter_missions(all_missions, query)
  local dashboard_width = tonumber(opts.dashboard_width) or self:window_width() or self:dashboard_config(1).width
  local now = self:dashboard_now(opts)
  local lines = {}
  local items = {}
  local selectable_rows = {}
  local best_match_row = nil
  if #all_missions == 0 then
    return { center_display_line(self.workspace_ui, "No Codux missions", dashboard_width) }, items, selectable_rows, nil, 0
  end
  if query ~= "" and #missions == 0 then
    return { center_display_line(self.workspace_ui, "No matching Codux missions", dashboard_width) },
      items,
      selectable_rows,
      nil,
      #all_missions
  end

  local total_roles = 0
  local total_active = 0
  local total_question = 0
  local total_idle = 0
  for _, mission in ipairs(missions) do
    local counts = self.mission.status_counts(mission)
    total_roles = total_roles + counts.total
    total_active = total_active + counts.active
    total_question = total_question + counts.question
    total_idle = total_idle + counts.idle
  end

  table.insert(
    lines,
    center_display_line(
      self.workspace_ui,
      string.format(
        "%s | %s | active %d | question %d | idle %d",
        pluralize(#missions, "mission", "missions"),
        pluralize(total_roles, "role", "roles"),
        total_active,
        total_question,
        total_idle
      ),
      dashboard_width
    )
  )
  local token_usage_line = self:dashboard_token_usage_line(dashboard_width)
  if token_usage_line then
    table.insert(lines, token_usage_line)
  end

  for mission_index, mission in ipairs(missions) do
    table.insert(lines, "")
    local counts = self.mission.status_counts(mission)
    local status = self.mission.status_label(mission)
    table.insert(lines, self:mission_dashboard_line(mission, counts, status, dashboard_width))
    items[#lines] = { kind = "mission", mission = mission }
    table.insert(selectable_rows, #lines)
    if query ~= "" and not best_match_row and mission._codux_match_kind == "mission" then
      best_match_row = #lines
    end
    table.insert(lines, self:mission_role_header_line(dashboard_width))
    local dirty_by_role = self:mission_dirty_status_by_role(root, mission, now)
    for _, entry in ipairs(mission.roles) do
      local line = self:mission_role_line(entry, dashboard_width, now, dirty_by_role)
      table.insert(lines, line)
      items[#lines] = { kind = "role", mission = mission, entry = entry }
      table.insert(selectable_rows, #lines)
      if
        query ~= ""
        and not best_match_row
        and mission._codux_match_kind == "role"
        and mission._codux_match_entry_key == entry_key(entry)
      then
        best_match_row = #lines
      end
    end
  end

  if query ~= "" and not best_match_row and #selectable_rows > 0 then
    best_match_row = selectable_rows[1]
  end

  return lines, items, selectable_rows, best_match_row, #all_missions
end

function M:mission_for_name(root, name)
  local missions, error_message = self:missions_for_root(root)
  if error_message then
    return nil, error_message
  end

  return self.mission.find_mission(missions, name)
end

function M:open_saved_objective_editor(name, root)
  root = root or self.project_root()
  local mission, mission_error = self:mission_for_name(root, name)
  if not mission then
    self.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  return self:open_objective_editor(mission.name, mission.objective, {
    title = " Edit Codux Mission Objective ",
    footer = " Ctrl-s/:w save | Ctrl-q cancel ",
    on_save = function(_, objective)
      return self.update_mission_objective(mission.name, objective, root)
    end,
  })
end

function M:objective_preview_config(line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local max_width = available_dimension(total_width, 4)
  local max_height = available_dimension(total_height, 4)
  local width = math.min(max_width, math.min(92, math.max(56, math.floor(total_width * 0.68))))
  local height = math.min(max_height, math.max(8, (line_count or 1) + 2))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Codux Mission Objective ",
    title_pos = "center",
    footer = " q close ",
    footer_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
    zindex = 80,
  }
end

function M:view_mission_objective(mission)
  mission = type(mission) == "table" and mission or self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end

  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-mission-objective-preview",
    modifiable = true,
  })
  if not bufnr then
    self.notify("Failed to create Codux mission objective preview", vim.log.levels.ERROR)
    return false
  end
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })

  local lines = vim.split(tostring(mission.objective or "No objective"), "\n", { plain = true })
  if #lines == 0 then
    lines = { "No objective" }
  end
  self.ui.set_lines(bufnr, lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:objective_preview_config(#lines))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission objective preview", vim.log.levels.ERROR)
    return false
  end

  self.ui.set_window_options(win, {
    wrap = true,
    linebreak = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  local function close_preview()
    self.ui.close_window(win)
    self.ui.delete_buffer(bufnr)
  end
  self.bind_close_keys(bufnr, close_preview, "Close Codux Mission Objective", "n", { escape = true, q = true })
  return true
end

function M:delete_saved_mission(name, root, opts)
  opts = type(opts) == "table" and opts or {}
  root = root or self.project_root()
  local mission, mission_error = self:mission_for_name(root, name)
  if not mission then
    self.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  if opts.confirm ~= false and not self:confirm_delete_mission(mission, root) then
    return false
  end

  local ok = self.delete_mission(mission.name or mission.mission_id, root)
  local dashboard_root = self.state.mission_dashboard_project_root or root
  if ok and dashboard_root == root and self:dashboard_is_visible() then
    self:update_dashboard_after_mission_delete(dashboard_root)
  end
  return ok
end

function M:close_saved_mission(name, root)
  root = root or self.project_root()
  local mission, mission_error = self:mission_for_name(root, name)
  if not mission then
    self.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  return self.close_mission(mission.name or mission.mission_id, root)
end

function M:confirm_delete_mission(mission, root)
  mission = type(mission) == "table" and mission or {}
  local name = mission.name or mission.mission_id
  local dirty_roles = self.mission_dirty_roles(name, root)
  dirty_roles = type(dirty_roles) == "table" and dirty_roles or {}

  local message = "Delete Codux mission " .. tostring(name) .. "?\n\n"
    .. "This will permanently remove every role workspace, Git worktree, instruction file, and branch."

  if #dirty_roles > 0 then
    local labels = {}
    for _, role in ipairs(dirty_roles) do
      local label = type(role) == "table" and (role.name or role.safe_name or role.label) or role
      local reason = type(role) == "table" and role.reason or nil
      if reason == "unknown" then
        label = tostring(label) .. " (status unknown)"
      end
      table.insert(labels, "  - " .. tostring(label))
    end
    message = message
      .. "\n\nDirty or unknown role worktrees:\n"
      .. table.concat(labels, "\n")
      .. "\n\nForce delete will nuke uncommitted and untracked work."
  end

  local choice = vim.fn.confirm(message, "&Yes\n&No", 2)
  return choice == 1
end

function M:highlight_dashboard(bufnr, lines, items)
  if vim.api and type(vim.api.nvim_set_hl) == "function" then
    pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyUsage", { fg = "#8b949e" })
  end
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, self.namespace, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", 0, 0, -1)

  for index, line in ipairs(lines) do
    local item = items[index]
    if line == "Commands" then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "WhichKeyDesc", index - 1, 0, -1)
    elseif line:find("usage | ", 1, true) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "CoduxWhichKeyUsage", index - 1, 0, -1)
    elseif line:find("^%s+Tab%s", 1, false) or line:find("^%s+O%s", 1, false) or line:find("^%s+n%s", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 0, -1)
    elseif line:find("^Output%s%s", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "WhichKeyDesc", index - 1, 0, 6)
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 6, -1)
    elseif item and item.kind == "mission" and not line:find("^%s+objective", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "WhichKey", index - 1, 0, -1)
    elseif item and item.kind == "mission" then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 0, -1)
    elseif line:find("^%s*role%s+", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Identifier", index - 1, 0, -1)
    elseif item and item.kind == "role" then
      local status = item.entry and item.entry.status or "inactive"
      local group = status == "question" and "WarningMsg"
        or status == "active" and "MoreMsg"
        or status == "idle" and "Identifier"
        or "Comment"
      local status_start = line:find(status, 1, true)
      if status_start then
        pcall(
          vim.api.nvim_buf_add_highlight,
          bufnr,
          self.namespace,
          group,
          index - 1,
          status_start - 1,
          status_start - 1 + #status
        )
      end
    end
  end

  local has_selected_row = self.state.mission_dashboard_selected_row ~= nil
  local selected_row = self.state.mission_dashboard_selected_row or self.state.mission_dashboard_best_match_row
  if selected_row then
    local group = has_selected_row and "IncSearch" or "Visual"
    local start_col, end_col = self:dashboard_row_highlight_range(lines[selected_row])
    local ok = type(vim.api.nvim_buf_set_extmark) == "function"
      and pcall(vim.api.nvim_buf_set_extmark, bufnr, self.namespace, selected_row - 1, start_col, {
        end_col = end_col,
        hl_group = group,
        hl_eol = false,
      })
    if not ok then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, group, selected_row - 1, start_col, end_col)
    end
  end
end

function M:highlight_command_bar(bufnr, lines)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, self.namespace, 0, -1)
  for index, line in ipairs(lines or {}) do
    pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 0, -1)
    local search_start = 1
    for _, item in ipairs(dashboard_command_items) do
      local key = tostring(item.key or "")
      local label = tostring(item.label or "")
      local pair = key .. " " .. label
      local pair_start = line:find(pair, search_start, true)
      if pair_start then
        local key_start = pair_start - 1
        local label_start = pair_start + #key
        pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "WhichKey", index - 1, key_start, key_start + #key)
        pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, label_start, label_start + #label)
        search_start = pair_start + #pair
      end
    end
  end
end

function M:render_command_bar()
  if not self.is_loaded_buf(self.state.mission_dashboard_command_bar_buf) then
    return false
  end
  local width = self:window_width() or self:dashboard_config(1).width
  local lines = self:dashboard_command_lines(width)
  self.ui.set_lines(self.state.mission_dashboard_command_bar_buf, lines, { modifiable = true })
  self:highlight_command_bar(self.state.mission_dashboard_command_bar_buf, lines)
  return true
end

function M:open_command_bar()
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return false
  end
  if self.is_valid_win(self.state.mission_dashboard_command_bar_win) and self.is_loaded_buf(self.state.mission_dashboard_command_bar_buf) then
    return self:render_command_bar()
  end

  local lines = self:dashboard_command_lines(self:window_width() or self:dashboard_config(1).width)
  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions-commands",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    self.notify("Failed to create Codux mission commands", vim.log.levels.ERROR)
    return false
  end
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
  self.ui.set_lines(bufnr, lines, { modifiable = true })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, self:dashboard_command_config(#lines))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission commands", vim.log.levels.ERROR)
    return false
  end

  self.state.mission_dashboard_command_bar_buf = bufnr
  self.state.mission_dashboard_command_bar_win = win
  self.ui.set_window_options(win, {
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  self:highlight_command_bar(bufnr, lines)

  local group = vim.api.nvim_create_augroup("codux-mission-commands-" .. tostring(bufnr), { clear = true })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if self.state.mission_dashboard_command_bar_buf == bufnr then
        self.state.mission_dashboard_command_bar_buf = nil
        self.state.mission_dashboard_command_bar_win = nil
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  return true
end

function M:close_command_bar()
  self.ui.close_window(self.state.mission_dashboard_command_bar_win)
  self.ui.delete_buffer(self.state.mission_dashboard_command_bar_buf)
  self.state.mission_dashboard_command_bar_win = nil
  self.state.mission_dashboard_command_bar_buf = nil
  return true
end

function M:render_dashboard()
  if not self.is_loaded_buf(self.state.mission_dashboard_buf) then
    return false
  end

  self:refresh_dashboard_token_usage(false)
  local root = self.state.mission_dashboard_project_root or self.project_root()
  local query = tostring(self.state.mission_dashboard_query or "")
  local selected = self:selected_item()
  local lines, items, selectable_rows, best_match_row = self:dashboard_lines(root, {
    query = query,
    selected_item = selected,
  })
  self.state.mission_dashboard_items = items
  self.state.mission_dashboard_selectable_rows = selectable_rows
  self.state.mission_dashboard_best_match_row = best_match_row

  local selected_item = self:selected_item()
  local dashboard_min_height = self:dashboard_min_height_for_lines(lines)
  self:resize_dashboard_stack(#lines, { selected_item = selected_item, dashboard_min_height = dashboard_min_height })
  self.ui.set_lines(self.state.mission_dashboard_buf, lines, { modifiable = true })
  self:highlight_dashboard(self.state.mission_dashboard_buf, lines, items)
  self:render_command_bar()
  self:render_output_panel(self:dashboard_output_entry(selected_item))
  self.state.mission_dashboard_focus_match = false

  return true
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

function M:selected_row()
  if self.state.mission_dashboard_selected_row then
    return self.state.mission_dashboard_selected_row
  end

  if self.state.mission_dashboard_best_match_row then
    return self.state.mission_dashboard_best_match_row
  end

  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return nil
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, self.state.mission_dashboard_win)
  return ok and cursor[1] or nil
end

function M:selected_item()
  local row = self:selected_row()
  if not row then
    return nil
  end
  return self.state.mission_dashboard_items and self.state.mission_dashboard_items[row] or nil
end

function M:selected_selectable_item()
  local row = self:selected_row()
  if not row then
    return nil
  end

  local selectable = self.state.mission_dashboard_selectable_rows or {}
  local found = false
  for _, selectable_row in ipairs(selectable) do
    if selectable_row == row then
      found = true
      break
    end
  end
  if not found then
    return nil
  end

  return self.state.mission_dashboard_items and self.state.mission_dashboard_items[row] or nil
end

function M:mission_list_focus_row()
  local rows = self.state.mission_dashboard_selectable_rows or {}
  if #rows == 0 then
    return 1
  end

  local selected = self.state.mission_dashboard_selected_row or self.state.mission_dashboard_best_match_row
  for _, row in ipairs(rows) do
    if row == selected then
      return row
    end
  end
  return rows[1]
end

function M:focus_mission_list()
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return false
  end

  self.state.mission_dashboard_focus_match = false
  if self.is_valid_win(self.state.mission_dashboard_command_win) then
    return self.set_current_win(self.state.mission_dashboard_command_win)
  end
  return self.set_current_win(self.state.mission_dashboard_win)
end

function M:focus_search_input()
  return self:dashboard_search_controller():focus()
end

function M:toggle_search_list_focus()
  return self:dashboard_search_controller():toggle_list_focus()
end

function M:move_mission_selection(delta)
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return false
  end

  local rows = self.state.mission_dashboard_selectable_rows or {}
  if #rows == 0 then
    return false
  end

  local current = self.state.mission_dashboard_selected_row
    or self.state.mission_dashboard_best_match_row
    or self:selected_row()
    or rows[1]
  local current_index = 1
  for index, row in ipairs(rows) do
    if row >= current then
      current_index = index
      break
    end
  end

  local next_index = math.max(1, math.min(#rows, current_index + (tonumber(delta) or 0)))
  local next_row = rows[next_index]
  self.state.mission_dashboard_selected_row = next_row
  self.state.mission_dashboard_search_confirmed = true
  self.state.mission_dashboard_focus_match = false
  self:render_dashboard()
  return true
end

function M:open_search_input(opts)
  return self:dashboard_search_controller():open(opts)
end

function M:lock_dashboard_mouse()
  if self.state.mission_dashboard_saved_mouse == nil then
    self.state.mission_dashboard_saved_mouse = vim.o.mouse
  end
  vim.o.mouse = ""
  return true
end

function M:restore_dashboard_mouse()
  local saved = self.state.mission_dashboard_saved_mouse
  self.state.mission_dashboard_saved_mouse = nil
  if saved ~= nil then
    vim.o.mouse = saved
  end
  return true
end

function M:close_dashboard()
  self:stop_monitor_timer()
  if self.state.mission_dashboard_resize_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self.state.mission_dashboard_resize_augroup)
    self.state.mission_dashboard_resize_augroup = nil
  end
  self:close_action_palette()
  self:close_output_panel()
  self:close_command_bar()
  self.ui.close_window(self.state.mission_dashboard_search_win)
  self.ui.close_window(self.state.mission_dashboard_command_win)
  self.ui.close_window(self.state.mission_dashboard_win)
  self.ui.delete_buffer(self.state.mission_dashboard_search_buf)
  self.ui.delete_buffer(self.state.mission_dashboard_command_bar_buf)
  self.ui.delete_buffer(self.state.mission_dashboard_command_buf)
  self.ui.delete_buffer(self.state.mission_dashboard_buf)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = self.window_buffer(win)
    if self.is_loaded_buf(bufnr) and mission_control_filetypes[self.buffer_filetype(bufnr)] then
      self.ui.close_window(win)
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if self.is_loaded_buf(bufnr) and mission_control_filetypes[self.buffer_filetype(bufnr)] then
      self.ui.delete_buffer(bufnr)
    end
  end

  self.state.mission_dashboard_buf = nil
  self.state.mission_dashboard_win = nil
  self.state.mission_dashboard_search_buf = nil
  self.state.mission_dashboard_search_win = nil
  self.state.mission_dashboard_command_buf = nil
  self.state.mission_dashboard_command_win = nil
  self.state.mission_dashboard_command_bar_buf = nil
  self.state.mission_dashboard_command_bar_win = nil
  self.state.mission_dashboard_output_buf = nil
  self.state.mission_dashboard_output_win = nil
  self.state.mission_dashboard_output_entry = nil
  self.state.mission_dashboard_output_key = nil
  self.state.mission_dashboard_output_blocked_key = nil
  self.state.mission_dashboard_output_job = nil
  self.state.mission_dashboard_output_preview = nil
  self.state.mission_dashboard_output_buf_kind = nil
  self.state.mission_dashboard_action_buf = nil
  self.state.mission_dashboard_action_win = nil
  self.state.mission_dashboard_action_items = {}
  self.state.mission_dashboard_action_mission = nil
  self.state.mission_dashboard_action_workspace = nil
  self.state.mission_dashboard_action_kind = nil
  self.state.mission_dashboard_items = {}
  self.state.mission_dashboard_selectable_rows = {}
  self.state.mission_dashboard_query = ""
  self.state.mission_dashboard_best_match_row = nil
  self.state.mission_dashboard_selected_row = nil
  self.state.mission_dashboard_focus_match = false
  self.state.mission_dashboard_search_confirmed = false
  self.state.mission_dashboard_project_root = nil
  self.state.mission_dashboard_resize_augroup = nil
  self.state.mission_dashboard_token_usage_refreshed_at = nil
  self:restore_dashboard_mouse()
  return true
end

function M:stop_monitor_timer()
  local timer = self.state.mission_dashboard_monitor_timer
  self.state.mission_dashboard_monitor_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

function M:start_monitor_timer()
  if self.state.mission_dashboard_monitor_timer then
    return true
  end

  local loop = vim.uv or vim.loop
  local timer = loop and type(loop.new_timer) == "function" and loop.new_timer() or nil
  if not timer then
    return false
  end

  self.state.mission_dashboard_monitor_timer = timer
  local function tick()
    if not self.is_valid_win(self.state.mission_dashboard_win) or not self.is_loaded_buf(self.state.mission_dashboard_buf) then
      self:stop_monitor_timer()
      return
    end
    self:render_dashboard()
  end
  local scheduled_tick = type(vim.schedule_wrap) == "function" and vim.schedule_wrap(tick) or tick
  timer:start(1000, 1000, scheduled_tick)
  return true
end

function M:open_command_sink()
  local bufnr, win = ui.open_hidden_command_sink({
    ui = self.ui,
    filetype = "codux-missions-command",
    focusable = true,
    enter = true,
    on_create_buffer = function(target_bufnr)
      ui.disable_buffer_completion(target_bufnr, { is_loaded_buf = self.is_loaded_buf })
    end,
    bind = function(target_bufnr)
      self:bind_dashboard_commands(target_bufnr)
    end,
  })
  if not bufnr then
    return false
  end

  self.state.mission_dashboard_command_buf = bufnr
  self.state.mission_dashboard_command_win = win
  return true
end

function M:selected_mission()
  local item = self:selected_item()
  return item and item.mission or nil
end

function M:selected_mission_or_notify()
  local mission = self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return nil
  end
  return mission
end

function M:close_action_palette()
  return self:action_palette_controller():close()
end

function M:action_palette_width()
  local dashboard_width = self:window_width() or 58
  return math.min(math.max(32, dashboard_width - 8), 48)
end

function M:action_palette_config(target, item_count, kind)
  local dashboard_config = self.is_valid_win(self.state.mission_dashboard_win)
      and self.get_window_config(self.state.mission_dashboard_win)
    or {}
  local dashboard_width = self:window_width() or 58
  local dashboard_height = self:window_height() or math.max(1, item_count or 1)
  local width = self:action_palette_width()
  local height = math.max(1, item_count or 1)
  local col = type(dashboard_config.col) == "number" and dashboard_config.col or math.floor((vim.o.columns - dashboard_width) / 2)
  local row = type(dashboard_config.row) == "number" and dashboard_config.row or 0
  local title = target and (target.name or target.safe_name or target.mission_role or target.mission_id) or "item"
  local prefix = kind == "workspace" and " Codux workspace: " or " Codux mission: "
  local title_width = kind == "workspace" and width - 19 or width - 17

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = prefix .. self.workspace_ui.truncate_display_tail(title, title_width) .. " ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, col + math.floor((dashboard_width - width) / 2)),
    row = math.max(0, row + math.floor((dashboard_height - height) / 2)),
    zindex = 70,
  }
end

function M:render_action_palette()
  return self:action_palette_controller():render(nil, self.state.mission_dashboard_action_kind)
end

function M:dashboard_is_visible()
  return self.is_loaded_buf(self.state.mission_dashboard_buf)
end

function M:refresh_loaded_dashboard()
  if not self:dashboard_is_visible() then
    return false
  end
  return self:render_dashboard()
end

function M:refresh_or_open_dashboard(root)
  if self:dashboard_is_visible() then
    return self:render_dashboard()
  end
  return self:open_dashboard(root)
end

function M:mission_count(root)
  local missions, error_message = self:missions_for_root(root)
  if error_message then
    return nil, error_message
  end
  return #missions
end

function M:update_dashboard_after_mission_delete(root)
  local remaining_count, error_message = self:mission_count(root)
  if error_message then
    return self:refresh_loaded_dashboard(root)
  end
  if remaining_count == 0 then
    return self:close_dashboard()
  end
  return self:refresh_loaded_dashboard(root)
end

function M:edit_selected_mission(mission)
  local root = self.state.mission_dashboard_project_root or self.project_root()
  mission = mission or self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  return self:open_objective_editor(mission.name, mission.objective, {
    title = " Edit Codux Mission Objective ",
    footer = " Ctrl-s/:w save | Ctrl-q cancel ",
    on_save = function(_, objective)
      local ok = self.update_mission_objective(mission.name, objective, root)
      if ok ~= false then
        vim.schedule(function()
          self:refresh_loaded_dashboard(root)
        end)
      end
      return ok
    end,
  })
end

function M:delete_selected_mission(mission)
  local root = self.state.mission_dashboard_project_root or self.project_root()
  mission = mission or self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  if not self:confirm_delete_mission(mission, root) then
    return false
  end
  local ok = self.delete_mission(mission.name or mission.mission_id, root)
  if ok then
    self:update_dashboard_after_mission_delete(root)
  end
  return ok
end

function M:close_selected_mission(mission)
  local root = self.state.mission_dashboard_project_root or self.project_root()
  mission = mission or self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  local ok = self.close_mission(mission.name or mission.mission_id, root)
  if ok then
    self:refresh_loaded_dashboard(root)
  end
  return ok
end

function M:start_selected_mission(mission)
  local root = self.state.mission_dashboard_project_root or self.project_root()
  mission = mission or self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  local ok = self.start_mission(mission.name or mission.mission_id, root, {
    restart_inactive = true,
    focus_first = false,
  })
  self:refresh_loaded_dashboard(root)
  return ok
end

function M:action_palette_target()
  if self.state.mission_dashboard_action_kind == "workspace" then
    return self.state.mission_dashboard_action_workspace
  end
  return self.state.mission_dashboard_action_mission
end

function M:run_workspace_action(action, target)
  local workspace = target or self.state.mission_dashboard_action_workspace
  if action == "open_workspace" then
    return false
  end
  if action == "prompt_workspace" then
    workspace = workspace or self:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    self:close_action_palette()
    return self:open_workspace_prompt(workspace)
  end
  if action == "answer_question" then
    workspace = workspace or self:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    self:close_action_palette()
    return self:open_workspace_question_answer(workspace)
  end
  if action == "edit_instructions" then
    workspace = workspace or self:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    self:close_action_palette()
    return self.edit_saved_workspace_instruction(workspace)
  end
  if action == "close_workspace" then
    workspace = workspace or self:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    self:close_action_palette()
    return self.close_saved_workspace_window(workspace)
  end
  if action == "delete_workspace" then
    workspace = workspace or self:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    self:close_action_palette()
    return self:delete_role_workspace(workspace)
  end
  if action == "create_workspace" then
    self:close_action_palette()
    return self:create_new_workspace(workspace)
  end
  return nil
end

function M:run_mission_action(action, target)
  if action == "create_mission" then
    self:close_action_palette()
    return self:create_new_mission()
  end
  local mission = target or self.state.mission_dashboard_action_mission or self:selected_mission_or_notify()
  if not mission then
    return false
  end

  if action == "edit_objective" then
    self:close_action_palette()
    return self:edit_selected_mission(mission)
  end
  if action == "view_objective" then
    self:close_action_palette()
    return self:view_mission_objective(mission)
  end
  if action == "start_mission" then
    self:close_action_palette()
    return self:start_selected_mission(mission)
  end
  if action == "close_mission" then
    self:close_action_palette()
    return self:close_selected_mission(mission)
  end
  if action == "delete_mission" then
    self:close_action_palette()
    return self:delete_selected_mission(mission)
  end
  return false
end

function M:run_action(action, target)
  local workspace_result = self:run_workspace_action(action, target)
  if workspace_result ~= nil then
    return workspace_result
  end
  return self:run_mission_action(action, target)
end

function M:run_highlighted_action()
  return self:action_palette_controller():run_highlighted()
end

function M:move_action_cursor(delta)
  return self:action_palette_controller():move_cursor(delta)
end

function M:open_action_palette_for(target, kind)
  target = type(target) == "table" and target or nil
  if not target then
    return false
  end

  return self:action_palette_controller():open(target, kind)
end

function M:selected_role_workspace_or_notify()
  local item = self:selected_selectable_item()
  if not item or item.kind ~= "role" or type(item.entry) ~= "table" then
    self.notify("No Codux workspace selected", vim.log.levels.WARN)
    return nil
  end
  return item.entry
end

function M:mission_context_for_workspace(entry)
  entry = type(entry) == "table" and entry or nil
  if not entry then
    return nil
  end

  local mission_id = entry.mission_id
  if type(mission_id) ~= "string" or mission_id == "" then
    return nil
  end

  return {
    mission_id = mission_id,
    mission_name = entry.mission_name,
    mission_objective = entry.mission_objective,
  }
end

function M:open_workspace_prompt(entry)
  entry = type(entry) == "table" and entry or self:selected_role_workspace_or_notify()
  if not entry then
    return false
  end

  local label = entry.mission_role or entry.name or entry.safe_name or "workspace"
  if entry.status == "inactive" then
    self.notify("workspace is inactive", vim.log.levels.WARN)
    return false
  end

  local prompt_fn = self.ui.single_line_prompt
  if type(prompt_fn) ~= "function" then
    self.notify("Codux prompt input is unavailable", vim.log.levels.ERROR)
    return false
  end

  return self:open_workspace_prompt_input(entry, label, self.send_prompt_to_workspace, "Sent prompt to ")
end

function M:workspace_question_pending(entry)
  entry = type(entry) == "table" and entry or {}
  return entry.status ~= "inactive"
end

function M:open_workspace_question_answer(entry)
  entry = type(entry) == "table" and entry or self:selected_role_workspace_or_notify()
  if not entry then
    return false
  end
  if entry.status == "inactive" then
    self.notify("workspace is inactive", vim.log.levels.WARN)
    return false
  end

  local label = entry.mission_role or entry.name or entry.safe_name or "workspace"
  return ui.key_choice_menu({
    title = " Answer " .. tostring(label) .. " ",
    filetype = "codux-mission-question-answer",
    zindex = 85,
    choices = {
      { key = "o", action = "option", label = "option", desc = "Send Codux Plan Option" },
      { key = "n", action = "option_note", label = "option + note", desc = "Send Codux Plan Option With Note" },
    },
    create_error = "Failed to create Codux answer menu",
    open_error = "Failed to open Codux answer menu",
    cancel_desc = "Cancel Codux Answer",
  }, function(choice)
    if type(choice) ~= "table" then
      return
    end
    if choice.action == "option_note" then
      self:open_question_option_input(entry, label, true)
      return
    end
    self:open_question_option_input(entry, label, false)
  end, {
    notify = self.notify,
    create_scratch_buffer = self.ui.create_scratch_buffer,
    set_lines = self.ui.set_lines,
    set_window_options = self.ui.set_window_options,
    close_window = self.ui.close_window,
    delete_buffer = self.ui.delete_buffer,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
  })
end

function M:open_question_option_input(entry, label, with_note)
  local prompt_fn = self.ui.single_line_prompt
  if type(prompt_fn) ~= "function" then
    self.notify("Codux prompt input is unavailable", vim.log.levels.ERROR)
    return false
  end

  label = label or (entry and (entry.mission_role or entry.name or entry.safe_name)) or "workspace"
  return prompt_fn({
    prompt = "Plan option " .. tostring(label) .. ": ",
    filetype = "codux-mission-question-option",
    zindex = 86,
    allowed_chars = "1234",
    max_length = 1,
    on_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
    end,
  }, function(input)
    local option = trim(input)
    if option == "" then
      self.notify("Option number is required", vim.log.levels.WARN)
      return
    end
    if not option:match("^[1-4]$") then
      self.notify("Option number must be 1, 2, 3, or 4", vim.log.levels.WARN)
      return
    end

    local ok, error_message = self.select_workspace_question_option(entry, option, { with_note = with_note == true })
    if not ok then
      self.notify(error_message or "Failed to answer question", vim.log.levels.ERROR)
      return
    end
    if with_note == true then
      self:open_question_note_input(entry, label)
      return
    end
    self.notify("Answered question for " .. tostring(label))
    self:render_dashboard()
  end, {
    notify = self.notify,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
  })
end

function M:open_question_note_input(entry, label)
  local prompt_fn = self.ui.single_line_prompt
  if type(prompt_fn) ~= "function" then
    self.notify("Codux prompt input is unavailable", vim.log.levels.ERROR)
    return false
  end

  label = label or (entry and (entry.mission_role or entry.name or entry.safe_name)) or "workspace"
  return prompt_fn({
    prompt = "Note " .. tostring(label) .. ": ",
    filetype = "codux-mission-question-note",
    zindex = 86,
    insert_input = true,
    on_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
    end,
  }, function(input)
    local note = trim(input)
    if note == "" then
      self.notify("Note is required", vim.log.levels.WARN)
      return
    end

    local ok, error_message = self.submit_workspace_question_note(entry, note)
    if ok then
      self.notify("Sent note to " .. tostring(label))
      self:render_dashboard()
    else
      self.notify(error_message or "Failed to send question note", vim.log.levels.ERROR)
    end
  end, {
    notify = self.notify,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
  })
end

function M:open_workspace_prompt_input(entry, label, submit_fn, success_prefix)
  entry = type(entry) == "table" and entry or nil
  label = label or (entry and (entry.mission_role or entry.name or entry.safe_name)) or "workspace"
  submit_fn = type(submit_fn) == "function" and submit_fn or self.send_prompt_to_workspace
  success_prefix = type(success_prefix) == "string" and success_prefix or "Sent prompt to "
  local prompt_fn = self.ui.single_line_prompt
  if type(prompt_fn) ~= "function" then
    self.notify("Codux prompt input is unavailable", vim.log.levels.ERROR)
    return false
  end

  return prompt_fn({
    prompt = "Prompt " .. tostring(label) .. ": ",
    filetype = "codux-mission-workspace-prompt",
    zindex = 80,
    on_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
    end,
  }, function(input)
    if input == nil then
      return
    end
    if trim(input) == "" then
      self.notify("Prompt is required", vim.log.levels.WARN)
      return
    end

    local ok, error_message = submit_fn(entry, input)
    if ok then
      self.notify(success_prefix .. tostring(label))
      self:render_dashboard()
    else
      self.notify(error_message or "Failed to send prompt", vim.log.levels.ERROR)
    end
  end, {
    notify = self.notify,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
  })
end

function M:interrupt_workspace_prompt(entry)
  entry = type(entry) == "table" and entry or self:selected_role_workspace_or_notify()
  if not entry then
    return false
  end
  if entry.status ~= "active" and entry.codex_status ~= "working" then
    return false
  end

  local ok, error_message = self.interrupt_workspace(entry)
  if not ok then
    self.notify(error_message or "Failed to interrupt workspace", vim.log.levels.ERROR)
    return false
  end

  local label = entry.mission_role or entry.name or entry.safe_name or "workspace"
  return self:open_workspace_prompt_input(entry, label, self.send_prompt_to_workspace, "Sent prompt to ")
end

function M:interrupt_selected_workspace(entry)
  entry = type(entry) == "table" and entry or self:selected_role_workspace_or_notify()
  if not entry then
    return false
  end
  return self:interrupt_workspace_prompt(entry)
end

function M:switch_selected_workspace_mode(entry)
  entry = type(entry) == "table" and entry or self:selected_role_workspace_or_notify()
  if not entry then
    return false
  end

  local ok, error_message = self.switch_workspace_mode(entry)
  if ok then
    self.notify("Switched Codux mode for " .. tostring(entry.mission_role or entry.name or entry.safe_name))
    self:render_dashboard()
    return true
  end

  self.notify(error_message or "Failed to switch workspace mode", vim.log.levels.ERROR)
  return false
end

function M:delete_role_workspace(entry)
  if type(entry) ~= "table" then
    return false
  end
  if self.workspace_ui.confirm_delete_workspace(entry) then
    return self.delete_saved_workspace(entry)
  end
  return false
end

function M:open_action_palette()
  local item = self:selected_selectable_item()
  if not item then
    self.notify("No Codux mission or workspace selected", vim.log.levels.WARN)
    return false
  end
  if item.kind == "mission" then
    return self:open_action_palette_for(item.mission, "mission")
  end
  if item.kind == "role" then
    return self:open_action_palette_for(item.entry, "workspace")
  end
  self.notify("No Codux mission or workspace selected", vim.log.levels.WARN)
  return false
end

function M:refresh_dashboard()
  self:close_dashboard()
  return self:open_dashboard()
end

function M:create_new_mission()
  return self:open_prompt()
end

function M:create_new_workspace(workspace)
  workspace = workspace or self.state.mission_dashboard_action_workspace or self:selected_role_workspace_or_notify()
  local mission_context = self:mission_context_for_workspace(workspace)
  if not mission_context then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end

  return self.create_workspace_prompt(mission_context)
end

function M:bind_dashboard_commands(bufnr)
  self.bind_close_keys(bufnr, function()
    return self:close_dashboard()
  end, "Close Codux Missions", "n", { escape = true })
  self.set_buffer_keymap(bufnr, "n", "<Tab>", function()
    return self:toggle_search_list_focus()
  end, "Search/List Codux Missions", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "j", function()
    return self:move_mission_selection(1)
  end, "Next Codux Mission", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "k", function()
    return self:move_mission_selection(-1)
  end, "Previous Codux Mission", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "m", function()
    return self:open_action_palette()
  end, "Open Codux Mission Menu")
  self.set_buffer_keymap(bufnr, "n", "a", function()
    return self:open_workspace_question_answer()
  end, "Answer Codux Mission Role Question")
  self.set_buffer_keymap(bufnr, "n", "p", function()
    return self:open_workspace_prompt()
  end, "Prompt Codux Mission Role")
  self.set_buffer_keymap(bufnr, "n", "i", function()
    return self:interrupt_selected_workspace()
  end, "Interrupt Codux Mission Role")
  self.set_buffer_keymap(bufnr, "n", "s", function()
    return self:switch_selected_workspace_mode()
  end, "Switch Codux Mission Role Mode")
end

function M:open_dashboard(root)
  self:close_dashboard()
  root = root or self.project_root()
  local lines, items, selectable_rows, best_match_row, mission_count = self:dashboard_lines(root)
  if mission_count == 0 then
    return self:open_prompt()
  end
  local initial_selected_item = items[selectable_rows[1]]
  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions",
    modifiable = false,
  })
  if not bufnr then
    self.notify("Failed to create Codux missions dashboard", vim.log.levels.ERROR)
    return false
  end
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
  self:lock_dashboard_mouse()

  self.ui.set_lines(bufnr, lines, { modifiable = true })
  self.state.mission_dashboard_buf = bufnr
  self.state.mission_dashboard_project_root = root
  self.state.mission_dashboard_items = items
  self.state.mission_dashboard_selectable_rows = selectable_rows
  self.state.mission_dashboard_best_match_row = best_match_row
  self.state.mission_dashboard_selected_row = selectable_rows[1]
  self.state.mission_dashboard_query = ""
  self.state.mission_dashboard_focus_match = false
  self.state.mission_dashboard_search_confirmed = false
  self:highlight_dashboard(bufnr, lines, items)
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, self:dashboard_config(#lines, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    reserve_search_input = true,
    selected_item = initial_selected_item,
    dashboard_min_height = self:dashboard_min_height_for_lines(lines),
  }))
  if not win_ok then
    self:restore_dashboard_mouse()
    self.ui.delete_buffer(bufnr)
    self.state.mission_dashboard_buf = nil
    self.state.mission_dashboard_project_root = nil
    self.state.mission_dashboard_items = {}
    self.state.mission_dashboard_selectable_rows = {}
    self.state.mission_dashboard_best_match_row = nil
    self.state.mission_dashboard_selected_row = nil
    self.state.mission_dashboard_query = ""
    self.state.mission_dashboard_focus_match = false
    self.state.mission_dashboard_search_confirmed = false
    self.notify("Failed to open Codux missions dashboard", vim.log.levels.ERROR)
    return false
  end
  if vim.api and type(vim.api.nvim_set_hl) == "function" then
    pcall(vim.api.nvim_set_hl, 0, "CoduxDashboardCursor", { fg = "NONE", bg = "NONE", blend = 100 })
  end
  self.ui.set_window_options(win, {
    cursorline = false,
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey,Cursor:CoduxDashboardCursor,CursorIM:CoduxDashboardCursor",
  })
  self.state.mission_dashboard_win = win
  self:refresh_dashboard_token_usage(true)
  self.state.mission_dashboard_resize_augroup = vim.api.nvim_create_augroup(
    "codux-mission-dashboard-" .. tostring(bufnr),
    { clear = true }
  )
  vim.api.nvim_create_autocmd("VimResized", {
    group = self.state.mission_dashboard_resize_augroup,
    callback = function()
      if self.is_valid_win(self.state.mission_dashboard_win) and self.is_loaded_buf(self.state.mission_dashboard_buf) then
        self:render_dashboard()
      end
    end,
  })

  self:bind_dashboard_commands(bufnr)
  self:open_command_bar()
  self:open_output_panel(self:selected_output_entry())
  self:open_command_sink()
  self:start_monitor_timer()
  vim.schedule(function()
    if self.is_valid_win(self.state.mission_dashboard_win) and self.is_loaded_buf(self.state.mission_dashboard_buf) then
      self:open_search_input({ focus = false })
    end
  end)
  return true
end

for name, method in pairs(output_panel) do
  M[name] = method
end

return M
