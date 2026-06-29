local M = {}

M.MANAGER_NAME_WIDTH = 28
M.MANAGER_STATUS_WIDTH = 8
M.MANAGER_MODE_WIDTH = 4
M.MANAGER_GAP = "  "

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
  local fixed_width = M.MANAGER_STATUS_WIDTH + M.MANAGER_MODE_WIDTH + (gap_width * 3)
  local available = math.max(1, width - fixed_width)
  local name_width = math.min(M.MANAGER_NAME_WIDTH, math.max(12, available - 8))
  local target_width = math.max(0, available - name_width)

  return name_width, target_width
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
  local target = type(entry.target_path) == "string" and entry.target_path ~= "" and vim.fn.fnamemodify(entry.target_path, ":t") or ""
  local name_width, target_width = M.manager_column_widths(width)

  return table.concat({
    M.pad_display_right(entry.name or "", name_width),
    M.MANAGER_GAP,
    M.pad_display_right(status, M.MANAGER_STATUS_WIDTH),
    M.MANAGER_GAP,
    M.pad_display_right(mode, M.MANAGER_MODE_WIDTH),
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
    "target",
  })
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
    table.insert(parts, tostring(segment.key or "") .. " " .. tostring(segment.desc or ""))
    if index < #segments then
      table.insert(parts, "  ")
    end
  end

  return table.concat(parts, "")
end

function M.manager_footer_segments()
  return {
    { key = "s", desc = "search" },
    { key = "enter", desc = "open" },
    { key = "r", desc = "rename" },
    { key = "x", desc = "close" },
    { key = "d", desc = "delete" },
    { key = "h", desc = "doctor" },
    { key = "<c-q>", desc = "close" },
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
