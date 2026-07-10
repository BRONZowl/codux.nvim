package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

if type(vim) ~= "table" then
  local function deepcopy(value)
    if type(value) ~= "table" then
      return value
    end
    local copy = {}
    for key, item in pairs(value) do
      copy[key] = deepcopy(item)
    end
    return copy
  end

  local function tbl_deep_extend(behavior, ...)
    local values = { ... }
    local result = {}
    for _, value in ipairs(values) do
      if type(value) == "table" then
        for key, item in pairs(value) do
          if behavior == "force" or result[key] == nil then
            if type(item) == "table" and type(result[key]) == "table" then
              result[key] = tbl_deep_extend(behavior, result[key], item)
            else
              result[key] = deepcopy(item)
            end
          end
        end
      end
    end
    return result
  end

  vim = {
    deepcopy = deepcopy,
    env = {},
    list_extend = function(target, values)
      target = type(target) == "table" and target or {}
      for _, value in ipairs(type(values) == "table" and values or {}) do
        table.insert(target, value)
      end
      return target
    end,
    tbl_deep_extend = tbl_deep_extend,
    tbl_isempty = function(value)
      return type(value) ~= "table" or next(value) == nil
    end,
    split = function(value, separator)
      value = tostring(value or "")
      separator = tostring(separator or "")
      if separator == "" then
        return { value }
      end
      local parts = {}
      local start = 1
      while true do
        local found = value:find(separator, start, true)
        if not found then
          table.insert(parts, value:sub(start))
          break
        end
        table.insert(parts, value:sub(start, found - 1))
        start = found + #separator
      end
      return parts
    end,
    o = {
      columns = 120,
      lines = 40,
      cmdheight = 1,
    },
    fn = {
      confirm = function()
        return 1
      end,
      expand = function(value)
        return tostring(value or "")
      end,
      fnamemodify = function(value, modifier)
        if modifier == ":t" then
          return tostring(value or ""):match("[^/]+$") or tostring(value or "")
        end
        if modifier == ":h" then
          return tostring(value or ""):match("(.+)/[^/]*$") or "."
        end
        return tostring(value or "")
      end,
      readfile = function()
        return {}
      end,
      mkdir = function()
        return 1
      end,
      shellescape = function(value)
        return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
      end,
      strcharpart = function(value, start, length)
        value = tostring(value or "")
        start = tonumber(start) or 0
        if length == nil then
          return value:sub(start + 1)
        end
        return value:sub(start + 1, start + length)
      end,
      strchars = function(value)
        return #tostring(value or "")
      end,
      strdisplaywidth = function(value)
        return #tostring(value or "")
      end,
      writefile = function()
        return 0
      end,
    },
    log = {
      levels = {
        ERROR = 4,
        WARN = 3,
      },
    },
    loop = {
      cwd = function()
        return "/repo"
      end,
    },
  }
end

local M = {}

function M.assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function M.assert_nil(actual, message)
  if actual ~= nil then
    error((message or "assertion failed") .. ": expected nil, got " .. tostring(actual), 2)
  end
end

function M.assert_true(actual, message)
  if actual ~= true then
    error((message or "assertion failed") .. ": expected true, got " .. tostring(actual), 2)
  end
end

function M.assert_false(actual, message)
  if actual ~= false then
    error((message or "assertion failed") .. ": expected false, got " .. tostring(actual), 2)
  end
end

function M.assert_contains(value, expected, message)
  if not tostring(value or ""):find(expected, 1, true) then
    error((message or "assertion failed") .. ": expected " .. tostring(value) .. " to contain " .. tostring(expected), 2)
  end
end

function M.assert_table_equal(actual, expected, message)
  if type(actual) ~= "table" then
    error((message or "assertion failed") .. ": expected table, got " .. type(actual), 2)
  end
  M.assert_equal(#actual, #expected, message)
  for index, expected_value in ipairs(expected) do
    M.assert_equal(actual[index], expected_value, (message or "assertion failed") .. " at index " .. tostring(index))
  end
end

function M.with_stubs(stubs, callback)
  stubs = type(stubs) == "table" and stubs or {}
  callback = type(callback) == "function" and callback or function() end
  local originals = {}
  for index, stub in ipairs(stubs) do
    originals[index] = stub.target[stub.key]
    stub.target[stub.key] = stub.value
  end

  local ok, result = pcall(callback)
  for index = #stubs, 1, -1 do
    local stub = stubs[index]
    stub.target[stub.key] = originals[index]
  end
  if not ok then
    error(result, 0)
  end
  return result
end

function M.with_vim_api(stubs, callback)
  local old_api = vim.api
  vim.api = vim.api or {}
  local normalized = {}
  for key, value in pairs(type(stubs) == "table" and stubs or {}) do
    table.insert(normalized, { target = vim.api, key = key, value = value })
  end

  local ok, result = pcall(function()
    return M.with_stubs(normalized, callback)
  end)
  vim.api = old_api
  if not ok then
    error(result, 0)
  end
  return result
end

return M
