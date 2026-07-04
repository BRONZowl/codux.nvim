local M = {}
M.__index = M

local mission_mod = require("codux.mission")
local ui = require("codux.ui")

local function noop() end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function command_display(command)
  if type(command) == "table" then
    local parts = {}
    for _, part in ipairs(command) do
      table.insert(parts, tostring(part))
    end
    return table.concat(parts, " ")
  end
  return tostring(command or "")
end

local function preview_attach_error(command, detail)
  local message = "failed to attach workspace session preview"
  detail = tostring(detail or "")
  if detail ~= "" then
    message = message .. ": " .. detail
  end

  local display = command_display(command)
  if display ~= "" then
    message = message .. " (" .. display .. ")"
  end
  return message
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
  { key = "j/k", label = "move" },
  { key = "m", label = "menu" },
  { key = "p", label = "prompt" },
  { key = "O", label = "preview" },
  { key = "e", label = "edit" },
  { key = "x", label = "close" },
  { key = "d", label = "delete" },
  { key = "n", label = "mission" },
  { key = "w", label = "workspace" },
  { key = "q", label = "close" },
}

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

local function mission_default_output_entry(mission)
  mission = type(mission) == "table" and mission or {}
  local fallback = nil
  local active = nil
  local idle = nil
  for _, entry in ipairs(mission.roles or {}) do
    if type(entry) == "table" then
      fallback = fallback or entry
      local status = tostring(entry.status or "")
      if status == "question" then
        return entry
      end
      if status == "active" then
        active = active or entry
      elseif status == "idle" then
        idle = idle or entry
      end
    end
  end
  return active or idle or fallback
end

local function disable_completion(is_loaded_buf, bufnr)
  if type(is_loaded_buf) == "function" and not is_loaded_buf(bufnr) then
    return false
  end

  for _, option in ipairs({ "complete", "completefunc", "omnifunc", "thesaurusfunc", "tagfunc", "dictionary" }) do
    pcall(vim.api.nvim_set_option_value, option, "", { buf = bufnr })
  end

  local buffer_vars = {
    blink_cmp_enabled = false,
    cmp_enabled = false,
    codux_disable_completion = true,
    completion = false,
    copilot_enabled = false,
    minicompletion_disable = true,
  }

  for key, value in pairs(buffer_vars) do
    pcall(function()
      vim.b[bufnr][key] = value
    end)
  end

  return true
end

local mission_control_filetypes = {
  ["codux-missions"] = true,
  ["codux-missions-search"] = true,
  ["codux-missions-command"] = true,
  ["codux-missions-commands"] = true,
  ["codux-missions-actions"] = true,
  ["codux-missions-output"] = true,
  ["codux-mission-preview"] = true,
  ["codux-mission-objective-preview"] = true,
  ["codux-mission-objective"] = true,
  ["codux-mission-workspace-prompt"] = true,
}

local function mark_internal_buffer(is_loaded_buf, bufnr)
  return disable_completion(is_loaded_buf, bufnr)
end

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
    create_mission = type(opts.create_mission) == "function" and opts.create_mission or noop,
    create_workspace_prompt = type(opts.create_workspace_prompt) == "function" and opts.create_workspace_prompt or noop,
    workspace_entries_for_project = type(opts.workspace_entries_for_project) == "function"
        and opts.workspace_entries_for_project
      or function()
        return {}
      end,
    open_saved_workspace = type(opts.open_saved_workspace) == "function" and opts.open_saved_workspace or noop,
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
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
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

function M:dashboard_preview_height(total_height, command_height, mode)
  total_height = math.max(1, tonumber(total_height) or (vim.o.lines - vim.o.cmdheight))
  command_height = math.max(0, tonumber(command_height) or 0)
  mode = mode == "workspace" and "workspace" or "compact"

  if mode == "compact" then
    return 1
  end

  local target = math.min(40, math.max(14, math.floor(total_height * 0.80)))
  local reserved_gaps = (command_height > 0 and 1 or 0) + 1
  local content_capacity = available_dimension(total_height, 4)
  local preferred_dashboard_height = 1
  local preferred_available = content_capacity - command_height - reserved_gaps - preferred_dashboard_height
  if preferred_available >= 1 then
    return math.min(target, preferred_available)
  end

  local compact_available = content_capacity - command_height - reserved_gaps - 1
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
  local preview_height = opts.reserve_output_panel and self:dashboard_preview_height(total_height, command_height, preview_mode)
    or 0
  local command_reserve = command_height > 0 and bordered_float_outer_height(command_height) or 0
  local preview_reserve = preview_height > 0 and bordered_float_outer_height(preview_height) or 0
  local output_reserve = search_reserve + command_reserve + preview_reserve
  local max_height = output_reserve > 0 and math.max(1, total_height - output_reserve - 2)
    or available_dimension(total_height, 4)
  local height = math.min(max_height, math.max(8, line_count or 1))
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
  local desired_height = self:dashboard_preview_height(total_height, command_height, preview_mode)
  local height = math.min(desired_height, math.max(1, available_below))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Output ",
    title_pos = "center",
    footer = " Ctrl-o workspace ",
    footer_pos = "center",
    width = dashboard_width,
    height = height,
    col = math.max(0, dashboard_col),
    row = math.max(0, row),
    zindex = 55,
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
  mark_internal_buffer(self.is_loaded_buf, bufnr)
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
  mark_internal_buffer(self.is_loaded_buf, bufnr)

  self.ui.set_lines(bufnr, preview_lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:preview_config(#preview_lines))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission preview", vim.log.levels.ERROR)
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

  local function launch_mission()
    close_preview()
    self.create_mission(mission)
  end

  local function edit_mission()
    close_preview()
    self:open_objective_editor(mission.name, mission.objective)
  end

  self.set_buffer_keymap(bufnr, "n", "<CR>", launch_mission, "Launch Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "e", edit_mission, "Edit Codux Mission")
  self.bind_close_keys(bufnr, close_preview, "Cancel Codux Mission", "n", { escape = true, q = true })
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
  local name_width = math.min(34, math.max(16, dashboard_width - self.workspace_ui.display_width(right) - 1))
  local mission_name = self.workspace_ui.pad_display_right(tostring(mission.name or mission.mission_id), name_width)
  return mission_name .. " " .. right
end

function M:mission_role_header_line(dashboard_width)
  local branch_width, target_width = self:mission_role_flexible_widths(dashboard_width)
  return "  "
    .. self.workspace_ui.pad_display_right("role", 14)
    .. "  "
    .. self.workspace_ui.pad_display_right("status", 8)
    .. "  "
    .. self.workspace_ui.pad_display_right("mode", 7)
    .. "  "
    .. self.workspace_ui.pad_display_right("permission profile", 18)
    .. "  "
    .. self.workspace_ui.pad_display_right("last activity", 13)
    .. "  "
    .. self.workspace_ui.pad_display_right("needs review", 12)
    .. "  "
    .. self.workspace_ui.pad_display_right("worktree status", 15)
    .. "  "
    .. self.workspace_ui.pad_display_right("window status", 13)
    .. "  "
    .. self.workspace_ui.pad_display_right("worktree", 8)
    .. "  "
    .. self.workspace_ui.pad_display_right("branch", branch_width)
    .. "  "
    .. self.workspace_ui.pad_display_right("cleanup status", 14)
    .. "  "
    .. self.workspace_ui.pad_display_right("target", target_width)
end

function M:mission_role_flexible_widths(dashboard_width)
  local fixed_width = 14 + 8 + 7 + 18 + 13 + 12 + 15 + 13 + 8 + 14 + 2 + (11 * 2)
  local available = math.max(20, dashboard_width - fixed_width)
  local branch_width = math.max(18, math.min(32, math.floor(available * 0.65)))
  local target_width = math.max(10, available - branch_width)
  return branch_width, target_width
end

function M:mission_role_line(entry, dashboard_width, now, dirty_by_role)
  local role = entry.mission_role or entry.name or entry.safe_name
  local status = entry.status or "inactive"
  local mode = self:mission_mode_label(entry)
  local profile = self:permission_profile_label(entry)
  local details = self:mission_workspace_details(entry, dirty_by_role, now)
  local branch_width, target_width = self:mission_role_flexible_widths(dashboard_width)
  local target = type(entry.target_path) == "string" and entry.target_path ~= ""
      and vim.fn.fnamemodify(entry.target_path, ":t")
    or "none"
  return "  "
    .. self.workspace_ui.pad_display_right(role, 14)
    .. "  "
    .. self.workspace_ui.pad_display_right(status, 8)
    .. "  "
    .. self.workspace_ui.pad_display_right(mode, 7)
    .. "  "
    .. self.workspace_ui.pad_display_right(profile, 18)
    .. "  "
    .. self.workspace_ui.pad_display_right(details.last_activity, 13)
    .. "  "
    .. self.workspace_ui.pad_display_right(details.needs_review, 12)
    .. "  "
    .. self.workspace_ui.pad_display_right(details.worktree_status, 15)
    .. "  "
    .. self.workspace_ui.pad_display_right(details.window_status, 13)
    .. "  "
    .. self.workspace_ui.pad_display_right(details.worktree, 8)
    .. "  "
    .. self.workspace_ui.pad_display_right(details.branch, branch_width)
    .. "  "
    .. self.workspace_ui.pad_display_right(details.cleanup_status, 14)
    .. "  "
    .. self.workspace_ui.truncate_display_tail(target, target_width)
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

function M:dashboard_lines(root, opts)
  opts = type(opts) == "table" and opts or {}
  local entries, error_message = self.workspace_entries_for_project(root)
  if error_message then
    return { error_message }, {}, {}
  end

  local all_missions = self.mission.group_entries(entries)
  local query = tostring(opts.query or "")
  local missions = self:filter_missions(all_missions, query)
  local dashboard_width = tonumber(opts.dashboard_width) or self:window_width() or self:dashboard_config(1).width
  local now = self:dashboard_now(opts)
  local lines = {}
  local items = {}
  local selectable_rows = {}
  local best_match_row = nil
  if #all_missions == 0 then
    return { center_display_line(self.workspace_ui, "No Codux missions", dashboard_width) }, items, selectable_rows
  end
  if query ~= "" and #missions == 0 then
    return { center_display_line(self.workspace_ui, "No matching Codux missions", dashboard_width) }, items, selectable_rows
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

  return lines, items, selectable_rows, best_match_row
end

function M:dashboard_output_entry(item)
  if type(item) == "table" then
    if item.kind == "role" and type(item.entry) == "table" then
      return item.entry
    end
    if item.kind == "mission" then
      return mission_default_output_entry(item.mission)
    end
  end
  return nil
end

function M:mission_for_name(root, name)
  local entries, error_message = self.workspace_entries_for_project(root)
  if error_message then
    return nil, error_message
  end

  local missions = self.mission.group_entries(entries)
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
  mark_internal_buffer(self.is_loaded_buf, bufnr)

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

  return self.delete_mission(mission.name or mission.mission_id, root)
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
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, self.namespace, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", 0, 0, -1)

  for index, line in ipairs(lines) do
    local item = items[index]
    if line == "Commands" then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "WhichKeyDesc", index - 1, 0, -1)
    elseif line:find("^%s+Tab%s", 1, false) or line:find("^%s+O%s", 1, false) or line:find("^%s+n%s", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 0, -1)
    elseif line:find("^Output%s%s", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "WhichKeyDesc", index - 1, 0, 6)
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 6, -1)
    elseif item and item.kind == "mission" and not line:find("^%s+objective", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "WhichKey", index - 1, 0, -1)
    elseif item and item.kind == "mission" then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 0, -1)
    elseif line:find("^%s+role%s+", 1, false) then
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

  local selected_row = self.state.mission_dashboard_search_confirmed and self.state.mission_dashboard_selected_row
    or self.state.mission_dashboard_best_match_row
  if selected_row then
    local group = self.state.mission_dashboard_search_confirmed and "IncSearch" or "Visual"
    local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, self.namespace, selected_row - 1, 0, {
      line_hl_group = group,
    })
    if not ok then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, group, selected_row - 1, 0, -1)
    end
  end
end

function M:highlight_output_panel(bufnr, lines)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, self.namespace, 0, -1)
  for index, line in ipairs(lines or {}) do
    local prefix_end = line:find("^Output:%s", 1, false)
    if prefix_end then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "WhichKeyDesc", index - 1, 0, prefix_end)
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, prefix_end, -1)
    elseif line:find("^%s+", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", index - 1, 0, -1)
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
  mark_internal_buffer(self.is_loaded_buf, bufnr)
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

function M:output_panel_lines(entry, message)
  local lines = {}
  if type(entry) ~= "table" then
    table.insert(lines, "Output: select a workspace row to preview its Codux session")
    return lines
  end

  if entry.status == "inactive" then
    table.insert(lines, "Output: workspace inactive")
    return lines
  end

  local role = entry.mission_role or entry.name or entry.safe_name or "workspace"
  table.insert(lines, "Output: " .. tostring(role))
  table.insert(lines, "  " .. tostring(message or "opening workspace session preview..."))
  table.insert(lines, "  Ctrl-o workspace")
  return lines
end

function M:selected_output_entry()
  local item = self:selected_item()
  return self:dashboard_output_entry(item)
end

function M:output_entry_key(entry)
  if type(entry) ~= "table" then
    return ""
  end
  return role_cache_key(entry)
end

function M:output_preview_running()
  local job_id = self.state.mission_dashboard_output_job
  if type(job_id) ~= "number" or job_id <= 0 then
    return false
  end
  local ok, statuses = pcall(vim.fn.jobwait, { job_id }, 0)
  return ok and type(statuses) == "table" and statuses[1] == -1
end

function M:render_output_status(entry, message)
  if not self:ensure_output_buffer("status", self:output_panel_lines(entry, message)) then
    return false
  end
  local lines = self:output_panel_lines(entry, message)
  self.ui.set_lines(self.state.mission_dashboard_output_buf, lines, { modifiable = true })
  self:highlight_output_panel(self.state.mission_dashboard_output_buf, lines)
  pcall(vim.api.nvim_set_option_value, "modified", false, { buf = self.state.mission_dashboard_output_buf })
  return true
end

function M:output_buffer_buftype(bufnr)
  if not self.is_loaded_buf(bufnr) then
    return nil
  end
  local ok, buftype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = bufnr })
  return ok and buftype or nil
end

function M:attach_output_buffer_autocmd(bufnr)
  if not self.is_loaded_buf(bufnr) then
    return false
  end

  local group = vim.api.nvim_create_augroup("codux-mission-output-" .. tostring(bufnr), { clear = true })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if self.state.mission_dashboard_output_replacing_buf == bufnr then
        pcall(vim.api.nvim_del_augroup_by_id, group)
        return
      end
      if self.state.mission_dashboard_output_buf == bufnr then
        self:close_output_preview()
        self.state.mission_dashboard_output_buf = nil
        self.state.mission_dashboard_output_win = nil
        self.state.mission_dashboard_output_entry = nil
        self.state.mission_dashboard_output_key = nil
        self.state.mission_dashboard_output_blocked_key = nil
        self.state.mission_dashboard_output_buf_kind = nil
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
  return true
end

function M:create_output_buffer(kind, lines)
  if type(self.ui.create_scratch_buffer) ~= "function" then
    return nil
  end

  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions-output",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    return nil
  end

  mark_internal_buffer(self.is_loaded_buf, bufnr)
  if type(lines) == "table" then
    self.ui.set_lines(bufnr, lines, { modifiable = true })
    self:highlight_output_panel(bufnr, lines)
  end
  self:bind_output_panel_commands(bufnr)
  self:attach_output_buffer_autocmd(bufnr)
  return bufnr
end

function M:output_window_buffer()
  if not self.is_valid_win(self.state.mission_dashboard_output_win) then
    return nil
  end

  local ok, current = pcall(vim.api.nvim_win_get_buf, self.state.mission_dashboard_output_win)
  return ok and current or nil
end

function M:unlock_output_window()
  local win = self.state.mission_dashboard_output_win
  if not self.is_valid_win(win) then
    return false
  end
  pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
  return true
end

function M:set_output_window_buffer(bufnr)
  local win = self.state.mission_dashboard_output_win
  if not self.is_valid_win(win) then
    return true
  end

  local current = self:output_window_buffer()
  if current == nil then
    return true
  end
  if current == bufnr then
    return true
  end

  local had_winfixbuf = false
  local winfix_ok, winfixbuf = pcall(vim.api.nvim_get_option_value, "winfixbuf", { win = win })
  if winfix_ok then
    had_winfixbuf = winfixbuf == true
    if had_winfixbuf then
      pcall(vim.api.nvim_set_option_value, "winfixbuf", false, { win = win })
    end
  end

  local set_ok = pcall(vim.api.nvim_win_set_buf, win, bufnr)
  if winfix_ok and had_winfixbuf then
    self:unlock_output_window()
  end
  if not set_ok then
    return false
  end

  return self:output_window_buffer() == bufnr
end

function M:replace_output_buffer(kind, lines)
  local old_buf = self.state.mission_dashboard_output_buf
  local bufnr = self:create_output_buffer(kind, lines)
  if not bufnr then
    if not self.is_loaded_buf(old_buf) then
      return false
    end
    self.state.mission_dashboard_output_buf_kind = kind
    return true
  end

  self.state.mission_dashboard_output_replacing_buf = old_buf
  if not self:set_output_window_buffer(bufnr) then
    if self.state.mission_dashboard_output_replacing_buf == old_buf then
      self.state.mission_dashboard_output_replacing_buf = nil
    end
    self.ui.delete_buffer(bufnr)
    return false
  end

  self.state.mission_dashboard_output_buf = bufnr
  self.state.mission_dashboard_output_buf_kind = kind
  if old_buf ~= bufnr then
    self.ui.delete_buffer(old_buf)
  end
  if self.state.mission_dashboard_output_replacing_buf == old_buf then
    self.state.mission_dashboard_output_replacing_buf = nil
  end
  return true
end

function M:ensure_output_buffer(kind, lines)
  local bufnr = self.state.mission_dashboard_output_buf
  local buftype = self:output_buffer_buftype(bufnr)
  local current_kind = self.state.mission_dashboard_output_buf_kind
  local must_replace = not self.is_loaded_buf(bufnr)
    or current_kind ~= kind
    or buftype == "terminal"
    or kind == "terminal"

  if must_replace then
    return self:replace_output_buffer(kind, lines)
  end

  self.state.mission_dashboard_output_buf_kind = kind
  return true
end

function M:prepare_output_terminal_buffer()
  if not self:ensure_output_buffer("terminal") then
    return false
  end

  local bufnr = self.state.mission_dashboard_output_buf
  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
  return true
end

function M:close_output_preview()
  local job_id = self.state.mission_dashboard_output_job
  self.state.mission_dashboard_output_job = nil
  if type(job_id) == "number" and job_id > 0 then
    pcall(self.jobstop, job_id)
  end
  local preview = self.state.mission_dashboard_output_preview
  self.state.mission_dashboard_output_preview = nil
  if preview then
    pcall(self.close_workspace_interactive_preview, preview)
  end
end

function M:start_output_preview(entry)
  if not self.is_loaded_buf(self.state.mission_dashboard_output_buf) then
    return false
  end

  self:close_output_preview()
  self.state.mission_dashboard_output_generation = (tonumber(self.state.mission_dashboard_output_generation) or 0) + 1
  local generation = self.state.mission_dashboard_output_generation
  self.state.mission_dashboard_output_entry = entry
  self.state.mission_dashboard_output_key = self:output_entry_key(entry)
  self.state.mission_dashboard_output_blocked_key = nil
  if type(entry) ~= "table" then
    return self:render_output_status(entry, "select a workspace to preview")
  end
  if entry.status == "inactive" then
    return self:render_output_status(entry, "workspace is not active")
  end

  self:render_output_status(entry, "opening workspace session preview...")
  local preview, error_message = self.workspace_interactive_preview(entry)
  if not preview then
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, error_message or "workspace session preview unavailable")
  end

  local command = preview.command
  if type(command) ~= "table" and type(command) ~= "string" then
    self.close_workspace_interactive_preview(preview)
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, "workspace session preview command unavailable")
  end

  if not self:prepare_output_terminal_buffer() then
    self.close_workspace_interactive_preview(preview)
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, "workspace session preview buffer unavailable")
  end
  local preview_key = self.state.mission_dashboard_output_key
  local preview_buf = self.state.mission_dashboard_output_buf
  local term_ok, term_error = pcall(vim.api.nvim_buf_call, self.state.mission_dashboard_output_buf, function()
    return self.termopen(command, {
      on_exit = function(exited_job_id, code)
        if
          self.state.mission_dashboard_output_job == exited_job_id
          and self.state.mission_dashboard_output_generation == generation
          and self.state.mission_dashboard_output_key == preview_key
        then
          self.state.mission_dashboard_output_job = nil
          local active_entry = self.state.mission_dashboard_output_entry
          local active_key = self.state.mission_dashboard_output_key
          local active_preview = self.state.mission_dashboard_output_preview
          self.state.mission_dashboard_output_preview = nil
          if active_preview then
            pcall(self.close_workspace_interactive_preview, active_preview)
          end
          self.state.mission_dashboard_output_blocked_key = active_key
          self:render_output_status(active_entry, "workspace preview exited with code " .. tostring(code))
        end
      end,
    })
  end)
  if not term_ok or type(term_error) ~= "number" or term_error <= 0 then
    self.close_workspace_interactive_preview(preview)
    local detail = term_ok and ("invalid job id " .. tostring(term_error)) or term_error
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, preview_attach_error(command, detail))
  end

  self.state.mission_dashboard_output_job = term_error
  self.state.mission_dashboard_output_preview = preview
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-missions-output", { buf = preview_buf })
  return true
end

function M:render_output_panel(entry)
  if not self.is_loaded_buf(self.state.mission_dashboard_output_buf) then
    return false
  end
  entry = type(entry) == "table" and entry or self:selected_output_entry()
  local key = self:output_entry_key(entry)
  if key ~= self.state.mission_dashboard_output_key then
    return self:start_output_preview(entry)
  end
  if self:output_preview_running() then
    return true
  end
  if key ~= "" and key == self.state.mission_dashboard_output_blocked_key then
    return true
  end
  return self:start_output_preview(entry)
end

function M:focus_output_panel()
  if not self.is_valid_win(self.state.mission_dashboard_output_win) then
    return false
  end
  self:unlock_output_window()
  local ok = self.set_current_win(self.state.mission_dashboard_output_win)
  if ok and self:output_preview_running() then
    pcall(vim.cmd, "startinsert")
  end
  return ok
end

function M:bind_output_panel_commands(bufnr)
  self.set_buffer_keymap(bufnr, { "n", "t" }, "<C-q>", function()
    return self:close_dashboard()
  end, "Close Codux Missions", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, { "n", "t" }, "<C-o>", function()
    return self:open_output_workspace()
  end, "Open Codux Mission Workspace", {
    nowait = true,
  })
end

function M:open_output_panel(entry)
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return false
  end
  if self.is_valid_win(self.state.mission_dashboard_output_win) and self.is_loaded_buf(self.state.mission_dashboard_output_buf) then
    return self:render_output_panel(entry)
  end

  local initial_lines = self:output_panel_lines(entry, "opening workspace session preview...")
  local bufnr = self:create_output_buffer("status", initial_lines)
  if not bufnr then
    self.notify("Failed to create Codux mission output", vim.log.levels.ERROR)
    return false
  end
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, self:dashboard_output_config(#initial_lines, {
    preview_mode = self:dashboard_preview_mode({ kind = "role", entry = entry }),
  }))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission output", vim.log.levels.ERROR)
    return false
  end

  self.state.mission_dashboard_output_buf = bufnr
  self.state.mission_dashboard_output_win = win
  self.state.mission_dashboard_output_buf_kind = "status"
  self.state.mission_dashboard_output_entry = entry
  self.state.mission_dashboard_output_key = nil
  self.ui.set_window_options(win, {
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = false,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  self:start_output_preview(entry)

  return true
end

function M:close_output_panel()
  self:close_output_preview()
  self.ui.close_window(self.state.mission_dashboard_output_win)
  self.ui.delete_buffer(self.state.mission_dashboard_output_buf)
  self.state.mission_dashboard_output_win = nil
  self.state.mission_dashboard_output_buf = nil
  self.state.mission_dashboard_output_entry = nil
  self.state.mission_dashboard_output_key = nil
  self.state.mission_dashboard_output_blocked_key = nil
  self.state.mission_dashboard_output_buf_kind = nil
  return true
end

function M:render_dashboard()
  if not self.is_loaded_buf(self.state.mission_dashboard_buf) then
    return false
  end

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
  self:resize_dashboard_stack(#lines, { selected_item = selected_item })
  self.ui.set_lines(self.state.mission_dashboard_buf, lines, { modifiable = true })
  self:highlight_dashboard(self.state.mission_dashboard_buf, lines, items)
  self:render_command_bar()
  self:render_output_panel(self:dashboard_output_entry(selected_item))
  if self.state.mission_dashboard_focus_match and self.is_valid_win(self.state.mission_dashboard_win) then
    local row = best_match_row or selectable_rows[1] or 1
    self.set_window_cursor(self.state.mission_dashboard_win, { row, 0 })
    self.state.mission_dashboard_focus_match = false
  end

  return true
end

function M:render_search()
  if not self.is_loaded_buf(self.state.mission_dashboard_search_buf) then
    return false
  end

  local query = tostring(self.state.mission_dashboard_query or "")
  self.ui.set_lines(self.state.mission_dashboard_search_buf, { query .. " " }, { modifiable = true })

  if self.is_valid_win(self.state.mission_dashboard_search_win) then
    local width = self:window_width() or 1
    pcall(vim.api.nvim_win_set_cursor, self.state.mission_dashboard_search_win, { 1, math.min(#query, math.max(0, width - 1)) })
  end

  return true
end

function M:update_query(query)
  self.state.mission_dashboard_query = tostring(query or "")
  self.state.mission_dashboard_selected_row = nil
  self.state.mission_dashboard_focus_match = true
  self.state.mission_dashboard_search_confirmed = false
  self:render_dashboard()
  self:render_search()
  return true
end

function M:append_query(input)
  return self:update_query(tostring(self.state.mission_dashboard_query or "") .. tostring(input or ""))
end

function M:delete_query_char()
  local query = tostring(self.state.mission_dashboard_query or "")
  if query == "" then
    return true
  end

  local length = vim.fn.strchars(query)
  return self:update_query(vim.fn.strcharpart(query, 0, math.max(0, length - 1)))
end

function M:clear_query()
  if self.state.mission_dashboard_query == "" then
    return true
  end

  return self:update_query("")
end

function M:selected_row()
  if self.state.mission_dashboard_search_confirmed and self.state.mission_dashboard_selected_row then
    return self.state.mission_dashboard_selected_row
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
  self.set_window_cursor(self.state.mission_dashboard_win, { self:mission_list_focus_row(), 0 })
  return self.set_current_win(self.state.mission_dashboard_win)
end

function M:focus_search_input()
  if self.is_valid_win(self.state.mission_dashboard_search_win) then
    return self.set_current_win(self.state.mission_dashboard_search_win)
  end

  return self:open_search_input()
end

function M:toggle_search_list_focus()
  if
    self.is_valid_win(self.state.mission_dashboard_search_win)
    and self.get_current_win() == self.state.mission_dashboard_search_win
  then
    return self:focus_mission_list()
  end

  return self:focus_search_input()
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
  self.set_window_cursor(self.state.mission_dashboard_win, { next_row, 0 })
  return true
end

function M:open_search_input(opts)
  opts = type(opts) == "table" and opts or {}
  local focus = opts.focus ~= false
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return false
  end

  if self.is_valid_win(self.state.mission_dashboard_search_win) then
    pcall(self.set_window_config, self.state.mission_dashboard_search_win, self:dashboard_search_config())
    if focus then
      return self.set_current_win(self.state.mission_dashboard_search_win)
    end
    return true
  end

  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions-search",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    self.notify("Failed to create Codux mission search", vim.log.levels.ERROR)
    return false
  end
  mark_internal_buffer(self.is_loaded_buf, bufnr)

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, focus, self:dashboard_search_config())
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission search", vim.log.levels.ERROR)
    return false
  end

  self.state.mission_dashboard_search_buf = bufnr
  self.state.mission_dashboard_search_win = win
  self.ui.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  self:render_search()

  local group = vim.api.nvim_create_augroup("codux-mission-search-" .. tostring(bufnr), { clear = true })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if self.state.mission_dashboard_search_buf == bufnr then
        self.state.mission_dashboard_search_buf = nil
        self.state.mission_dashboard_search_win = nil
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  self.bind_close_keys(bufnr, function()
    return self:close_dashboard()
  end, "Close Codux Missions", "n", { escape = true })
  self.set_buffer_keymap(bufnr, "n", "<Tab>", function()
    return self:focus_mission_list()
  end, "Focus Codux Mission List", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "<CR>", function()
    if not self.state.mission_dashboard_best_match_row then
      self.notify("No Codux mission selected", vim.log.levels.WARN)
      return false
    end

    self.state.mission_dashboard_search_confirmed = true
    self.state.mission_dashboard_selected_row = self.state.mission_dashboard_best_match_row
    self.state.mission_dashboard_focus_match = false
    self:render_dashboard()
    if self.is_valid_win(self.state.mission_dashboard_win) then
      self.set_current_win(self.state.mission_dashboard_win)
    end
    return true
  end, "Select Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "<BS>", function()
    return self:delete_query_char()
  end, "Delete Codux Mission Search Character", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "<C-h>", function()
    return self:delete_query_char()
  end, "Delete Codux Mission Search Character", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "<C-u>", function()
    return self:clear_query()
  end, "Clear Codux Mission Search", {
    nowait = true,
  })
  for _, key in ipairs(self.ui.printable_prompt_keys()) do
    local lhs = key[1]
    local input = key[2]
    self.set_buffer_keymap(bufnr, "n", lhs, function()
      return self:append_query(input)
    end, "Search Codux Missions", {
      nowait = true,
    })
  end

  self:render_search()
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
    on_create_buffer = function(target_bufnr)
      mark_internal_buffer(self.is_loaded_buf, target_bufnr)
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
  self.ui.close_window(self.state.mission_dashboard_action_win)
  self.ui.delete_buffer(self.state.mission_dashboard_action_buf)
  self.state.mission_dashboard_action_win = nil
  self.state.mission_dashboard_action_buf = nil
  self.state.mission_dashboard_action_items = {}
  self.state.mission_dashboard_action_mission = nil
  self.state.mission_dashboard_action_workspace = nil
  self.state.mission_dashboard_action_kind = nil
  return true
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
  if not self.is_loaded_buf(self.state.mission_dashboard_action_buf) then
    return false
  end

  local width = self:action_palette_width()
  local lines = {}
  local action_kind = self.state.mission_dashboard_action_kind
  for _, item in ipairs(self.state.mission_dashboard_action_items or {}) do
    local line = action_kind == "workspace" and self.workspace_ui.role_workspace_action_line(item, width)
      or self.workspace_ui.mission_action_line(item, width)
    table.insert(lines, line)
  end

  self.ui.set_lines(self.state.mission_dashboard_action_buf, lines, { modifiable = true })
  pcall(vim.api.nvim_buf_clear_namespace, self.state.mission_dashboard_action_buf, self.namespace, 0, -1)
  for index, item in ipairs(self.state.mission_dashboard_action_items or {}) do
    local key = tostring(item.key or "")
    if key ~= "" then
      local label_start = #key + 2
      pcall(
        vim.api.nvim_buf_add_highlight,
        self.state.mission_dashboard_action_buf,
        self.namespace,
        "WhichKey",
        index - 1,
        0,
        #key
      )
      pcall(
        vim.api.nvim_buf_add_highlight,
        self.state.mission_dashboard_action_buf,
        self.namespace,
        "Normal",
        index - 1,
        #key,
        label_start
      )
      pcall(
        vim.api.nvim_buf_add_highlight,
        self.state.mission_dashboard_action_buf,
        self.namespace,
        "Normal",
        index - 1,
        label_start,
        -1
      )
    end
  end
  return true
end

function M:edit_selected_mission(mission)
  local root = self.state.mission_dashboard_project_root or self.project_root()
  mission = mission or self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  self:close_dashboard()
  return self:open_objective_editor(mission.name, mission.objective, {
    title = " Edit Codux Mission Objective ",
    footer = " Ctrl-s/:w save | Ctrl-q cancel ",
    on_save = function(_, objective)
      local ok = self.update_mission_objective(mission.name, objective, root)
      if ok ~= false then
        vim.schedule(function()
          self:open_dashboard(root)
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
  self:close_dashboard()
  return self.delete_mission(mission.name or mission.mission_id, root)
end

function M:close_selected_mission(mission)
  local root = self.state.mission_dashboard_project_root or self.project_root()
  mission = mission or self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  self:close_dashboard()
  return self.close_mission(mission.name or mission.mission_id, root)
end

function M:start_selected_mission(mission)
  local root = self.state.mission_dashboard_project_root or self.project_root()
  mission = mission or self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end
  self:close_dashboard()
  local ok = self.start_mission(mission.name or mission.mission_id, root, {
    restart_inactive = true,
    prompt_roles = true,
    focus_first = true,
  })
  if not ok then
    self:open_dashboard(root)
  end
  return ok
end

function M:action_palette_target()
  if self.state.mission_dashboard_action_kind == "workspace" then
    return self.state.mission_dashboard_action_workspace
  end
  return self.state.mission_dashboard_action_mission
end

function M:run_action(action, target)
  local workspace = target or self.state.mission_dashboard_action_workspace
  if action == "open_workspace" then
    workspace = workspace or self:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    self:close_action_palette()
    return self:open_role_workspace(workspace)
  end
  if action == "prompt_workspace" then
    workspace = workspace or self:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    self:close_action_palette()
    return self:open_workspace_prompt(workspace)
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

  local mission = target or self.state.mission_dashboard_action_mission or self:selected_mission_name_or_notify()
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

function M:run_highlighted_action()
  if not self.is_valid_win(self.state.mission_dashboard_action_win) then
    return false
  end

  local cursor = self.get_window_cursor(self.state.mission_dashboard_action_win)
  if not cursor then
    return false
  end

  local action_item = self.state.mission_dashboard_action_items[cursor[1]]
  if not action_item then
    return false
  end
  return self:run_action(action_item.action, self:action_palette_target())
end

function M:move_action_cursor(delta)
  if not self.is_valid_win(self.state.mission_dashboard_action_win) then
    return false
  end

  local count = #self.state.mission_dashboard_action_items
  if count == 0 then
    return false
  end

  local cursor = self.get_window_cursor(self.state.mission_dashboard_action_win)
  if not cursor then
    return false
  end
  local row = ((cursor[1] - 1 + delta) % count) + 1
  self.set_window_cursor(self.state.mission_dashboard_action_win, { row, 0 })
  return true
end

function M:open_action_palette_for(target, kind)
  target = type(target) == "table" and target or nil
  if not target then
    return false
  end

  self:close_action_palette()
  local action_items = kind == "workspace" and self.workspace_ui.role_workspace_action_items(target)
    or self.workspace_ui.mission_action_items(target)
  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions-actions",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    local label = kind == "workspace" and "workspace" or "mission"
    self.notify("Failed to create Codux " .. label .. " actions", vim.log.levels.ERROR)
    return false
  end
  mark_internal_buffer(self.is_loaded_buf, bufnr)

  self.state.mission_dashboard_action_buf = bufnr
  self.state.mission_dashboard_action_items = action_items
  self.state.mission_dashboard_action_mission = kind == "workspace" and nil or target
  self.state.mission_dashboard_action_workspace = kind == "workspace" and target or nil
  self.state.mission_dashboard_action_kind = kind
  self:render_action_palette()

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:action_palette_config(target, #action_items, kind))
  if not win_ok then
    self:close_action_palette()
    local label = kind == "workspace" and "workspace" or "mission"
    self.notify("Failed to open Codux " .. label .. " actions", vim.log.levels.ERROR)
    return false
  end

  self.state.mission_dashboard_action_win = win
  self.ui.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    cursorline = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })

  local action_label = kind == "workspace" and "Workspace" or "Mission"
  self.bind_close_keys(bufnr, function()
    return self:close_action_palette()
  end, "Close Codux " .. action_label .. " Actions", "n", { escape = true, q = true })
  self.set_buffer_keymap(bufnr, "n", "<CR>", function()
    return self:run_highlighted_action()
  end, "Run Codux " .. action_label .. " Action")
  self.set_buffer_keymap(bufnr, "n", "j", function()
    return self:move_action_cursor(1)
  end, "Next Codux " .. action_label .. " Action", { nowait = true })
  self.set_buffer_keymap(bufnr, "n", "<Down>", function()
    return self:move_action_cursor(1)
  end, "Next Codux " .. action_label .. " Action", { nowait = true })
  self.set_buffer_keymap(bufnr, "n", "k", function()
    return self:move_action_cursor(-1)
  end, "Previous Codux " .. action_label .. " Action", { nowait = true })
  self.set_buffer_keymap(bufnr, "n", "<Up>", function()
    return self:move_action_cursor(-1)
  end, "Previous Codux " .. action_label .. " Action", { nowait = true })

  for _, action_item in ipairs(action_items) do
    local bound_action = action_item.action
    local bound_label = action_item.label
    self.set_buffer_keymap(bufnr, "n", action_item.key, function()
      return self:run_action(bound_action, target)
    end, bound_label .. " Codux " .. action_label, { nowait = true })
  end

  pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
  return true
end

function M:selected_mission_name_or_notify()
  local item = self:selected_selectable_item()
  if not item or item.kind ~= "mission" then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return nil
  end
  return item.mission
end

function M:selected_role_workspace_or_notify()
  local item = self:selected_selectable_item()
  if not item or item.kind ~= "role" or type(item.entry) ~= "table" then
    self.notify("No Codux workspace selected", vim.log.levels.WARN)
    return nil
  end
  return item.entry
end

function M:open_role_workspace(entry)
  if type(entry) ~= "table" then
    return false
  end
  local name = entry.safe_name or entry.name
  if type(name) ~= "string" or name == "" then
    return false
  end

  local ok = self.open_saved_workspace(name, entry.project_root)
  if ok then
    self:close_dashboard()
  end
  return ok
end

function M:open_output_workspace()
  local entry = self:selected_output_entry()
  if type(entry) ~= "table" then
    entry = self.state.mission_dashboard_output_entry
  end
  if type(entry) ~= "table" then
    self.notify("No Codux workspace selected", vim.log.levels.WARN)
    return false
  end

  local name = entry.safe_name or entry.name
  if type(name) ~= "string" or name == "" then
    self.notify("No Codux workspace selected", vim.log.levels.WARN)
    return false
  end

  return self:open_role_workspace(entry)
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

  return prompt_fn({
    prompt = "Prompt " .. tostring(label) .. ": ",
    filetype = "codux-mission-workspace-prompt",
    zindex = 80,
    on_create_buffer = function(bufnr)
      mark_internal_buffer(self.is_loaded_buf, bufnr)
    end,
  }, function(input)
    if input == nil then
      return
    end
    if trim(input) == "" then
      self.notify("Prompt is required", vim.log.levels.WARN)
      return
    end

    local ok, error_message = self.send_prompt_to_workspace(entry, input)
    if ok then
      self.notify("Sent prompt to " .. tostring(label))
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
  self:close_dashboard()
  return self:open_prompt()
end

function M:create_new_workspace()
  self:close_dashboard()
  return self.create_workspace_prompt()
end

function M:bind_dashboard_commands(bufnr)
  self.bind_close_keys(bufnr, function()
    return self:close_dashboard()
  end, "Close Codux Missions", "n", { escape = true, q = true })
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
  self.set_buffer_keymap(bufnr, "n", "p", function()
    return self:open_workspace_prompt()
  end, "Prompt Codux Mission Role")
  self.set_buffer_keymap(bufnr, "n", "O", function()
    return self:focus_output_panel()
  end, "Focus Codux Mission Output")
  self.set_buffer_keymap(bufnr, "n", "e", function()
    return self:edit_selected_mission()
  end, "Edit Codux Mission Objective")
  self.set_buffer_keymap(bufnr, "n", "x", function()
    return self:close_selected_mission()
  end, "Close Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "d", function()
    return self:delete_selected_mission()
  end, "Delete Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "n", function()
    return self:create_new_mission()
  end, "Create Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "w", function()
    return self:create_new_workspace()
  end, "Create Codux Workspace")
end

function M:open_dashboard(root)
  self:close_dashboard()
  root = root or self.project_root()
  local lines, items, selectable_rows, best_match_row = self:dashboard_lines(root)
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
  mark_internal_buffer(self.is_loaded_buf, bufnr)

  self.ui.set_lines(bufnr, lines, { modifiable = true })
  self:highlight_dashboard(bufnr, lines, items)
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:dashboard_config(#lines, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    reserve_search_input = true,
    selected_item = initial_selected_item,
  }))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux missions dashboard", vim.log.levels.ERROR)
    return false
  end
  self.ui.set_window_options(win, {
    cursorline = true,
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  self.state.mission_dashboard_buf = bufnr
  self.state.mission_dashboard_win = win
  self.state.mission_dashboard_project_root = root
  self.state.mission_dashboard_items = items
  self.state.mission_dashboard_selectable_rows = selectable_rows
  self.state.mission_dashboard_best_match_row = best_match_row
  self.state.mission_dashboard_selected_row = selectable_rows[1]
  self.state.mission_dashboard_query = ""
  self.state.mission_dashboard_focus_match = false
  self.state.mission_dashboard_search_confirmed = false
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
  if #selectable_rows > 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { selectable_rows[1], 0 })
  end
  vim.schedule(function()
    if self.is_valid_win(self.state.mission_dashboard_win) and self.is_loaded_buf(self.state.mission_dashboard_buf) then
      self:open_search_input({ focus = false })
    end
  end)
  return true
end

return M
