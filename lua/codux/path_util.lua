local text_util = require("codux.text")

local M = {}

local trim = text_util.trim

function M.strip_trailing_slashes(value)
  value = tostring(value or "")
  while #value > 1 and value:sub(-1) == "/" do
    value = value:sub(1, -2)
  end
  return value
end

function M.path_join(...)
  local parts = {}
  for _, value in ipairs({ ... }) do
    value = tostring(value or "")
    if value ~= "" then
      table.insert(parts, value)
    end
  end
  return table.concat(parts, "/"):gsub("/+", "/")
end

function M.normalize_absolute_path(base, path)
  path = tostring(path or "")
  if path == "" then
    return nil
  end
  if path:sub(1, 1) ~= "/" then
    path = M.path_join(base, path)
  end

  local stack = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #stack > 0 then
        table.remove(stack)
      end
    elseif part ~= "." and part ~= "" then
      table.insert(stack, part)
    end
  end

  return "/" .. table.concat(stack, "/")
end

function M.normalize_relative_directory(value)
  value = trim(value)
  value = value:gsub("^%./+", "")
  value = value:gsub("/+$", "")
  return value
end

function M.starts_with_path(path, root)
  path = M.strip_trailing_slashes(path)
  root = M.strip_trailing_slashes(root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

function M.relative_path_escapes_root(value)
  value = M.normalize_relative_directory(value)
  return value == ".." or value:sub(1, 3) == "../" or value:find("/%.%./") ~= nil or value:sub(-3) == "/.."
end

function M.path_token(value)
  value = tostring(value or ""):gsub("[^%w_.-]+", "-"):gsub("-+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if value == "" then
    return "workspace"
  end
  return value:sub(1, 96)
end

function M.short_path_token(value, max_length)
  max_length = math.max(1, tonumber(max_length) or 32)
  return M.path_token(value):sub(1, max_length)
end

return M
