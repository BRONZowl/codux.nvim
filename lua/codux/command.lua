local M = {}

local text_util = require("codux.text")

local function trim(value)
  return text_util.trim(value)
end

function M.display(command, opts)
  opts = type(opts) == "table" and opts or {}
  if type(command) == "string" then
    return command
  end

  if type(command) ~= "table" then
    return tostring(command)
  end

  local parts = {}
  for _, part in ipairs(command) do
    local value = tostring(part)
    if value:find("%s") or (opts.escape_shell_specials and value:find("[\"'\\$`;&|<>]")) then
      value = vim.fn.shellescape(value)
    end
    table.insert(parts, value)
  end

  return table.concat(parts, " ")
end

function M.executable(command)
  if type(command) == "table" then
    return command[1]
  end

  if type(command) == "string" then
    return command:match("^%s*(%S+)")
  end

  return nil
end

function M.error(command, label)
  label = label or "Agent command"
  if type(command) == "string" then
    if command:match("^%s*$") then
      return label .. " must not be empty"
    end
    return nil
  end

  if type(command) ~= "table" then
    return label .. " must be a string or list"
  end

  if type(command[1]) ~= "string" or command[1]:match("^%s*$") then
    return label .. " list must start with an executable"
  end

  return nil
end

function M.with_args(command, args)
  args = type(args) == "table" and args or {}
  if #args == 0 then
    return command
  end

  if type(command) == "table" then
    local with_args = vim.list_extend({}, command)
    for _, arg in ipairs(args) do
      table.insert(with_args, arg)
    end
    return with_args
  end

  if type(command) == "string" then
    local parts = { command }
    for _, arg in ipairs(args) do
      table.insert(parts, vim.fn.shellescape(tostring(arg)))
    end
    return table.concat(parts, " ")
  end

  return command
end

function M.with_prompt(command, prompt)
  if type(prompt) ~= "string" or prompt == "" then
    return command
  end

  return M.with_args(command, { prompt })
end

function M.toml_basic_string(value)
  value = tostring(value or "")
  value = value:gsub("\\", "\\\\")
  value = value:gsub('"', '\\"')
  value = value:gsub("\b", "\\b")
  value = value:gsub("\t", "\\t")
  value = value:gsub("\n", "\\n")
  value = value:gsub("\f", "\\f")
  value = value:gsub("\r", "\\r")
  value = value:gsub("[%z\1-\8\11\12\14-\31]", function(char)
    return string.format("\\u%04X", string.byte(char))
  end)
  return '"' .. value .. '"'
end

function M.with_developer_instructions(command, instructions)
  instructions = type(instructions) == "string" and trim(instructions) or ""
  if instructions == "" then
    return command
  end

  return M.with_args(command, {
    "-c",
    "developer_instructions=" .. M.toml_basic_string(instructions),
  })
end

function M.shell(command)
  return M.display(command, { escape_shell_specials = true })
end

return M
