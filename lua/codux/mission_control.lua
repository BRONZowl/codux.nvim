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
    update_mission_objective = type(opts.update_mission_objective) == "function" and opts.update_mission_objective
      or noop,
    delete_mission = type(opts.delete_mission) == "function" and opts.delete_mission or noop,
    workspace_entries_for_project = type(opts.workspace_entries_for_project) == "function"
        and opts.workspace_entries_for_project
      or function()
        return {}
      end,
    open_saved_workspace = type(opts.open_saved_workspace) == "function" and opts.open_saved_workspace or noop,
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

function M:objective_editor_config(line_count)
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
    title = " Codux Mission Objective ",
    title_pos = "center",
    footer = " Ctrl-s/:w preview | Ctrl-q cancel ",
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
    title = " codux missions ",
    title_pos = "center",
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
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:objective_editor_config(#objective_lines))
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
    else
      local mission, plan_error = self.mission.plan(mission_name, objective)
      if not mission then
        self.notify(plan_error, vim.log.levels.ERROR)
        return
      end
      saved = true
      close_editor()
      self:open_preview(mission)
      return
    end

    saved = true
    close_editor()
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

local function status_counts(roles)
  local counts = {
    active = 0,
    idle = 0,
    inactive = 0,
    question = 0,
  }

  for _, entry in ipairs(type(roles) == "table" and roles or {}) do
    local status = entry.status or "inactive"
    if counts[status] == nil then
      status = "inactive"
    end
    counts[status] = counts[status] + 1
  end

  return counts
end

local function mission_status(counts)
  if counts.question > 0 then
    return "question"
  end
  if counts.active > 0 then
    return "active"
  end
  if counts.idle > 0 then
    return "idle"
  end
  return "inactive"
end

function M:dashboard_lines(root)
  local entries, error_message = self.workspace_entries_for_project(root)
  if error_message then
    return { error_message }, {}
  end

  local missions = self.mission.group_entries(entries)
  local lines = {
    "CODUX MISSION CONTROL",
    "Project: " .. tostring(root or ""),
    "Keys: <CR> open  e edit objective  d delete mission  n new  r refresh  q close",
    "",
  }
  local items = {}
  if #missions == 0 then
    table.insert(lines, "No Codux missions yet")
    table.insert(lines, "Create one with n or :CoduxMissionCreate")
    return lines, items
  end

  for mission_index, mission in ipairs(missions) do
    if mission_index > 1 then
      table.insert(lines, "")
    end
    local counts = status_counts(mission.roles)
    local line = string.format(
      "%02d  %-30s %-8s roles:%d  active:%d  question:%d",
      mission_index,
      tostring(mission.name or mission.mission_id),
      mission_status(counts),
      #mission.roles,
      counts.active,
      counts.question
    )
    table.insert(lines, line)
    items[#lines] = {
      type = "mission",
      mission = mission,
    }
    table.insert(lines, "    Objective: " .. self.mission.objective_preview(mission.objective, 94))
    items[#lines] = {
      type = "mission",
      mission = mission,
    }
    table.insert(lines, "    ROLE         STATUS    MODE   AGE   TARGET")
    for _, entry in ipairs(mission.roles) do
      local role = entry.mission_role or entry.name or entry.safe_name
      local status = entry.status or "inactive"
      local mode = self.workspace_ui.manager_mode_label(entry)
      local age = self.workspace_ui.relative_age_label(self.workspace_ui.session_timestamp(entry))
      local target = type(entry.target_path) == "string" and entry.target_path ~= "" and vim.fn.fnamemodify(entry.target_path, ":t") or ""
      local role_line = string.format("    %-12s %-8s %-6s %-5s %s", role, status, mode, age, target)
      table.insert(lines, role_line)
      items[#lines] = {
        type = "role",
        mission = mission,
        entry = entry,
      }
    end
  end

  return lines, items
end

function M:decorate_dashboard(bufnr, lines, items)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, self.namespace, 0, -1)
  for index, line in ipairs(lines) do
    local item = items[index]
    local highlight = nil
    if index == 1 then
      highlight = "Title"
    elseif type(item) == "table" and item.type == "mission" then
      highlight = "Identifier"
    elseif type(item) == "table" and item.type == "role" then
      if line:find("question", 1, true) then
        highlight = "WarningMsg"
      elseif line:find("active", 1, true) then
        highlight = "Statement"
      else
        highlight = "Comment"
      end
    elseif line:find("^Keys:") then
      highlight = "Comment"
    end
    if highlight then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, self.namespace, index - 1, 0, {
        end_col = #line,
        hl_group = highlight,
      })
    end
  end
  return true
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
  self:decorate_dashboard(bufnr, lines, items)
  self.state.mission_dashboard_buf = bufnr
  self.state.mission_dashboard_win = win
  self.state.mission_dashboard_items = items

  local function render_dashboard()
    lines, items = self:dashboard_lines(root)
    self.ui.set_lines(bufnr, lines, { modifiable = true })
    self:decorate_dashboard(bufnr, lines, items)
    self.state.mission_dashboard_items = items
    return true
  end

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
    local entry = type(item) == "table" and item.entry or nil
    if not entry and type(item) == "table" and type(item.mission) == "table" and type(item.mission.roles) == "table" then
      entry = item.mission.roles[1]
    end
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
    if type(item) == "table" then
      return item.mission
    end
    return nil
  end

  local function edit_selected_mission()
    local mission = selected_mission()
    if not mission then
      self.notify("Select a Codux mission to edit", vim.log.levels.WARN)
      return false
    end
    close_dashboard()
    return self:open_objective_editor(mission.name, mission.objective, {
      on_save = function(_, objective)
        local ok, error_message = self.update_mission_objective(root, mission.mission_id, objective)
        if not ok then
          self.notify(error_message or "Failed to update Codux mission", vim.log.levels.ERROR)
          return false
        end
        self.notify("Updated Codux mission objective for " .. tostring(mission.name))
        self:open_dashboard()
        return true
      end,
    })
  end

  local function delete_selected_mission()
    local mission = selected_mission()
    if not mission then
      self.notify("Select a Codux mission to delete", vim.log.levels.WARN)
      return false
    end
    local choice = vim.fn.confirm(
      "Delete Codux mission " .. tostring(mission.name) .. " and all role workspaces?",
      "&Yes\n&No",
      2
    )
    if choice ~= 1 then
      return false
    end
    close_dashboard()
    local ok, error_message = self.delete_mission(root, mission.mission_id)
    if not ok then
      self.notify(error_message or "Failed to delete Codux mission", vim.log.levels.ERROR)
      return false
    end
    self.notify("Deleted Codux mission " .. tostring(mission.name))
    self:open_dashboard()
    return true
  end

  local function create_new_mission()
    close_dashboard()
    return self:open_prompt()
  end

  self.set_buffer_keymap(bufnr, "n", "<CR>", open_selected, "Open Codux Mission Role")
  self.set_buffer_keymap(bufnr, "n", "e", edit_selected_mission, "Edit Codux Mission Objective")
  self.set_buffer_keymap(bufnr, "n", "d", delete_selected_mission, "Delete Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "n", create_new_mission, "Create Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "r", render_dashboard, "Refresh Codux Missions")
  self.bind_close_keys(bufnr, close_dashboard, "Close Codux Missions", "n", { escape = true, q = true })
  return true
end

return M
