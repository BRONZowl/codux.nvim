local M = {}
M.__index = M

local action_palette_mod = require("codux.action_palette")
local dashboard_actions = require("codux.mission_dashboard_actions")
local dashboard_layout = require("codux.mission_dashboard_layout")
local dashboard_render = require("codux.mission_dashboard_render")
local dashboard_search_mod = require("codux.dashboard_search")
local filetypes = require("codux.filetypes")
local mission_dashboard = require("codux.mission_dashboard")
local mission_mod = require("codux.mission")
local text_util = require("codux.text")
local ui = require("codux.ui")
local output_panel = require("codux.mission_output_panel")

local function noop() end

local function trim(value)
  return text_util.trim(value)
end

local dashboard_command_items = mission_dashboard.command_items()

local mission_control_filetypes = filetypes.mission_control

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
  return dashboard_layout.window_height(self)
end

function M:window_width()
  return dashboard_layout.window_width(self)
end

function M:mission_filter_score(mission, query)
  return dashboard_render.mission_filter_score(self, mission, query)
end

function M:filter_missions(missions, query)
  return dashboard_render.filter_missions(self, missions, query)
end

function M:objective_editor_config(line_count, opts)
  return dashboard_layout.objective_editor_config(self, line_count, opts)
end

function M:preview_config(line_count)
  return dashboard_layout.preview_config(self, line_count)
end

function M:dashboard_workspace_preview_active(entry)
  return dashboard_layout.dashboard_workspace_preview_active(self, entry)
end

function M:dashboard_preview_mode(item)
  return dashboard_layout.dashboard_preview_mode(self, item)
end

function M:dashboard_preview_height(total_height, command_height, mode, dashboard_min_height)
  return dashboard_layout.dashboard_preview_height(self, total_height, command_height, mode, dashboard_min_height)
end

function M:dashboard_config(line_count, opts)
  return dashboard_layout.dashboard_config(self, line_count, opts)
end

function M:dashboard_search_config()
  return dashboard_layout.dashboard_search_config(self)
end

function M:dashboard_command_config(line_count)
  return dashboard_layout.dashboard_command_config(self, line_count)
end

function M:dashboard_output_config(line_count, opts)
  return dashboard_layout.dashboard_output_config(self, line_count, opts)
end

function M:resize_dashboard_stack(line_count, opts)
  return dashboard_layout.resize_dashboard_stack(self, line_count, opts)
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
  local initial_preview_lines = self.mission.preview_lines(mission)
  local initial_config = self:preview_config(#initial_preview_lines)
  local preview_lines = self.mission.preview_lines(mission, {
    max_width = initial_config.width,
    max_lines = initial_config.height,
  })
  local preview_config = self:preview_config(#preview_lines)
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

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, preview_config)
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission preview", vim.log.levels.ERROR)
    return false
  end
  if vim.api and type(vim.api.nvim_set_hl) == "function" then
    pcall(vim.api.nvim_set_hl, 0, "CoduxMissionPreviewCursor", { fg = "NONE", bg = "NONE", blend = 100 })
  end
  self.ui.set_window_options(win, {
    wrap = false,
    linebreak = false,
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
  return prompt({ prompt = "Codux mission: ", zindex = 80 }, function(input)
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
  return dashboard_render.dashboard_now(self, opts)
end

function M:cached_mission_dirty_roles(root, mission, now)
  return dashboard_render.cached_mission_dirty_roles(self, root, mission, now)
end

function M:cached_workspace_branch_state(entry, now)
  return dashboard_render.cached_workspace_branch_state(self, entry, now)
end

function M:role_freshness(entry, now)
  return dashboard_render.role_freshness(self, entry, now)
end

function M:mission_dirty_status_by_role(root, mission, now)
  return dashboard_render.mission_dirty_status_by_role(self, root, mission, now)
end

function M:mission_workspace_details(entry, dirty_by_role, now)
  return dashboard_render.mission_workspace_details(self, entry, dirty_by_role, now)
end

function M:permission_profile_label(entry)
  return dashboard_render.permission_profile_label(self, entry)
end

function M:mission_mode_label(entry)
  return dashboard_render.mission_mode_label(self, entry)
end

function M:mission_dashboard_line(mission, counts, status, dashboard_width)
  return dashboard_render.mission_dashboard_line(self, mission, counts, status, dashboard_width)
end

function M:mission_role_header_line(dashboard_width)
  return dashboard_render.mission_role_header_line(self, dashboard_width)
end

function M:mission_role_table_width(dashboard_width)
  return dashboard_render.mission_role_table_width(self, dashboard_width)
end

function M:mission_role_column_widths(dashboard_width)
  return dashboard_render.mission_role_column_widths(self, dashboard_width)
end

function M:mission_role_table_line(columns, values)
  return dashboard_render.mission_role_table_line(self, columns, values)
end

function M:mission_role_line(entry, dashboard_width, now, dirty_by_role)
  return dashboard_render.mission_role_line(self, entry, dashboard_width, now, dirty_by_role)
end

function M:dashboard_row_highlight_range(line)
  return dashboard_render.dashboard_row_highlight_range(self, line)
end

function M:dashboard_command_lines(dashboard_width)
  return dashboard_render.dashboard_command_lines(self, dashboard_width)
end

function M:dashboard_token_usage_line(dashboard_width)
  return dashboard_render.dashboard_token_usage_line(self, dashboard_width)
end

function M:dashboard_min_height_for_lines(lines)
  return dashboard_render.dashboard_min_height_for_lines(self, lines)
end

function M:refresh_dashboard_token_usage(force)
  return dashboard_render.refresh_dashboard_token_usage(self, force)
end

function M:missions_for_root(root)
  return dashboard_render.missions_for_root(self, root)
end

function M:dashboard_lines(root, opts)
  return dashboard_render.dashboard_lines(self, root, opts)
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
  return dashboard_layout.objective_preview_config(self, line_count)
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
  return mission_dashboard.highlight(self, bufnr, lines, items)
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
  return dashboard_actions.selected_mission(self)
end

function M:selected_mission_or_notify()
  return dashboard_actions.selected_mission_or_notify(self)
end

function M:close_action_palette()
  return dashboard_actions.close_action_palette(self)
end

function M:action_palette_width()
  return dashboard_actions.action_palette_width(self)
end

function M:action_palette_config(target, item_count, kind)
  return dashboard_actions.action_palette_config(self, target, item_count, kind)
end

function M:render_action_palette()
  return dashboard_actions.render_action_palette(self)
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
  return dashboard_actions.edit_selected_mission(self, mission)
end

function M:delete_selected_mission(mission)
  return dashboard_actions.delete_selected_mission(self, mission)
end

function M:close_selected_mission(mission)
  return dashboard_actions.close_selected_mission(self, mission)
end

function M:start_selected_mission(mission)
  return dashboard_actions.start_selected_mission(self, mission)
end

function M:action_palette_target()
  return dashboard_actions.action_palette_target(self)
end

function M:run_workspace_action(action, target)
  return dashboard_actions.run_workspace_action(self, action, target)
end

function M:run_mission_action(action, target)
  return dashboard_actions.run_mission_action(self, action, target)
end

function M:run_action(action, target)
  return dashboard_actions.run_action(self, action, target)
end

function M:run_highlighted_action()
  return dashboard_actions.run_highlighted_action(self)
end

function M:move_action_cursor(delta)
  return dashboard_actions.move_action_cursor(self, delta)
end

function M:open_action_palette_for(target, kind)
  return dashboard_actions.open_action_palette_for(self, target, kind)
end

function M:selected_role_workspace_or_notify()
  return dashboard_actions.selected_role_workspace_or_notify(self)
end

function M:mission_context_for_workspace(entry)
  return dashboard_actions.mission_context_for_workspace(self, entry)
end

function M:open_workspace_prompt(entry)
  return dashboard_actions.open_workspace_prompt(self, entry)
end

function M:workspace_question_pending(entry)
  return dashboard_actions.workspace_question_pending(self, entry)
end

function M:open_workspace_question_answer(entry)
  return dashboard_actions.open_workspace_question_answer(self, entry)
end

function M:open_question_option_input(entry, label, with_note)
  return dashboard_actions.open_question_option_input(self, entry, label, with_note)
end

function M:open_question_note_input(entry, label)
  return dashboard_actions.open_question_note_input(self, entry, label)
end

function M:open_workspace_prompt_input(entry, label, submit_fn, success_prefix)
  return dashboard_actions.open_workspace_prompt_input(self, entry, label, submit_fn, success_prefix)
end

function M:interrupt_workspace_action(entry)
  return dashboard_actions.interrupt_workspace_action(self, entry)
end

function M:interrupt_selected_workspace(entry)
  return dashboard_actions.interrupt_selected_workspace(self, entry)
end

function M:switch_selected_workspace_mode(entry)
  return dashboard_actions.switch_selected_workspace_mode(self, entry)
end

function M:delete_role_workspace(entry)
  return dashboard_actions.delete_role_workspace(self, entry)
end

function M:open_action_palette()
  return dashboard_actions.open_action_palette(self)
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
