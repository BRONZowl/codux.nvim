local text_util = require("codux.text")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.files_config(store)
  local workspaces = store:workspace_config()
  if workspaces.enabled == false then
    return { enabled = false }
  end

  local value = workspaces.instruction_files
  if value == false then
    return { enabled = false }
  end
  if type(value) ~= "table" then
    value = store.default_instruction_files
  end

  local directory = type(value.directory) == "string" and trim(value.directory) or ""
  if directory == "" then
    directory = store.default_instruction_files.directory
  end

  return {
    enabled = value.enabled ~= false,
    directory = directory,
  }
end

function M.directory(store, root)
  local file_config = store:instruction_files_config()
  if file_config.enabled == false then
    return nil
  end
  if type(root) ~= "string" or root == "" then
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

function M.file_path(store, root, safe_name)
  local directory = store:instruction_directory(root)
  if not directory or type(safe_name) ~= "string" or trim(safe_name) == "" then
    return nil
  end

  return directory .. "/" .. safe_name .. ".md"
end

function M.read_file(store, root, safe_name)
  local path = store:instruction_file_path(root, safe_name)
  if not path or vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end

  local instruction = trim(table.concat(lines, "\n"))
  if instruction == "" then
    return nil
  end

  return instruction
end

function M.write_file(store, root, safe_name, instruction)
  instruction = type(instruction) == "string" and trim(instruction) or ""
  if instruction == "" then
    return true, nil
  end

  local path = store:instruction_file_path(root, safe_name)
  if not path then
    return true, nil
  end

  local directory = vim.fn.fnamemodify(path, ":h")
  if directory ~= "" then
    local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, directory, "p")
    if not mkdir_ok or mkdir_result ~= 1 then
      return false, "Failed to create Codux workspace instruction directory"
    end
  end

  local lines = vim.split(instruction, "\n", { plain = true })
  local ok, result = pcall(vim.fn.writefile, lines, path)
  if not ok or result ~= 0 then
    return false, "Failed to write Codux workspace instruction file"
  end

  return true, nil
end

function M.delete_file(store, root, safe_name)
  local path = store:instruction_file_path(root, safe_name)
  if not path or vim.fn.filereadable(path) ~= 1 then
    return true, nil
  end

  local ok, result = pcall(vim.fn.delete, path)
  if not ok or result ~= 0 then
    return false, "Failed to delete Codux workspace instruction file"
  end

  return true, nil
end

function M.file_records(store, root)
  local directory = store:instruction_directory(root)
  if not directory or vim.fn.isdirectory(directory) ~= 1 then
    return {}
  end

  local ok, files = pcall(vim.fn.globpath, directory, "*.md", false, true)
  if not ok or type(files) ~= "table" then
    return {}
  end

  local records = {}
  for _, path in ipairs(files) do
    local safe_name = vim.fn.fnamemodify(path, ":t:r")
    local display_name, sanitized_name = store.sanitize_workspace_name(safe_name)
    if type(safe_name) == "string" and display_name and sanitized_name == safe_name then
      local instruction = store:read_instruction_file(root, safe_name)
      if instruction then
        records[safe_name] = {
          name = display_name,
          safe_name = safe_name,
          project_root = root,
          resolved_instruction = instruction,
          status = "inactive",
          agent_status = "idle",
          instruction_file = path,
          instruction_file_only = true,
        }
      end
    end
  end

  return records
end

return M
