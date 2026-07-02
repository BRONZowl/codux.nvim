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
    is_loaded_buf = type(opts.is_loaded_buf) == "function" and opts.is_loaded_buf or ui.is_loaded_buf,
    notify = type(opts.notify) == "function" and opts.notify or noop,
    create_mission = type(opts.create_mission) == "function" and opts.create_mission or noop,
    workspace_entries_for_project = type(opts.workspace_entries_for_project) == "function"
        and opts.workspace_entries_for_project
      or function()
        return {}
      end,
    open_saved_workspace = type(opts.open_saved_workspace) == "function" and opts.open_saved_workspace or noop,
    update_mission_objective = type(opts.update_mission_objective) == "function"
        and opts.update_mission_objective
      or noop,
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
    footer = " Enter open | e objective | d delete | n new | r refresh | q close ",
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

function M:dashboard_lines(root)
  local entries, error_message = self.workspace_entries_for_project(root)
  if error_message then
    return { error_message }, {}
  end

  local missions = self.mission.group_entries(entries)
  local lines = {
    "Mission Control",
  }
  local items = {}
  if #missions == 0 then
    return { "Mission Control", "", "No Codux missions" }, items
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
    end
  end

  return lines, items
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

  if opts.confirm ~= false then
    local choice = vim.fn.confirm("Delete Codux mission " .. tostring(mission.name or mission.mission_id) .. "?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return false
    end
  end

  return self.delete_mission(mission.name or mission.mission_id, root)
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
end

function M:open_dashboard()
  local root = self.project_root()
  local lines, items = self:dashboard_lines(root)
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
  self.state.mission_dashboard_items = items

  local function close_dashboard()
    self.ui.close_window(win)
    self.ui.delete_buffer(bufnr)
    self.state.mission_dashboard_buf = nil
    self.state.mission_dashboard_win = nil
    self.state.mission_dashboard_items = {}
  end

  local function open_selected()
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
    if not ok then
      return false
    end
    local item = items[cursor[1]]
    if not item then
      return false
    end
    local entry = item.kind == "role" and item.entry
      or item.kind == "mission" and item.mission and item.mission.roles and item.mission.roles[1]
      or nil
    if not entry then
      return false
    end
    close_dashboard()
    return self.open_saved_workspace(entry.name or entry.safe_name, entry.project_root)
  end

  local function selected_mission()
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
    if not ok then
      return nil
    end
    local item = items[cursor[1]]
    if not item then
      return nil
    end
    return item.mission
  end

  local function edit_selected_mission()
    local mission = selected_mission()
    if not mission then
      self.notify("No Codux mission selected", vim.log.levels.WARN)
      return false
    end
    close_dashboard()
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

  local function delete_selected_mission()
    local mission = selected_mission()
    if not mission then
      self.notify("No Codux mission selected", vim.log.levels.WARN)
      return false
    end
    local choice = vim.fn.confirm("Delete Codux mission " .. tostring(mission.name or mission.mission_id) .. "?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return false
    end
    close_dashboard()
    return self.delete_mission(mission.name or mission.mission_id, root)
  end

  local function refresh_dashboard()
    close_dashboard()
    return self:open_dashboard()
  end

  local function create_new_mission()
    close_dashboard()
    return self:open_prompt()
  end

  self.set_buffer_keymap(bufnr, "n", "<CR>", open_selected, "Open Codux Mission Role")
  self.set_buffer_keymap(bufnr, "n", "e", edit_selected_mission, "Edit Codux Mission Objective")
  self.set_buffer_keymap(bufnr, "n", "d", delete_selected_mission, "Delete Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "n", create_new_mission, "Create Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "r", refresh_dashboard, "Refresh Codux Missions")
  self.bind_close_keys(bufnr, close_dashboard, "Close Codux Missions", "n", { escape = true, q = true })
  return true
end

return M
