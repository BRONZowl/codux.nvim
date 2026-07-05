local text_util = require("codux.text")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.saved_workspace_instruction_request(runtime, entry)
  entry = type(entry) == "table" and entry or {}
  local root = entry.project_root or runtime.state.workspace_manager_project_root
  local safe_name = entry.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return nil, "workspace not found"
  end

  local instruction = runtime:read_instruction_file(root, safe_name)
  if type(instruction) ~= "string" or trim(instruction) == "" then
    local state_data = runtime:read_state()
    local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
    local workspaces = type(project) == "table" and project.workspaces or nil
    local record = type(workspaces) == "table" and workspaces[safe_name] or nil
    if type(record) == "table" and type(record.resolved_instruction) == "string" then
      instruction = record.resolved_instruction
    elseif type(entry.resolved_instruction) == "string" then
      instruction = entry.resolved_instruction
    end
  end

  return {
    name = entry.name or safe_name,
    safe_name = safe_name,
    project_root = root,
    custom_instruction = instruction,
    resolved_instruction = instruction,
  }, nil
end

function M.update_saved_workspace_instruction(runtime, entry, instruction)
  entry = type(entry) == "table" and entry or {}
  instruction = type(instruction) == "string" and trim(instruction) or ""
  if instruction == "" then
    return false, "Workspace instruction is required"
  end

  local root = entry.project_root or runtime.state.workspace_manager_project_root
  local safe_name = entry.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false, "workspace not found"
  end

  local instruction_ok, instruction_error = runtime:write_instruction_file(root, safe_name, instruction)
  if not instruction_ok then
    return false, instruction_error
  end

  local state_data, state_error = runtime:read_state()
  if state_error then
    return false, state_error
  end

  local project = runtime:project_state(state_data, root)
  local record = project.workspaces[safe_name]
  if type(record) == "table" then
    record.custom_instruction = instruction
    record.resolved_instruction = instruction
    project.updated_at = runtime:timestamp()

    local write_ok, write_error = runtime:write_state(state_data)
    if not write_ok then
      return false, write_error
    end
  end

  if runtime.state.workspace and runtime.state.workspace.project_root == root and runtime.state.workspace.safe_name == safe_name then
    runtime.state.workspace.custom_instruction = instruction
    runtime.state.workspace.resolved_instruction = instruction
  end
  if runtime.state.workspace_manager_project_root == root then
    runtime.render_workspace_manager()
  end

  return true, nil
end

return M
