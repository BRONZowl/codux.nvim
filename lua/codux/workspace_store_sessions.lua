local text_util = require("codux.text")
local workspace_store_state = require("codux.workspace_store_state")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.codex_home()
  local value = vim.env.CODEX_HOME
  if type(value) == "string" and trim(value) ~= "" then
    return vim.fn.expand(value)
  end

  return vim.fn.expand("~/.codex")
end

function M.session_files(store)
  local root = store:codex_home() .. "/sessions"
  if vim.fn.isdirectory(root) ~= 1 then
    return {}
  end

  local ok, files = pcall(vim.fn.globpath, root, "**/*.jsonl", false, true)
  if not ok or type(files) ~= "table" then
    return {}
  end

  return files
end

function M.read_meta(store, path)
  if type(path) ~= "string" or path == "" or vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path, "", 1)
  if not ok or type(lines) ~= "table" or type(lines[1]) ~= "string" then
    return nil
  end

  local decoded = store.json_decode(lines[1])
  if type(decoded) ~= "table" or decoded.type ~= "session_meta" or type(decoded.payload) ~= "table" then
    return nil
  end

  local payload = decoded.payload
  local session_id = workspace_store_state.normalize_session_id(payload.session_id)
    or workspace_store_state.normalize_session_id(payload.id)
  if not session_id then
    return nil
  end

  return {
    session_id = session_id,
    cwd = payload.cwd,
    timestamp = payload.timestamp,
    path = path,
    mtime = tonumber(vim.fn.getftime(path)) or 0,
  }
end

function M.session_for_id(store, session_id)
  session_id = workspace_store_state.normalize_session_id(session_id)
  if not session_id then
    return nil
  end

  for _, path in ipairs(store:codex_session_files()) do
    local meta = store:read_codex_session_meta(path)
    if meta and meta.session_id == session_id then
      return meta
    end
  end

  return nil
end

function M.latest_for_cwd(store, cwd, min_mtime)
  if type(cwd) ~= "string" or cwd == "" then
    return nil
  end

  min_mtime = tonumber(min_mtime) or 0
  local latest = nil
  for _, path in ipairs(store:codex_session_files()) do
    local meta = store:read_codex_session_meta(path)
    if meta and meta.cwd == cwd and meta.mtime >= min_mtime and (not latest or meta.mtime > latest.mtime) then
      latest = meta
    end
  end

  return latest
end

function M.apply_meta(workspace, meta)
  if type(workspace) ~= "table" or type(meta) ~= "table" then
    return false
  end

  local session_id = workspace_store_state.normalize_session_id(meta.session_id)
  if not session_id then
    return false
  end

  workspace.codex_session_id = session_id
  workspace.codex_session_path = meta.path
  workspace.codex_session_captured_at = workspace_store_state.timestamp()
  return true
end

function M.resolve_resume(store, workspace)
  if type(workspace) ~= "table" then
    return nil
  end

  local session_id = workspace_store_state.normalize_session_id(workspace.codex_session_id)
  if session_id then
    local meta = store:codex_session_for_id(session_id)
    if meta and meta.cwd == workspace.project_root then
      M.apply_meta(workspace, meta)
      return meta
    end
    workspace.codex_session_id = nil
    workspace.codex_session_path = nil
    workspace.codex_session_captured_at = nil
  end

  local meta = store:latest_codex_session_for_cwd(workspace.project_root)
  if meta then
    M.apply_meta(workspace, meta)
    return meta
  end

  return nil
end

return M
