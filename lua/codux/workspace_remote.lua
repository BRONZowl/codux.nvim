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

local function is_directory(path)
  if type(vim.fn) ~= "table" or type(vim.fn.isdirectory) ~= "function" then
    return false
  end
  local ok, result = pcall(vim.fn.isdirectory, path)
  return ok and result == 1
end

local function is_shared_temp_base(base)
  if type(base) ~= "string" or base == "" then
    return true
  end
  if base == "/tmp" or base == "/var/tmp" then
    return true
  end
  return base:match("^/tmp/") ~= nil or base:match("^/var/tmp/") ~= nil
end

local function secure_mkdir(path)
  if type(path) ~= "string" or path == "" or type(vim.fn) ~= "table" or type(vim.fn.mkdir) ~= "function" then
    return false
  end
  -- 0700 when supported (Neovim passes mode as the third argument).
  local ok, result = pcall(vim.fn.mkdir, path, "p", 448)
  if not ok or (result ~= 1 and result ~= 0 and not is_directory(path)) then
    ok, result = pcall(vim.fn.mkdir, path, "p")
    if not ok or (result ~= 1 and not is_directory(path)) then
      -- Test doubles may return 1 without creating a real directory.
      if not ok or result ~= 1 then
        return false
      end
    end
  end
  if type(vim.fn.setfperm) == "function" then
    pcall(vim.fn.setfperm, path, "rwx------")
  end
  return is_directory(path) or result == 1
end

--- Runtime directory for sockets and launch scripts.
--- Prefer stdpath("run"); never fall back to shared world-writable /tmp.
function M.server_dir()
  local candidates = {}
  if type(vim.fn) == "table" and type(vim.fn.stdpath) == "function" then
    for _, kind in ipairs({ "run", "cache", "state", "data" }) do
      local ok, value = pcall(vim.fn.stdpath, kind)
      if ok and type(value) == "string" and value ~= "" then
        table.insert(candidates, value)
      end
    end
  end
  if type(vim.env) == "table" and type(vim.env.XDG_RUNTIME_DIR) == "string" and vim.env.XDG_RUNTIME_DIR ~= "" then
    table.insert(candidates, 1, vim.env.XDG_RUNTIME_DIR)
  end
  if type(vim.fn) == "table" and type(vim.fn.expand) == "function" then
    local home_state = vim.fn.expand("~/.local/state")
    if type(home_state) == "string" and home_state ~= "" and not home_state:match("^~") then
      table.insert(candidates, home_state)
    end
  end

  for _, base in ipairs(candidates) do
    if not is_shared_temp_base(base) then
      local directory = base .. "/codux"
      if secure_mkdir(directory) then
        return directory
      end
    end
  end

  -- Last resort under home rather than shared /tmp. Keep a trailing
  -- `/codux` segment so socket names stay discoverable and consistent.
  local fallback = ".codux/run/codux"
  if type(vim.fn) == "table" and type(vim.fn.expand) == "function" then
    local expanded = vim.fn.expand("~/.codux/run/codux")
    if type(expanded) == "string" and expanded ~= "" and not expanded:match("^~") then
      fallback = expanded
    end
  end
  secure_mkdir(fallback)
  return fallback
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
