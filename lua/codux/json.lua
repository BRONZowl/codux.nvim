local M = {}

function M.encode(value)
  if vim.json and type(vim.json.encode) == "function" then
    return vim.json.encode(value)
  end
  if vim.fn and type(vim.fn.json_encode) == "function" then
    return vim.fn.json_encode(value)
  end
  return nil
end

--- Minimal pure-Lua JSON decoder for tests / environments without vim.json.
--- Supports objects, arrays, strings, numbers, booleans, and null.
local function pure_decode(str)
  local i = 1
  local s = tostring(str or "")

  local function peek()
    return s:sub(i, i)
  end

  local function skip_ws()
    local _, finish = s:find("^[ \t\r\n]*", i)
    i = (finish or (i - 1)) + 1
  end

  local parse_value

  local function parse_string()
    if peek() ~= '"' then
      return nil
    end
    i = i + 1
    local out = {}
    while i <= #s do
      local c = s:sub(i, i)
      if c == '"' then
        i = i + 1
        return table.concat(out)
      end
      if c == "\\" then
        local n = s:sub(i + 1, i + 1)
        local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        if n == "u" then
          local hex = s:sub(i + 2, i + 5)
          local code = tonumber(hex, 16)
          if not code then
            return nil
          end
          if code < 128 then
            table.insert(out, string.char(code))
          else
            -- Keep a placeholder for non-ASCII in pure-Lua path.
            table.insert(out, "?")
          end
          i = i + 6
        elseif map[n] then
          table.insert(out, map[n])
          i = i + 2
        else
          return nil
        end
      else
        table.insert(out, c)
        i = i + 1
      end
    end
    return nil
  end

  local function parse_number()
    local start = i
    if peek() == "-" then
      i = i + 1
    end
    if not s:sub(i, i):match("%d") then
      return nil
    end
    while s:sub(i, i):match("%d") do
      i = i + 1
    end
    if peek() == "." then
      i = i + 1
      if not s:sub(i, i):match("%d") then
        return nil
      end
      while s:sub(i, i):match("%d") do
        i = i + 1
      end
    end
    local exp = peek()
    if exp == "e" or exp == "E" then
      i = i + 1
      local sign = peek()
      if sign == "+" or sign == "-" then
        i = i + 1
      end
      if not s:sub(i, i):match("%d") then
        return nil
      end
      while s:sub(i, i):match("%d") do
        i = i + 1
      end
    end
    return tonumber(s:sub(start, i - 1))
  end

  local function parse_array()
    if peek() ~= "[" then
      return nil
    end
    i = i + 1
    skip_ws()
    local arr = {}
    if peek() == "]" then
      i = i + 1
      return arr
    end
    while true do
      local value = parse_value()
      if value == nil and peek() ~= "n" then
        -- allow explicit null via parse_value returning vim.NIL-like; use box
      end
      table.insert(arr, value)
      skip_ws()
      local c = peek()
      if c == "," then
        i = i + 1
        skip_ws()
      elseif c == "]" then
        i = i + 1
        return arr
      else
        return nil
      end
    end
  end

  local function parse_object()
    if peek() ~= "{" then
      return nil
    end
    i = i + 1
    skip_ws()
    local obj = {}
    if peek() == "}" then
      i = i + 1
      return obj
    end
    while true do
      skip_ws()
      local key = parse_string()
      if type(key) ~= "string" then
        return nil
      end
      skip_ws()
      if peek() ~= ":" then
        return nil
      end
      i = i + 1
      skip_ws()
      local value = parse_value()
      obj[key] = value
      skip_ws()
      local c = peek()
      if c == "," then
        i = i + 1
        skip_ws()
      elseif c == "}" then
        i = i + 1
        return obj
      else
        return nil
      end
    end
  end

  parse_value = function()
    skip_ws()
    local c = peek()
    if c == '"' then
      return parse_string()
    end
    if c == "{" then
      return parse_object()
    end
    if c == "[" then
      return parse_array()
    end
    if c == "t" and s:sub(i, i + 3) == "true" then
      i = i + 4
      return true
    end
    if c == "f" and s:sub(i, i + 4) == "false" then
      i = i + 5
      return false
    end
    if c == "n" and s:sub(i, i + 3) == "null" then
      i = i + 4
      return nil
    end
    if c == "-" or c:match("%d") then
      return parse_number()
    end
    return nil
  end

  local value = parse_value()
  skip_ws()
  if i <= #s then
    return nil
  end
  return value
end

function M.decode(value)
  local ok, decoded
  if vim.json and type(vim.json.decode) == "function" then
    ok, decoded = pcall(vim.json.decode, value)
    if ok then
      return decoded
    end
  end
  if vim.fn and type(vim.fn.json_decode) == "function" then
    ok, decoded = pcall(vim.fn.json_decode, value)
    if ok then
      return decoded
    end
  end
  ok, decoded = pcall(pure_decode, value)
  if ok then
    return decoded
  end
  return nil
end

return M
