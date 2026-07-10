local text_util = require("codux.text")
local workspace_git = require("codux.workspace_git")

local M = {}

local trim = text_util.trim

local function tmux_name_token(value, max_length)
  max_length = math.max(1, tonumber(max_length) or 48)
  value = tostring(value or ""):gsub("[^%w_-]+", "-"):gsub("-+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if value == "" then
    value = "workspace"
  end
  return value:sub(1, max_length)
end

local function stable_hash_token(value)
  local hash = 5381
  value = tostring(value or "")
  for index = 1, #value do
    hash = (hash * 33 + value:byte(index)) % 4294967296
  end
  return string.format("%08x", hash)
end

function M.server_dir()
  local base = nil
  if type(vim.fn.stdpath) == "function" then
    local ok, value = pcall(vim.fn.stdpath, "run")
    if ok and type(value) == "string" and value ~= "" then
      base = value
    end
  end
  if not base and type(vim.fn.tempname) == "function" then
    local ok, value = pcall(vim.fn.tempname)
    if ok and type(value) == "string" and value ~= "" then
      base = vim.fn.fnamemodify(value, ":h")
    end
  end
  base = base or "/tmp"
  local directory = base .. "/codux"
  pcall(vim.fn.mkdir, directory, "p")
  return directory
end

function M.server_path(root, safe_name, server_dir)
  return server_dir .. "/" .. workspace_git.path_token(root) .. "-" .. workspace_git.path_token(safe_name) .. ".sock"
end

function M.launch_server_path(root, safe_name, server_dir)
  local root_token = workspace_git.path_token(root)
  root_token = root_token:sub(math.max(1, #root_token - 11))
  return server_dir
    .. "/ws-"
    .. workspace_git.short_path_token(safe_name, 36)
    .. "-"
    .. root_token
    .. "-"
    .. workspace_git.launch_socket_token()
    .. ".sock"
end

function M.remote_luaeval(nvim_system, server, lua_expression, opts)
  opts = type(opts) == "table" and opts or {}
  if type(server) ~= "string" or server == "" then
    return nil, "workspace server is unavailable"
  end

  local attempts = math.max(1, tonumber(opts.attempts) or 1)
  local last_output = nil
  for attempt = 1, attempts do
    local output, code = nvim_system({ "--server", server, "--remote-expr", workspace_git.luaeval_expr(lua_expression) })
    if code == 0 then
      return trim(output), nil
    end
    last_output = trim(output)
    if attempt < attempts then
      pcall(vim.fn.sleep, tostring(tonumber(opts.sleep_ms) or 100) .. "m")
    end
  end

  return nil, last_output ~= "" and last_output or "workspace is not reachable"
end

function M.preview_session_name(entry)
  entry = type(entry) == "table" and entry or {}
  local root = entry.project_root or ""
  local workspace = entry.safe_name or entry.name or entry.window_name or ""
  return "codux-preview-"
    .. tmux_name_token(workspace, 48)
    .. "-"
    .. stable_hash_token(tostring(root) .. "\0" .. tostring(workspace))
end

return M
