local M = {}
M.__index = M

local mission_mod = require("codux.mission")
local ui = require("codux.ui")

local function noop() end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function available_dimension(total, margin)
  return math.max(1, total - margin)
end

local function entry_key(entry)
  entry = type(entry) == "table" and entry or {}
  return tostring(entry.safe_name or entry.name or entry.mission_role or "")
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
    update_mission_objective = type(opts.update_mission_objective) == "function"
        and opts.update_mission_objective
      or noop,
    mission_dirty_roles = type(opts.mission_dirty_roles) == "function" and opts.mission_dirty_roles or function()
      return {}
    end,
    close_mission = type(opts.close_mission) == "function" and opts.close_mission or noop,
    delete_mission = type(opts.delete_mission) == "function" and opts.delete_mission or noop,
    project_root = type(opts.project_root) == "function" and opts.project_root or function()
      return vim.loop.cwd()
    end,
    set_buffer_keymap = type(opts.set_buffer_keymap) == "function" and opts.set_buffer_keymap or ui.set_keymap,
    bind_close_keys = type(opts.bind_close_keys) == "function" and opts.bind_close_keys or ui.bind_close_keys,
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
    title = " codux mission control ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
  }
end

function M:dashboard_config(line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local max_width = available_dimension(total_width, 4)
  local max_height = available_dimension(total_height, 4)
  local width = math.min(max_width, math.max(80, math.floor(total_width * 0.76)))
  local height = math.min(max_height, math.max(8, line_count or 1))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " codux mission dashboard ",
    title_pos = "center",
    footer = " Enter open | m menu | e objective | x close | d delete | n new | r refresh | q close ",
    footer_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
  }
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
  })
  disable_completion(self.is_loaded_buf, bufnr)
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
      close_editor()
      return
    end

    local mission, plan_error = self.mission.plan(mission_name, objective)
    if not mission then
      self.notify(plan_error, vim.log.levels.ERROR)
      return
    end

    saved = true
    close_editor()
    self:open_preview(mission)
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = autocmd_group,
    buffer = bufnr,
    callback = save_editor,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = autocmd_group,
    buffer = bufnr,
    callback = function()
      pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
    end,
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

function M:dashboard_lines(root, opts)
  opts = type(opts) == "table" and opts or {}
  local entries, error_message = self.workspace_entries_for_project(root)
  if error_message then
    return { error_message }, {}, {}
  end

  local all_missions = self.mission.group_entries(entries)
  local query = tostring(opts.query or "")
  local missions = self:filter_missions(all_missions, query)
  local lines = {
    "Mission Control",
  }
  local items = {}
  local selectable_rows = {}
  local best_match_row = nil
  if #all_missions == 0 then
    return { "Mission Control", "", "No Codux missions" }, items, selectable_rows
  end
  if query ~= "" and #missions == 0 then
    return { "Mission Control", "", "No matching Codux missions" }, items, selectable_rows
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
    string.format(
      "%d missions | %d roles | %d active | %d question | %d idle",
      #missions,
      total_roles,
      total_active,
      total_question,
      total_idle
    )
  )

  for mission_index, mission in ipairs(missions) do
    table.insert(lines, "")
    local counts = self.mission.status_counts(mission)
    local status = self.mission.status_label(mission)
    local mission_name = self.workspace_ui.truncate_display_tail(tostring(mission.name or mission.mission_id), 34)
    table.insert(lines, string.format("%-34s %-8s %2d roles", mission_name, status, counts.total))
    items[#lines] = { kind = "mission", mission = mission }
    table.insert(selectable_rows, #lines)
    if query ~= "" and not best_match_row and mission._codux_match_kind == "mission" then
      best_match_row = #lines
    end
    if type(mission.objective) == "string" and mission.objective ~= "" then
      local objective = mission.objective:gsub("\n.*$", "")
      table.insert(lines, "  objective  " .. self.workspace_ui.truncate_display_tail(objective, 76))
      items[#lines] = { kind = "mission", mission = mission }
    end
    table.insert(lines, "  role           status    mode  age   workspace")
    for _, entry in ipairs(mission.roles) do
      local role = entry.mission_role or entry.name or entry.safe_name
      local status = entry.status or "inactive"
      local mode = self.workspace_ui.manager_mode_label(entry)
      local age = self.workspace_ui.relative_age_label(self.workspace_ui.session_timestamp(entry))
      local workspace = entry.name or entry.safe_name or ""
      local line = string.format(
        "  %-14s %-8s %-4s %-4s %s",
        self.workspace_ui.truncate_display_tail(role, 14),
        status,
        mode,
        age,
        self.workspace_ui.truncate_display_tail(workspace, 34)
      )
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
  pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Title", 0, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, bufnr, self.namespace, "Comment", 1, 0, -1)

  for index, line in ipairs(lines) do
    local item = items[index]
    if item and item.kind == "mission" and not line:find("^%s+objective", 1, false) then
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

function M:render_dashboard()
  if not self.is_loaded_buf(self.state.mission_dashboard_buf) then
    return false
  end

  local root = self.state.mission_dashboard_project_root or self.project_root()
  local query = tostring(self.state.mission_dashboard_query or "")
  local lines, items, selectable_rows, best_match_row = self:dashboard_lines(root, { query = query })
  self.state.mission_dashboard_items = items
  self.state.mission_dashboard_selectable_rows = selectable_rows
  self.state.mission_dashboard_best_match_row = best_match_row

  self.ui.set_lines(self.state.mission_dashboard_buf, lines, { modifiable = true })
  self:highlight_dashboard(self.state.mission_dashboard_buf, lines, items)
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

function M:open_search_input()
  if not self.is_valid_win(self.state.mission_dashboard_win) then
    return false
  end

  if self.is_valid_win(self.state.mission_dashboard_search_win) then
    return self.set_current_win(self.state.mission_dashboard_search_win)
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

  local dashboard_config = self.get_window_config(self.state.mission_dashboard_win)
  local width = math.max(20, self:window_width() or 58)
  local col = type(dashboard_config.col) == "number" and dashboard_config.col or 0
  local row = math.max(0, (type(dashboard_config.row) == "number" and dashboard_config.row or 0) - 3)

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Codux mission: ",
    title_pos = "center",
    width = width,
    height = 1,
    col = col,
    row = row,
    zindex = 60,
  })
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
    if self.is_valid_win(self.state.mission_dashboard_command_win) then
      self.set_current_win(self.state.mission_dashboard_command_win)
    elseif self.is_valid_win(self.state.mission_dashboard_win) then
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
  self:close_action_palette()
  self.ui.close_window(self.state.mission_dashboard_search_win)
  self.ui.close_window(self.state.mission_dashboard_command_win)
  self.ui.close_window(self.state.mission_dashboard_win)
  self.ui.delete_buffer(self.state.mission_dashboard_search_buf)
  self.ui.delete_buffer(self.state.mission_dashboard_command_buf)
  self.ui.delete_buffer(self.state.mission_dashboard_buf)

  local dashboard_filetypes = {
    ["codux-missions"] = true,
    ["codux-missions-search"] = true,
    ["codux-missions-command"] = true,
    ["codux-missions-actions"] = true,
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

  self.state.mission_dashboard_buf = nil
  self.state.mission_dashboard_win = nil
  self.state.mission_dashboard_search_buf = nil
  self.state.mission_dashboard_search_win = nil
  self.state.mission_dashboard_command_buf = nil
  self.state.mission_dashboard_command_win = nil
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
  return true
end

function M:open_command_sink()
  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions-command",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    return false
  end

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, {
    relative = "editor",
    style = "minimal",
    border = "none",
    width = 1,
    height = 1,
    col = vim.o.columns + 1,
    row = vim.o.lines + 1,
    zindex = 1,
  })
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    return false
  end

  self.state.mission_dashboard_command_buf = bufnr
  self.state.mission_dashboard_command_win = win
  self.ui.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
  })
  self:bind_dashboard_commands(bufnr)
  return true
end

function M:open_selected()
  local item = self:selected_item()
  if not item then
    return false
  end
  local entry = item.kind == "role" and item.entry
    or item.kind == "mission" and item.mission and item.mission.roles and item.mission.roles[1]
    or nil
  if not entry then
    return false
  end
  self:close_dashboard()
  return self.open_saved_workspace(entry.name or entry.safe_name, entry.project_root)
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
          self:open_dashboard()
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

function M:run_action(action, target)
  local workspace = self.state.mission_dashboard_action_workspace or target
  if action == "open_workspace" then
    workspace = workspace or self:selected_role_workspace_or_notify()
    if not workspace then
      return false
    end
    self:close_action_palette()
    return self:open_role_workspace(workspace)
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

  local mission = self.state.mission_dashboard_action_mission or target or self:selected_mission_name_or_notify()
  if not mission then
    return false
  end

  if action == "edit_objective" then
    self:close_action_palette()
    return self:edit_selected_mission(mission)
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
  return self:run_action(action_item.action, self.state.mission_dashboard_action_mission)
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
  self:close_dashboard()
  return self.open_saved_workspace(entry.name or entry.safe_name, entry.project_root)
end

function M:delete_role_workspace(entry)
  if type(entry) ~= "table" then
    return false
  end
  local label = entry.name or entry.safe_name or "workspace"
  local choice = vim.fn.confirm("Delete Codux workspace " .. tostring(label) .. "?", "&Yes\n&No", 2)
  if choice == 1 then
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
  self.set_buffer_keymap(bufnr, "n", "<CR>", function()
    return self:open_selected()
  end, "Open Codux Mission Role")
  self.set_buffer_keymap(bufnr, "n", "m", function()
    return self:open_action_palette()
  end, "Open Codux Mission Menu")
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
  self.set_buffer_keymap(bufnr, "n", "r", function()
    return self:refresh_dashboard()
  end, "Refresh Codux Missions")
end

function M:open_dashboard()
  self:close_dashboard()
  local root = self.project_root()
  local lines, items, selectable_rows, best_match_row = self:dashboard_lines(root)
  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions",
    modifiable = false,
  })
  if not bufnr then
    self.notify("Failed to create Codux missions dashboard", vim.log.levels.ERROR)
    return false
  end

  self.ui.set_lines(bufnr, lines, { modifiable = true })
  self:highlight_dashboard(bufnr, lines, items)
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:dashboard_config(#lines))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux missions dashboard", vim.log.levels.ERROR)
    return false
  end
  self.ui.set_window_options(win, {
    cursorline = true,
    wrap = false,
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

  self:bind_dashboard_commands(bufnr)
  self:open_command_sink()
  if #selectable_rows > 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { selectable_rows[1], 0 })
  end
  vim.schedule(function()
    if self.is_valid_win(self.state.mission_dashboard_win) and self.is_loaded_buf(self.state.mission_dashboard_buf) then
      self:open_search_input()
    end
  end)
  return true
end

return M
