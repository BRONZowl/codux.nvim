local path_util = require("codux.path_util")
local workspace_status = require("codux.workspace_status")

local M = {}

local launch_socket_counter = 0

-- Path helpers live in path_util; re-export for existing callers.
M.strip_trailing_slashes = path_util.strip_trailing_slashes
M.path_join = path_util.path_join
M.normalize_absolute_path = path_util.normalize_absolute_path
M.normalize_relative_directory = path_util.normalize_relative_directory
M.starts_with_path = path_util.starts_with_path
M.relative_path_escapes_root = path_util.relative_path_escapes_root
M.path_token = path_util.path_token
M.short_path_token = path_util.short_path_token

-- Status/mode helpers live in workspace_status; re-export for existing callers.
M.normalize_agent_mode = workspace_status.normalize_agent_mode
M.normalize_codex_mode = workspace_status.normalize_codex_mode
M.inactive_like_status = workspace_status.inactive_like_status

function M.prepend_command(command, args)
  local result = { command }
  for _, arg in ipairs(args or {}) do
    table.insert(result, arg)
  end
  return result
end

function M.launch_socket_token()
  launch_socket_counter = (launch_socket_counter + 1) % 65536
  local stamp = os.time() % 1048576
  local uv = vim.uv or vim.loop
  if type(uv) == "table" and type(uv.hrtime) == "function" then
    local ok, value = pcall(uv.hrtime)
    if ok and type(value) == "number" then
      stamp = value % 1048576
    end
  end
  return string.format("%05x%04x", stamp, launch_socket_counter)
end

function M.vimscript_string(value)
  value = tostring(value or "")
  value = value:gsub("\\", "\\\\")
  value = value:gsub('"', '\\"')
  value = value:gsub("\n", "\\n")
  value = value:gsub("\r", "\\r")
  return '"' .. value .. '"'
end

function M.luaeval_expr(lua_expression)
  return "luaeval(" .. M.vimscript_string(lua_expression) .. ")"
end

return M
