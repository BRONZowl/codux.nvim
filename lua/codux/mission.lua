local M = {}

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
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
    name = "Architect",
    safe_name = "architect",
    focus = "Clarify the design, interfaces, risks, and implementation order.",
  },
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
  {
    name = "QA",
    safe_name = "qa",
    focus = "Run or design the verification pass and report concrete failures.",
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
    "First pass: ground yourself in the repo, identify your role-specific next steps, then execute within this workspace. Report blockers and handoff notes clearly.",
  }, "\n")
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

return M
