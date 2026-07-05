local M = {}

local text_util = require("codux.text")

local function trim(value)
  return text_util.trim(value)
end

local function lines(value)
  value = tostring(value or "")
  local result = {}
  for line in (value .. "\n"):gmatch("(.-)\n") do
    table.insert(result, line)
  end
  return result
end

function M.objective_preview(objective, max_width)
  local first_line = tostring(objective or ""):gsub("\r", ""):match("([^\n]*)") or ""
  first_line = trim(first_line)
  if first_line == "" then
    return "No objective"
  end

  max_width = tonumber(max_width) or 80
  if #first_line <= max_width then
    return first_line
  end

  return first_line:sub(1, math.max(1, max_width - 3)) .. "..."
end

function M.update_instruction_objective(instruction, objective)
  if type(instruction) ~= "string" then
    return instruction
  end
  objective = trim(objective)
  if instruction == "" or objective == "" then
    return instruction
  end

  local prefix, suffix = instruction:match("^(.-\nObjective:\n).-(\n\nRole focus:\n.*)$")
  if not prefix then
    return instruction
  end

  return prefix .. objective .. suffix
end

local function safe_name(value)
  return trim(value):lower():gsub("[^%w_.-]+", "-"):gsub("-+", "-"):gsub("^-+", ""):gsub("-+$", "")
end

local function default_role_by_name(name)
  local target = safe_name(name)
  if target == "" then
    return nil
  end

  for _, role in ipairs(M.DEFAULT_ROLES or {}) do
    if safe_name(role.safe_name or role.name) == target or safe_name(role.name) == target then
      return role
    end
  end

  return nil
end

function M.sanitize_mission_name(name)
  local display_name = trim(name)
  if display_name == "" then
    return nil, "Mission name is required"
  end

  local safe = safe_name(display_name)
  if safe == "" then
    return nil, "Mission name must contain letters, numbers, dots, dashes, or underscores"
  end

  return display_name, safe
end

function M.mission_id(safe_name)
  return "mission:" .. tostring(safe_name or "")
end

M.DEFAULT_ROLES = {
  {
    name = "Builder",
    safe_name = "builder",
    focus = "Implement the primary code changes with focused validation.",
  },
  {
    name = "Reviewer",
    safe_name = "reviewer",
    focus = "Review the branch for bugs, regressions, edge cases, and test gaps.",
  },
}

function M.workspace_name(safe_mission_name, role)
  role = type(role) == "table" and role or {}
  return tostring(safe_mission_name or "") .. "-" .. tostring(role.safe_name or "")
end

function M.role_instruction(mission_name, objective, role)
  role = type(role) == "table" and role or {}
  local role_name = role.name or role.safe_name or "Agent"
  return table.concat({
    "You are the " .. role_name .. " for Codux Mission Control.",
    "",
    "Mission: " .. tostring(mission_name or ""),
    "",
    "Objective:",
    trim(objective),
    "",
    "Role focus:",
    tostring(role.focus or ""),
    "",
    "Stay inside this workspace and keep your work scoped to this role. Coordinate through concise handoff notes when another role needs context.",
  }, "\n")
end

function M.role_prompt(mission_name, objective, role)
  role = type(role) == "table" and role or {}
  local role_name = role.name or role.safe_name or "Agent"
  return table.concat({
    "Start your Mission Control role now.",
    "",
    "Mission: " .. tostring(mission_name or ""),
    "Role: " .. role_name,
    "",
    "Objective:",
    trim(objective),
    "",
    "First pass: stay in plan mode, ground yourself in the repo, and identify your role-specific next steps before executing. Report blockers and handoff notes clearly.",
  }, "\n")
end

function M.extract_role_focus(instruction)
  if type(instruction) ~= "string" then
    return ""
  end

  local focus = instruction:match("\nRole focus:\n(.-)\n\nStay inside this workspace")
    or instruction:match("^Role focus:\n(.-)\n\nStay inside this workspace")
  return trim(focus)
end

function M.role_from_entry(entry)
  entry = type(entry) == "table" and entry or {}
  local role_name = trim(entry.mission_role or entry.name or entry.safe_name)
  local role_safe_name = safe_name(entry.mission_role or role_name)
  local default_role = default_role_by_name(role_name) or default_role_by_name(role_safe_name) or {}
  local focus = trim(default_role.focus)
  if focus == "" then
    focus = M.extract_role_focus(entry.resolved_instruction or entry.custom_instruction)
  end

  return {
    name = role_name ~= "" and role_name or role_safe_name,
    safe_name = role_safe_name ~= "" and role_safe_name or safe_name(role_name),
    focus = focus,
  }
end

function M.plan(name, objective, opts)
  opts = type(opts) == "table" and opts or {}
  local mission_name, safe_name_or_error = M.sanitize_mission_name(name)
  if not mission_name then
    return nil, safe_name_or_error
  end

  objective = trim(objective)
  if objective == "" then
    return nil, "Mission objective is required"
  end

  local roles = type(opts.roles) == "table" and opts.roles or M.DEFAULT_ROLES
  local mission = {
    name = mission_name,
    safe_name = safe_name_or_error,
    mission_id = M.mission_id(safe_name_or_error),
    objective = objective,
    roles = {},
  }

  local seen = {}
  for _, role in ipairs(roles) do
    role = type(role) == "table" and role or {}
    local role_name = trim(role.name)
    local safe_role_source = trim(role.safe_name)
    if role_name == "" then
      role_name = safe_role_source
    end
    if safe_role_source == "" then
      safe_role_source = role_name
    end
    local safe_role = safe_name(safe_role_source)
    if safe_role == "" then
      return nil, "Mission role name is required"
    end
    if seen[safe_role] then
      return nil, "Duplicate mission role: " .. safe_role
    end
    seen[safe_role] = true

    local normalized_role = {
      name = role_name ~= "" and role_name or safe_role,
      safe_name = safe_role,
      focus = trim(role.focus),
    }
    normalized_role.workspace_name = M.workspace_name(mission.safe_name, normalized_role)
    normalized_role.instruction = M.role_instruction(mission.name, objective, normalized_role)
    normalized_role.initial_prompt = M.role_prompt(mission.name, objective, normalized_role)
    table.insert(mission.roles, normalized_role)
  end

  if #mission.roles == 0 then
    return nil, "Mission requires at least one role"
  end

  return mission, nil
end

function M.status_counts(mission)
  local counts = {
    total = 0,
    active = 0,
    question = 0,
    idle = 0,
    inactive = 0,
  }

  for _, entry in ipairs(type(mission) == "table" and type(mission.roles) == "table" and mission.roles or {}) do
    counts.total = counts.total + 1
    local status = entry.status
    if status == "active" then
      counts.active = counts.active + 1
    elseif status == "question" then
      counts.question = counts.question + 1
    elseif status == "idle" then
      counts.idle = counts.idle + 1
    else
      counts.inactive = counts.inactive + 1
    end
  end

  return counts
end

function M.status_label(mission)
  local counts = M.status_counts(mission)
  if counts.question > 0 then
    return "question"
  end
  if counts.active > 0 then
    return "active"
  end
  if counts.idle > 0 then
    return "idle"
  end
  return "inactive"
end

function M.find_mission(missions, name)
  local query = trim(name)
  if query == "" then
    return nil, "Mission name is required"
  end

  local query_safe = safe_name(query)
  for _, mission in ipairs(type(missions) == "table" and missions or {}) do
    local mission_name = trim(mission.name or mission.mission_id)
    local mission_safe = safe_name(mission_name)
    if mission_name == query or mission_safe == query_safe or mission.mission_id == query then
      return mission, nil
    end
  end

  return nil, "mission not found"
end

function M.preview_lines(mission)
  mission = type(mission) == "table" and mission or {}
  local result = {
    "Launch Codux mission?",
    "",
    "Mission: " .. tostring(mission.name or ""),
    "",
    "Objective:",
  }
  for _, line in ipairs(lines(mission.objective)) do
    table.insert(result, line)
  end
  table.insert(result, "")
  table.insert(result, "Crew:")
  for _, role in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    table.insert(result, "  " .. tostring(role.workspace_name or "") .. " - " .. tostring(role.name or ""))
  end
  table.insert(result, "")
  table.insert(result, "Each role will launch in a Git worktree with workspace-auto permissions.")
  return result
end

function M.group_entries(entries)
  local missions = {}
  local order = {}

  for _, entry in ipairs(type(entries) == "table" and entries or {}) do
    if type(entry) == "table" and type(entry.mission_id) == "string" and entry.mission_id ~= "" then
      local mission = missions[entry.mission_id]
      if not mission then
        mission = {
          mission_id = entry.mission_id,
          name = entry.mission_name or entry.mission_id,
          objective = entry.mission_objective,
          roles = {},
        }
        missions[entry.mission_id] = mission
        table.insert(order, mission)
      end
      table.insert(mission.roles, entry)
    end
  end

  table.sort(order, function(left, right)
    return tostring(left.name):lower() < tostring(right.name):lower()
  end)
  for _, mission in ipairs(order) do
    table.sort(mission.roles, function(left, right)
      return tostring(left.mission_role or left.name):lower() < tostring(right.mission_role or right.name):lower()
    end)
  end

  return order
end

function M.names(missions)
  local result = {}
  for _, mission in ipairs(type(missions) == "table" and missions or {}) do
    table.insert(result, mission.name or mission.mission_id)
  end
  table.sort(result, function(left, right)
    return tostring(left):lower() < tostring(right):lower()
  end)
  return result
end

return M
