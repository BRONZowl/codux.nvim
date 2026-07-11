local M = {}

local text = require("codux.text")

local COMMAND_ITEMS = {
  { key = "Tab", label = "search" },
  { key = "m", label = "menu" },
  { key = "n", label = "new" },
  { key = "c", label = "cleanup" },
  { key = "h", label = "doctor" },
  { key = "<C-o>", label = "control" },
}

local ROLE_TABLE_MAX_WIDTH = 112
local ROLE_TABLE_GAP = "  "
local ROW_LEFT_OF_TABLE = 2

local function entry_key(entry)
  entry = type(entry) == "table" and entry or {}
  return tostring(entry.safe_name or entry.name or entry.mission_role or "")
end

local function pluralize(count, singular, plural)
  return tostring(count) .. " " .. (count == 1 and singular or plural)
end

function M.command_items()
  return COMMAND_ITEMS
end

function M.center_display_line(display, value, width)
  display = type(display) == "table" and display or text
  value = tostring(value or "")
  width = tonumber(width) or 0
  local display_width = type(display.display_width) == "function" and display.display_width(value) or text.display_width(value)
  local padding = math.max(0, math.floor((width - display_width) / 2))
  return string.rep(" ", padding) .. value
end

function M.role_table_width(dashboard_width)
  dashboard_width = math.max(1, tonumber(dashboard_width) or 80)
  return math.min(dashboard_width, ROLE_TABLE_MAX_WIDTH)
end

function M.role_column_widths(dashboard_width)
  local table_width = M.role_table_width(dashboard_width)
  local columns = {
    role = 9,
    status = 8,
    mode = 7,
    profile = 13,
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
    + (#ROLE_TABLE_GAP * 8)
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

function M.role_table_line(workspace_ui, columns, values)
  workspace_ui = type(workspace_ui) == "table" and workspace_ui or text
  columns = type(columns) == "table" and columns or M.role_column_widths(80)
  values = type(values) == "table" and values or {}
  return table.concat({
    workspace_ui.pad_display_right(values.role, columns.role),
    ROLE_TABLE_GAP,
    workspace_ui.pad_display_right(values.status, columns.status),
    ROLE_TABLE_GAP,
    workspace_ui.pad_display_right(values.mode, columns.mode),
    ROLE_TABLE_GAP,
    workspace_ui.pad_display_right(values.profile, columns.profile),
    ROLE_TABLE_GAP,
    workspace_ui.pad_display_right(values.age, columns.age),
    ROLE_TABLE_GAP,
    workspace_ui.pad_display_right(values.review, columns.review),
    ROLE_TABLE_GAP,
    workspace_ui.pad_display_right(values.branch, columns.branch),
    ROLE_TABLE_GAP,
    workspace_ui.pad_display_right(values.cleanup, columns.cleanup),
    ROLE_TABLE_GAP,
    workspace_ui.pad_display_right(values.target, columns.target),
  })
end

function M.mission_line(controller, mission, counts, status, dashboard_width)
  local workspace_ui = controller.workspace_ui
  local right = workspace_ui.pad_display_right(status, 8) .. "  " .. pluralize(counts.total, "role", "roles")
  local row_width = M.role_table_width(dashboard_width)
  local name_width = math.min(34, math.max(16, row_width - workspace_ui.display_width(right) - 1))
  local mission_name = workspace_ui.pad_display_right(tostring(mission.name or mission.mission_id), name_width)
  local table_indent = math.max(0, math.floor(((tonumber(dashboard_width) or 0) - row_width) / 2))
  local padding = math.max(0, table_indent - ROW_LEFT_OF_TABLE)
  return string.rep(" ", padding) .. mission_name .. " " .. right
end

function M.mission_focus_line(controller, mission, dashboard_width)
  local preview = controller.mission.focus_packet_preview(type(mission) == "table" and mission.focus_packet or nil)
  if preview == "" then
    return nil
  end

  local width = math.max(20, tonumber(dashboard_width) or 80)
  local line = "focus: " .. preview
  return M.center_display_line(controller.workspace_ui, controller.workspace_ui.truncate_display_tail(line, width), width)
end

function M.role_header_line(controller, dashboard_width)
  local columns = M.role_column_widths(dashboard_width)
  return M.center_display_line(
    controller.workspace_ui,
    M.role_table_line(controller.workspace_ui, columns, {
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

function M.role_line(controller, entry, dashboard_width, now, dirty_by_role)
  local role = entry.mission_role or entry.name or entry.safe_name
  local status = entry.status or "inactive"
  local mode = controller:mission_mode_label(entry)
  local profile = controller:permission_profile_label(entry)
  local details = controller:mission_workspace_details(entry, dirty_by_role, now)
  local columns = M.role_column_widths(dashboard_width)
  local target = type(entry.target_path) == "string" and entry.target_path ~= ""
      and vim.fn.fnamemodify(entry.target_path, ":t")
    or "none"
  return M.center_display_line(
    controller.workspace_ui,
    M.role_table_line(controller.workspace_ui, columns, {
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

function M.row_highlight_range(line)
  line = tostring(line or "")
  local start_col = line:find("%S")
  if not start_col then
    return 0, 0
  end
  return start_col - 1, #line
end

function M.command_lines(controller, dashboard_width)
  local width = math.max(40, tonumber(dashboard_width) or 80)
  local parts = {}
  for _, item in ipairs(COMMAND_ITEMS) do
    table.insert(parts, item.key .. " " .. item.label)
  end
  local line = controller.workspace_ui.truncate_display_tail(table.concat(parts, " "), width)
  return { M.center_display_line(controller.workspace_ui, line, width) }
end

function M.token_usage_line(controller, dashboard_width)
  local provider = nil
  if type(controller.dashboard_token_agent_provider) == "function" then
    provider = controller:dashboard_token_agent_provider()
  end
  local usage
  if provider ~= nil and type(controller.token_usage_label) == "function" then
    usage = tostring(controller.token_usage_label(provider) or "")
  else
    usage = tostring(controller.token_usage_label and controller.token_usage_label() or "")
  end
  if usage == "" then
    return nil
  end
  return M.center_display_line(controller.workspace_ui, usage, dashboard_width)
end

function M.dispatch_status_line(controller, dashboard_width)
  local last = type(controller.state) == "table" and controller.state.mission_dashboard_last_dispatch or nil
  if type(last) ~= "table" then
    return nil
  end
  local processed = tonumber(last.processed) or 0
  if processed <= 0 and (tonumber(last.failed) or 0) <= 0 then
    return nil
  end
  local label = string.format(
    "dispatch | %d ok | %d failed%s",
    tonumber(last.succeeded) or 0,
    tonumber(last.failed) or 0,
    type(last.mission) == "string" and last.mission ~= "" and (" | " .. last.mission) or ""
  )
  return M.center_display_line(controller.workspace_ui, label, dashboard_width)
end

--- Codex labels use "usage |", Grok labels use "quota |" (may be centered with padding).
function M.is_token_usage_line(line)
  line = tostring(line or ""):match("^%s*(.-)%s*$") or ""
  return line:find("usage | ", 1, true) ~= nil or line:find("quota | ", 1, true) ~= nil
end

function M.min_height_for_lines(lines)
  for _, line in ipairs(lines or {}) do
    if M.is_token_usage_line(line) then
      return 2
    end
  end
  return 1
end

function M.lines(controller, root, opts)
  opts = type(opts) == "table" and opts or {}
  local all_missions, error_message = controller:missions_for_root(root)
  if error_message then
    return { error_message }, {}, {}
  end
  local query = tostring(opts.query or "")
  local missions = controller:filter_missions(all_missions, query)
  local dashboard_width = tonumber(opts.dashboard_width) or controller:window_width() or controller:dashboard_config(1).width
  local now = controller:dashboard_now(opts)
  local lines = {}
  local items = {}
  local selectable_rows = {}
  local best_match_row = nil
  if #all_missions == 0 then
    local residue = nil
    if type(controller.mission_residue_for_root) == "function" then
      residue = controller:mission_residue_for_root(root)
    end
    residue = type(residue) == "table" and residue or {}
    local residue_count = tonumber(residue.count) or 0
    local empty_buckets = type(residue.empty_project_buckets) == "table" and #residue.empty_project_buckets or 0
    local leftover_dirs = type(residue.leftover_directories) == "table" and #residue.leftover_directories or 0
    if residue_count == 0 then
      return { M.center_display_line(controller.workspace_ui, "No Codux missions", dashboard_width) },
        items,
        selectable_rows,
        nil,
        0
    end

    return {
      M.center_display_line(controller.workspace_ui, "No Codux missions", dashboard_width),
      "",
      M.center_display_line(controller.workspace_ui, "Stale Mission Control residue found", dashboard_width),
      M.center_display_line(
        controller.workspace_ui,
        tostring(empty_buckets) .. " empty state buckets | " .. tostring(leftover_dirs) .. " leftover directories",
        dashboard_width
      ),
      M.center_display_line(controller.workspace_ui, "c cleanup empty residue | n create mission", dashboard_width),
    }, items, selectable_rows, nil, 0
  end
  if query ~= "" and #missions == 0 then
    return { M.center_display_line(controller.workspace_ui, "No matching Codux missions", dashboard_width) },
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
    local counts = controller.mission.status_counts(mission)
    total_roles = total_roles + counts.total
    total_active = total_active + counts.active
    total_question = total_question + counts.question
    total_idle = total_idle + counts.idle
  end

  table.insert(
    lines,
    M.center_display_line(
      controller.workspace_ui,
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
  local token_usage_line = M.token_usage_line(controller, dashboard_width)
  if token_usage_line then
    table.insert(lines, token_usage_line)
  end
  local dispatch_line = M.dispatch_status_line(controller, dashboard_width)
  if dispatch_line then
    table.insert(lines, dispatch_line)
  end

  for _, mission in ipairs(missions) do
    table.insert(lines, "")
    local counts = controller.mission.status_counts(mission)
    local status = controller.mission.status_label(mission)
    table.insert(lines, M.mission_line(controller, mission, counts, status, dashboard_width))
    items[#lines] = { kind = "mission", mission = mission }
    table.insert(selectable_rows, #lines)
    if query ~= "" and not best_match_row and mission._codux_match_kind == "mission" then
      best_match_row = #lines
    end
    local focus_line = M.mission_focus_line(controller, mission, dashboard_width)
    if focus_line then
      table.insert(lines, focus_line)
    end
    table.insert(lines, M.role_header_line(controller, dashboard_width))
    local dirty_by_role = controller:mission_dirty_status_by_role(root, mission, now)
    for _, entry in ipairs(mission.roles) do
      local line = M.role_line(controller, entry, dashboard_width, now, dirty_by_role)
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

function M.highlight(controller, bufnr, lines, items)
  if vim.api and type(vim.api.nvim_set_hl) == "function" then
    pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyUsage", { fg = "#8b949e" })
  end
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, controller.namespace, 0, -1)
  pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "Comment", 0, 0, -1)

  for index, line in ipairs(lines) do
    local item = items[index]
    if line == "Commands" then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "WhichKeyDesc", index - 1, 0, -1)
    elseif M.is_token_usage_line(line) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "CoduxWhichKeyUsage", index - 1, 0, -1)
    elseif line:find("^%s+Tab%s", 1, false) or line:find("^%s+O%s", 1, false) or line:find("^%s+n%s", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "Comment", index - 1, 0, -1)
    elseif line:find("^Output%s%s", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "WhichKeyDesc", index - 1, 0, 6)
      pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "Comment", index - 1, 6, -1)
    elseif item and item.kind == "mission" and not line:find("^%s+objective", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "WhichKey", index - 1, 0, -1)
    elseif item and item.kind == "mission" then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "Comment", index - 1, 0, -1)
    elseif line:find("^%s*role%s+", 1, false) then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "Identifier", index - 1, 0, -1)
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
          controller.namespace,
          group,
          index - 1,
          status_start - 1,
          status_start - 1 + #status
        )
      end
    end
  end

  local has_selected_row = controller.state.mission_dashboard_selected_row ~= nil
  local selected_row = controller.state.mission_dashboard_selected_row or controller.state.mission_dashboard_best_match_row
  if selected_row then
    local group = has_selected_row and "IncSearch" or "Visual"
    local start_col, end_col = M.row_highlight_range(lines[selected_row])
    local ok = type(vim.api.nvim_buf_set_extmark) == "function"
      and pcall(vim.api.nvim_buf_set_extmark, bufnr, controller.namespace, selected_row - 1, start_col, {
        end_col = end_col,
        hl_group = group,
        hl_eol = false,
      })
    if not ok then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, group, selected_row - 1, start_col, end_col)
    end
  end
end

return M
