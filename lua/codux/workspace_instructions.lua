local text_util = require("codux.text")
local path_util = require("codux.path_util")

local M = {}

local trim = text_util.trim

function M.relative_dir(runtime, root)
  local config = runtime:instruction_files_config()
  if type(config) ~= "table" or config.enabled == false then
    return nil
  end
  if type(root) ~= "string" or root == "" then
    return nil
  end

  local configured = path_util.normalize_relative_directory(config.directory)
  if configured == "" then
    return nil
  end
  if path_util.relative_path_escapes_root(configured) then
    return nil
  end
  if configured:match("^/") or configured:match("^~") then
    local directory = runtime:instruction_directory(root)
    if type(directory) ~= "string" or directory == "" or not path_util.starts_with_path(directory, root) or directory == root then
      return nil
    end
    return path_util.normalize_relative_directory(directory:sub(#path_util.strip_trailing_slashes(root) + 2))
  end

  return configured
end

function M.ignore_rule(runtime, root)
  local relative_dir = runtime:workspace_instruction_relative_dir(root)
  if not relative_dir then
    return nil
  end

  if relative_dir == ".agents" or relative_dir:sub(1, 8) == ".agents/" then
    return ".agents/"
  end

  return relative_dir .. "/"
end

function M.ignore_status(runtime, root)
  local relative_dir = runtime:workspace_instruction_relative_dir(root)
  if not relative_dir then
    return {
      status = "skipped",
      reason = "workspace instruction files are disabled or outside the project",
    }
  end

  local marker = relative_dir .. "/.codux-ignore-check"
  local _, code = runtime.system({ "git", "-C", root, "check-ignore", "--quiet", "--", marker })
  if code == 0 then
    return {
      status = "ignored",
      relative_dir = relative_dir,
      marker = marker,
      rule = runtime:workspace_instruction_ignore_rule(root),
    }
  end
  if code == 1 then
    return {
      status = "not_ignored",
      relative_dir = relative_dir,
      marker = marker,
      rule = runtime:workspace_instruction_ignore_rule(root),
    }
  end

  return {
    status = "unknown",
    relative_dir = relative_dir,
    marker = marker,
    rule = runtime:workspace_instruction_ignore_rule(root),
  }
end

function M.ignore_warning(runtime, root)
  local status = runtime:workspace_instruction_ignore_status(root)
  if status.status ~= "not_ignored" then
    return nil
  end

  return "Codux workspace instructions are not ignored by Git. Add "
    .. tostring(status.rule or status.relative_dir .. "/")
    .. " to .gitignore or run :CoduxWorkspaceIgnore."
end

function M.warn_ignore(runtime, root)
  local warning = runtime:workspace_instruction_ignore_warning(root)
  if not warning then
    return false
  end

  runtime.state.workspace_instruction_ignore_warnings = type(runtime.state.workspace_instruction_ignore_warnings) == "table"
      and runtime.state.workspace_instruction_ignore_warnings
    or {}
  local relative_dir = runtime:workspace_instruction_relative_dir(root) or ""
  local key = tostring(root or "") .. "\n" .. relative_dir
  if runtime.state.workspace_instruction_ignore_warnings[key] then
    return false
  end

  runtime.state.workspace_instruction_ignore_warnings[key] = true
  runtime.notify(warning, vim.log.levels.WARN)
  return true
end

function M.ensure_gitignore(runtime, root)
  root = type(root) == "string" and root ~= "" and root or runtime:target_context().root
  if type(root) ~= "string" or root == "" then
    return false, "project root not detected"
  end

  local status = runtime:workspace_instruction_ignore_status(root)
  if status.status == "skipped" then
    return false, "workspace instruction files are disabled or outside the project"
  end
  if status.status == "unknown" then
    return false, "not inside a Git repository or unable to check .gitignore"
  end

  local rule = status.rule or runtime:workspace_instruction_ignore_rule(root)
  if type(rule) ~= "string" or rule == "" then
    return false, "workspace instruction ignore rule could not be determined"
  end

  local path = root .. "/.gitignore"
  local lines = {}
  if vim.fn.filereadable(path) == 1 then
    local ok, read_lines = pcall(vim.fn.readfile, path)
    if not ok or type(read_lines) ~= "table" then
      return false, "Failed to read .gitignore"
    end
    lines = read_lines
  end

  for _, line in ipairs(lines) do
    if trim(line) == rule then
      return true, "Codux workspace instructions are already ignored by Git"
    end
  end

  if #lines > 0 and lines[#lines] ~= "" then
    table.insert(lines, "")
  end
  table.insert(lines, "# Codux workspace instructions")
  table.insert(lines, rule)

  local ok, result = pcall(vim.fn.writefile, lines, path)
  if not ok or result ~= 0 then
    return false, "Failed to update .gitignore"
  end

  return true, "Added " .. rule .. " to .gitignore"
end

function M.files_config(runtime)
  if runtime.store and type(runtime.store.instruction_files_config) == "function" then
    return runtime.store:instruction_files_config()
  end
  local workspaces = runtime:workspace_config()
  if workspaces.enabled == false or workspaces.instruction_files == false then
    return { enabled = false }
  end
  local defaults = runtime.defaults.workspaces or {}
  local default_instruction_files = defaults.instruction_files or { enabled = true, directory = ".agents/codux" }
  local value = type(workspaces.instruction_files) == "table" and workspaces.instruction_files or default_instruction_files
  local directory = type(value.directory) == "string" and trim(value.directory) or ""
  if directory == "" then
    directory = default_instruction_files.directory or ".agents/codux"
  end
  return {
    enabled = value.enabled ~= false,
    directory = directory,
  }
end

function M.directory(runtime, root)
  if runtime.store and type(runtime.store.instruction_directory) == "function" then
    return runtime.store:instruction_directory(root)
  end
  local file_config = runtime:instruction_files_config()
  if file_config.enabled == false or type(root) ~= "string" or root == "" then
    return nil
  end
  local directory = vim.fn.expand(file_config.directory)
  if directory == "" then
    return nil
  end
  if directory:match("^/") then
    return directory
  end
  return root .. "/" .. directory
end

function M.file_path(runtime, root, safe_name)
  return runtime.store:instruction_file_path(root, safe_name)
end

function M.read_file(runtime, root, safe_name)
  return runtime.store:read_instruction_file(root, safe_name)
end

function M.write_file(runtime, root, safe_name, instruction)
  return runtime.store:write_instruction_file(root, safe_name, instruction)
end

function M.delete_file(runtime, root, safe_name)
  return runtime.store:delete_instruction_file(root, safe_name)
end

function M.file_records(runtime, root)
  return runtime.store:instruction_file_records(root)
end

return M
