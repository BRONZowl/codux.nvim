local M = {}

function M.trim(value)
  local trimmed = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return trimmed
end

function M.display_width(value)
  value = tostring(value or "")
  if vim.fn and type(vim.fn.strdisplaywidth) == "function" then
    local ok, width = pcall(vim.fn.strdisplaywidth, value)
    if ok and type(width) == "number" then
      return width
    end
  end

  return #value
end

function M.truncate_display_tail(text, max_width)
  text = tostring(text or "")
  max_width = tonumber(max_width) or 0

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
  local char_count = vim.fn and type(vim.fn.strchars) == "function" and vim.fn.strchars(text) or #text
  local suffix = ""

  for start = char_count - 1, 0, -1 do
    local candidate
    if vim.fn and type(vim.fn.strcharpart) == "function" then
      candidate = vim.fn.strcharpart(text, start)
    else
      candidate = text:sub(start + 1)
    end
    if M.display_width(candidate) > suffix_width then
      break
    end
    suffix = candidate
  end

  return "..." .. suffix
end

function M.pad_display_right(text, width)
  text = M.truncate_display_tail(text, width)
  return text .. string.rep(" ", math.max(0, (tonumber(width) or 0) - M.display_width(text)))
end

function M.center_display_line(text, width)
  text = tostring(text or "")
  width = tonumber(width) or 0
  local padding = math.max(0, math.floor((width - M.display_width(text)) / 2))
  return string.rep(" ", padding) .. text
end

return M
