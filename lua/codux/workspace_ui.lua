local M = {}

M.MANAGER_NAME_WIDTH = 28
M.MANAGER_STATUS_WIDTH = 8
M.MANAGER_MODE_WIDTH = 4
M.MANAGER_PROFILE_WIDTH = 7
M.MANAGER_BRANCH_WIDTH = 12
M.MANAGER_AGE_WIDTH = 4
M.MANAGER_GAP = "  "

M.STATUS_ORDER = {
  question = 1,
  active = 2,
  idle = 3,
  inactive = 4,
}

function M.display_width(text)
  local ok, width = pcall(vim.fn.strdisplaywidth, text or "")
  if ok and type(width) == "number" then
    return width
  end

  return #(text or "")
end

function M.truncate_display_tail(text, max_width)
  text = tostring(text or "")

  if max_width <= 0 then
    return ""
  end

  if M.display_width(text) <= max_width then
    return text
  end

  if max_width <= 3 then
    return string.rep(".", max_width)
  end

  local suffix_width = max_width - 3
  local char_count = vim.fn.strchars(text)
  local suffix = ""

  for start = char_count - 1, 0, -1 do
    local candidate = vim.fn.strcharpart(text, start)
    if M.display_width(candidate) > suffix_width then
      break
    end
    suffix = candidate
  end

  return "..." .. suffix
end

function M.pad_display_right(text, width)
  text = M.truncate_display_tail(text, width)
  return text .. string.rep(" ", math.max(0, width - M.display_width(text)))
end

function M.manager_column_widths(width)
  width = tonumber(width) or 58
  local gap_width = M.display_width(M.MANAGER_GAP)
  local fixed_width = M.MANAGER_STATUS_WIDTH
    + M.MANAGER_MODE_WIDTH
    + M.MANAGER_PROFILE_WIDTH
    + M.MANAGER_BRANCH_WIDTH
    + M.MANAGER_AGE_WIDTH
    + (gap_width * 6)
  local available = math.max(1, width - fixed_width)
  local name_width = math.min(M.MANAGER_NAME_WIDTH, math.max(12, available - 10))
  local target_width = math.max(0, available - name_width)

  return name_width, target_width
end

function M.parse_timestamp(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end

  local year, month, day, hour, min, sec = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
  if not year then
    return nil
  end

  local local_epoch = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
    isdst = false,
  })
  local utc_as_local = os.time(os.date("!*t", local_epoch))
  local local_as_local = os.time(os.date("*t", local_epoch))
  return local_epoch + os.difftime(local_as_local, utc_as_local)
end

function M.relative_age_label(timestamp, now)
  local then_seconds = M.parse_timestamp(timestamp)
  if not then_seconds then
    return "--"
  end

  now = tonumber(now) or os.time()
  local elapsed = math.max(0, now - then_seconds)
  if elapsed < 60 then
    return "<1m"
  end
  if elapsed < 3600 then
    return tostring(math.floor(elapsed / 60)) .. "m"
  end
  if elapsed < 86400 then
    return tostring(math.floor(elapsed / 3600)) .. "h"
  end
  if elapsed < 604800 then
    return tostring(math.floor(elapsed / 86400)) .. "d"
  end
  if elapsed < 31536000 then
    return tostring(math.floor(elapsed / 604800)) .. "w"
  end
  return tostring(math.floor(elapsed / 31536000)) .. "y"
end

function M.activity_timestamp(entry)
  entry = type(entry) == "table" and entry or {}
  return entry.last_activity_at
    or entry.last_target_at
    or entry.last_opened_at
    or entry.codex_session_captured_at
    or entry.created_at
end

function M.session_timestamp(entry)
  entry = type(entry) == "table" and entry or {}
  return entry.created_at or entry.codex_session_captured_at
end

function M.timestamp_sort_value(value)
  return M.parse_timestamp(value) or 0
end

function M.status_rank(status)
  return M.STATUS_ORDER[status] or 99
end

function M.sort_entries(entries, sort_mode)
  entries = vim.deepcopy(type(entries) == "table" and entries or {})
  sort_mode = sort_mode or "status_recent"

  table.sort(entries, function(left, right)
    if sort_mode == "name" then
      return tostring(left.name):lower() < tostring(right.name):lower()
    end

    if sort_mode == "status_recent" then
      local left_status = M.status_rank(left.status)
      local right_status = M.status_rank(right.status)
      if left_status ~= right_status then
        return left_status < right_status
      end
    end

    local left_activity = M.timestamp_sort_value(M.activity_timestamp(left))
    local right_activity = M.timestamp_sort_value(M.activity_timestamp(right))
    if left_activity ~= right_activity then
      return left_activity > right_activity
    end

    return tostring(left.name):lower() < tostring(right.name):lower()
  end)

  return entries
end

function M.manager_mode_label(entry)
  entry = type(entry) == "table" and entry or {}
  if entry.status == "inactive" then
    return "--"
  end
  if entry.codex_mode == "execute" then
    return "exec"
  end
  if entry.codex_mode == "plan" then
    return "plan"
  end
  return "--"
end

function M.manager_line(entry, width)
  entry = type(entry) == "table" and entry or {}
  local status = entry.status or "inactive"
  local mode = M.manager_mode_label(entry)
  local profile = entry.permission_profile or "default"
  local branch = entry.git_branch or ""
  local age = M.relative_age_label(M.session_timestamp(entry))
  local target = type(entry.target_path) == "string" and entry.target_path ~= "" and vim.fn.fnamemodify(entry.target_path, ":t") or ""
  local name_width, target_width = M.manager_column_widths(width)

  return table.concat({
    M.pad_display_right(entry.name or "", name_width),
    M.MANAGER_GAP,
    M.pad_display_right(status, M.MANAGER_STATUS_WIDTH),
    M.MANAGER_GAP,
    M.pad_display_right(mode, M.MANAGER_MODE_WIDTH),
    M.MANAGER_GAP,
    M.pad_display_right(profile, M.MANAGER_PROFILE_WIDTH),
    M.MANAGER_GAP,
    M.pad_display_right(branch, M.MANAGER_BRANCH_WIDTH),
    M.MANAGER_GAP,
    M.pad_display_right(age, M.MANAGER_AGE_WIDTH),
    M.MANAGER_GAP,
    M.truncate_display_tail(target, target_width),
  })
end

function M.manager_header_line(width)
  local name_width = M.manager_column_widths(width)

  return table.concat({
    M.pad_display_right("workspace", name_width),
    M.MANAGER_GAP,
    M.pad_display_right("status", M.MANAGER_STATUS_WIDTH),
    M.MANAGER_GAP,
    M.pad_display_right("mode", M.MANAGER_MODE_WIDTH),
    M.MANAGER_GAP,
    M.pad_display_right("profile", M.MANAGER_PROFILE_WIDTH),
    M.MANAGER_GAP,
    M.pad_display_right("branch", M.MANAGER_BRANCH_WIDTH),
    M.MANAGER_GAP,
    M.pad_display_right("age", M.MANAGER_AGE_WIDTH),
    M.MANAGER_GAP,
    "target",
  })
end

function M.manager_action_items()
  return {
    { key = "r", action = "rename", label = "Rename Workspace" },
    { key = "e", action = "edit_instructions", label = "Edit Instructions" },
    { key = "x", action = "close_window", label = "Close Workspace" },
    { key = "X", action = "close_all_windows", label = "Close All Workspaces" },
    { key = "d", action = "delete", label = "Delete Workspace" },
  }
end

function M.manager_action_line(item, width)
  item = type(item) == "table" and item or {}
  width = tonumber(width) or 40
  local line = tostring(item.key or "") .. "  " .. tostring(item.label or "")
  return M.truncate_display_tail(line, width)
end

function M.fuzzy_workspace_score(value, query)
  value = tostring(value or "")
  query = tostring(query or "")
  if query == "" then
    return 0
  end

  local lower_value = value:lower()
  local lower_query = query:lower()
  if #lower_query <= 2 then
    if lower_value:find(lower_query, 1, true) ~= 1 then
      return nil
    end
    return #value - #query
  end

  local positions = {}
  local from = 1

  for index = 1, #lower_query do
    local char = lower_query:sub(index, index)
    local found = lower_value:find(char, from, true)
    if not found then
      return nil
    end
    table.insert(positions, found)
    from = found + 1
  end

  local gaps = 0
  local consecutive = 0
  for index = 2, #positions do
    local gap = positions[index] - positions[index - 1] - 1
    gaps = gaps + gap
    if gap == 0 then
      consecutive = consecutive + 1
    end
  end

  return (positions[1] * 4) + (gaps * 10) + (#value - #query) - (consecutive * 2)
end

function M.fuzzy_workspace_filter(entries, query)
  entries = type(entries) == "table" and entries or {}
  query = tostring(query or "")
  if query == "" then
    return entries
  end

  local scored = {}
  for _, entry in ipairs(entries) do
    local score = M.fuzzy_workspace_score(entry.name, query)
    if score then
      table.insert(scored, { entry = entry, score = score })
    end
  end

  table.sort(scored, function(left, right)
    if left.score == right.score then
      return tostring(left.entry.name):lower() < tostring(right.entry.name):lower()
    end
    return left.score < right.score
  end)

  local matches = {}
  for _, item in ipairs(scored) do
    table.insert(matches, item.entry)
  end
  return matches
end

function M.footer_line(segments)
  segments = type(segments) == "table" and segments or {}
  local parts = {}
  for index, segment in ipairs(segments) do
    local key = tostring(segment.key or "")
    local desc = tostring(segment.desc or "")
    table.insert(parts, desc ~= "" and (key .. " " .. desc) or key)
    if index < #segments then
      table.insert(parts, "  ")
    end
  end

  return table.concat(parts, "")
end

function M.manager_footer_segments(_state, width)
  local full = {
    { key = "tab", desc = "search/list" },
    { key = "j/k", desc = "move" },
    { key = "m", desc = "menu" },
    { key = "h", desc = "doctor" },
    { key = "enter", desc = "open" },
    { key = "<c-q>", desc = "close" },
  }

  width = tonumber(width)
  if not width or M.display_width(M.footer_line(full)) <= width then
    return full
  end

  return {
    { key = "tab", desc = "" },
    { key = "j/k", desc = "" },
    { key = "m", desc = "menu" },
    { key = "h", desc = "" },
    { key = "enter", desc = "" },
    { key = "<c-q>", desc = "" },
  }
end

function M.create_footer_segments()
  return {
    { key = "enter", desc = "create" },
    { key = "e", desc = "edit instruction" },
    { key = "<c-q>", desc = "cancel" },
  }
end

return M
