local Store = {}
Store.__index = Store

local json = require("codux.json")
local text_util = require("codux.text")
local workspace_store_instructions = require("codux.workspace_store_instructions")
local workspace_store_sessions = require("codux.workspace_store_sessions")
local workspace_store_state = require("codux.workspace_store_state")

local function trim(value)
  return text_util.trim(value)
end

local function default_workspace_window_name(safe_name)
  return tostring(safe_name or "")
end

function Store:workspace_config()
  if type(self.get_workspace_config) == "function" then
    local value = self.get_workspace_config()
    if type(value) == "table" then
      return value
    end
  end

  return {}
end

function Store:state_file()
  local value = self:workspace_config().state_file
  if type(value) == "string" and trim(value) ~= "" then
    return vim.fn.expand(value)
  end

  return vim.fn.stdpath("data") .. "/codux/workspaces.json"
end

function Store:instruction_files_config()
  return workspace_store_instructions.files_config(self)
end

function Store:instruction_directory(root)
  return workspace_store_instructions.directory(self, root)
end

function Store:instruction_file_path(root, safe_name)
  return workspace_store_instructions.file_path(self, root, safe_name)
end

function Store:read_instruction_file(root, safe_name)
  return workspace_store_instructions.read_file(self, root, safe_name)
end

function Store:write_instruction_file(root, safe_name, instruction)
  return workspace_store_instructions.write_file(self, root, safe_name, instruction)
end

function Store:delete_instruction_file(root, safe_name)
  return workspace_store_instructions.delete_file(self, root, safe_name)
end

function Store:instruction_file_records(root)
  return workspace_store_instructions.file_records(self, root)
end

function Store:empty_state()
  return workspace_store_state.empty_state()
end

Store.normalize_session_id = workspace_store_state.normalize_session_id
Store.normalize_codex_mode = workspace_store_state.normalize_codex_mode

function Store:normalize_record(record, safe_name, root)
  return workspace_store_state.normalize_record(self, record, safe_name, root)
end

function Store:normalize_state(state_data)
  return workspace_store_state.normalize_state(self, state_data)
end

function Store:read_state()
  local path = self:state_file()
  if vim.fn.filereadable(path) ~= 1 then
    return self:empty_state(), nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return self:empty_state(), "Failed to read Codux workspace state"
  end

  local decoded = self.json_decode(table.concat(lines, "\n"))
  if type(decoded) ~= "table" then
    return self:empty_state(), "Failed to parse Codux workspace state"
  end

  return self:normalize_state(decoded), nil
end

function Store:write_state(state_data)
  local path = self:state_file()
  local directory = vim.fn.fnamemodify(path, ":h")
  if directory ~= "" then
    local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, directory, "p")
    if not mkdir_ok or mkdir_result ~= 1 then
      return false, "Failed to create Codux workspace state directory"
    end
  end

  local encoded = self.json_encode(self:normalize_state(state_data))
  local ok, result = pcall(vim.fn.writefile, { encoded }, path)
  if not ok or result ~= 0 then
    return false, "Failed to write Codux workspace state"
  end

  return true, nil
end

function Store.timestamp()
  return workspace_store_state.timestamp()
end

function Store:project_state(state_data, root)
  return workspace_store_state.project_state(self, state_data, root)
end

function Store.workspace_from_state(record, fallback)
  return workspace_store_state.workspace_from_state(record, fallback)
end

function Store:state_record(workspace, existing)
  return workspace_store_state.state_record(self, workspace, existing)
end

function Store.codex_home()
  return workspace_store_sessions.codex_home()
end

function Store:codex_session_files()
  return workspace_store_sessions.session_files(self)
end

function Store:read_codex_session_meta(path)
  return workspace_store_sessions.read_meta(self, path)
end

function Store:codex_session_for_id(session_id)
  return workspace_store_sessions.session_for_id(self, session_id)
end

function Store:latest_codex_session_for_cwd(cwd, min_mtime)
  return workspace_store_sessions.latest_for_cwd(self, cwd, min_mtime)
end

function Store.apply_codex_session_meta(workspace, meta)
  return workspace_store_sessions.apply_meta(workspace, meta)
end

function Store:resolve_workspace_resume_session(workspace)
  return workspace_store_sessions.resolve_resume(self, workspace)
end

local M = {}

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local store = {
    get_workspace_config = opts.get_workspace_config,
    default_instruction_files = type(opts.default_instruction_files) == "table" and opts.default_instruction_files
      or { enabled = true, directory = ".agents/codux" },
    json_encode = type(opts.json_encode) == "function" and opts.json_encode or json.encode,
    json_decode = type(opts.json_decode) == "function" and opts.json_decode or json.decode,
    sanitize_workspace_name = type(opts.sanitize_workspace_name) == "function" and opts.sanitize_workspace_name
      or function(name)
        return trim(name), trim(name)
      end,
    workspace_window_name = type(opts.workspace_window_name) == "function" and opts.workspace_window_name
      or default_workspace_window_name,
  }

  return setmetatable(store, Store)
end

return M
