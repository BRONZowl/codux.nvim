local M = {}

local text_util = require("codux.text")

local trim = text_util.trim

local function lines(value)
  value = tostring(value or "")
  local result = {}
  for line in (value .. "\n"):gmatch("(.-)\n") do
    table.insert(result, line)
  end
  return result
end

local function truncate_line(line, max_width)
  max_width = tonumber(max_width)
  if not max_width then
    return line
  end
  return text_util.truncate_display_tail(line, max_width)
end

local function truncate_preview_lines(preview_lines, opts)
  opts = type(opts) == "table" and opts or {}
  local max_width = tonumber(opts.max_width)
  local max_lines = tonumber(opts.max_lines)
  if not max_width and not max_lines then
    return preview_lines
  end

  local result = {}
  for _, line in ipairs(preview_lines) do
    table.insert(result, truncate_line(line, max_width))
  end

  if max_lines and max_lines > 0 and #result > max_lines then
    local marker = truncate_line("... preview truncated", max_width)
    local truncated = {}
    for index = 1, math.max(0, max_lines - 1) do
      table.insert(truncated, result[index])
    end
    table.insert(truncated, marker)
    result = truncated
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

M.MANAGER_ROLE = {
  name = "Manager",
  safe_name = "manager",
  focus = "Own the mission objective and focus packet. Plan work, coordinate worker roles, write clear handoffs, and do not implement everything yourself. This role is the mission console in Mission Control.",
}

M.DEFAULT_ROLES = {
  M.MANAGER_ROLE,
  {
    name = "Agent",
    safe_name = "agent",
    focus = "Create the requested outcome accurately, keep context focused, validate cheaply, and ask only high-impact questions.",
  },
}

--- True when a planned role or workspace entry is the mission Manager.
function M.is_manager_role(entry_or_role)
  entry_or_role = type(entry_or_role) == "table" and entry_or_role or {}
  -- Check fields individually (do not pack into a list with ipairs — nils stop iteration).
  for _, value in ipairs({
    entry_or_role.mission_role or false,
    entry_or_role.name or false,
    entry_or_role.safe_name or false,
  }) do
    if value and safe_name(value) == "manager" then
      return true
    end
  end
  return false
end

--- First Manager role among mission.roles (planned or workspace entries).
function M.find_manager_role(mission)
  mission = type(mission) == "table" and mission or {}
  for _, role in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    if M.is_manager_role(role) then
      return role
    end
  end
  return nil
end

--- Ensure a Manager role is present; prepend MANAGER_ROLE when missing.
function M.ensure_manager_in_roles(roles)
  roles = type(roles) == "table" and roles or {}
  local result = {}
  for _, role in ipairs(roles) do
    table.insert(result, role)
  end
  for _, role in ipairs(result) do
    if M.is_manager_role(role) then
      return result
    end
  end
  table.insert(result, 1, {
    name = M.MANAGER_ROLE.name,
    safe_name = M.MANAGER_ROLE.safe_name,
    focus = M.MANAGER_ROLE.focus,
  })
  return result
end

function M.default_focus_packet(mission_name, objective)
  return table.concat({
    "# Mission Focus Packet",
    "",
    "Mission:",
    tostring(mission_name or ""),
    "",
    "Current User Intent:",
    trim(objective),
    "",
    "Current Direction:",
    "The Manager owns planning and handoffs. Worker roles (e.g. Agent) execute scoped tasks. Preserve prompt fidelity and keep context narrow.",
    "",
    "User Preferences:",
    "- Prefer accurate creation from the user's prompt.",
    "- Ask fewer questions; ask only when the answer materially changes the result.",
    "- Avoid extra token use and broad context expansion.",
    "",
    "Active Scope:",
    "The files, behavior, and validation needed for this mission.",
    "",
    "Out of Scope:",
    "Heavy acceptance workflows and unrelated refactors without Manager direction.",
    "",
    "Next Action:",
    "Manager: ground in the repo and sequence work. Workers: implement the handoff they receive.",
  }, "\n")
end

function M.workspace_name(safe_mission_name, role)
  role = type(role) == "table" and role or {}
  return tostring(safe_mission_name or "") .. "-" .. tostring(role.safe_name or "")
end

function M.role_instruction(mission_name, objective, role, opts)
  role = type(role) == "table" and role or {}
  opts = type(opts) == "table" and opts or {}
  local role_name = role.name or role.safe_name or "Agent"
  local closing
  if M.is_manager_role(role) then
    closing = table.concat({
      "You are the mission console for this mission in Codux Mission Control.",
      "Plan, sequence, and write clear handoffs for worker roles. Do not implement everything yourself.",
      "Stay inside this Manager workspace for chat and planning; worker execution happens in other role workspaces.",
    }, " ")
  else
    closing =
      "Stay inside this workspace and keep your work scoped to this role. Coordinate through concise handoff notes when another role needs context."
  end
  local lines = {
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
    closing,
  }
  if M.is_manager_role(role) then
    local orchestrate = require("codux.mission_orchestrate")
    local help = orchestrate.manager_dispatch_help(
      opts.project_root,
      opts.mission_safe or safe_name(mission_name),
      opts.instruction_directory
    )
    table.insert(lines, "")
    table.insert(lines, "Worker dispatch protocol:")
    table.insert(lines, help)
  end
  return table.concat(lines, "\n")
end

function M.prompt_with_focus_packet(prompt, focus_packet)
  prompt = tostring(prompt or "")
  focus_packet = trim(focus_packet)
  if focus_packet == "" then
    return prompt
  end

  return table.concat({
    "Mission Focus Packet:",
    focus_packet,
    "",
    "User Request:",
    prompt,
  }, "\n")
end

function M.focus_packet_preview(focus_packet)
  local focus = tostring(focus_packet or "")
  local preview = ""
  local use_next = false
  for line in (focus:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
    local normalized = trim(line)
    if use_next and normalized ~= "" then
      return normalized
    end
    if normalized == "Current User Intent:" then
      use_next = true
    elseif preview == "" and normalized ~= "" and not normalized:match("^#") and not normalized:match(":$") then
      preview = normalized
    end
  end
  return preview
end

function M.role_prompt(mission_name, objective, role, focus_packet)
  role = type(role) == "table" and role or {}
  local role_name = role.name or role.safe_name or "Agent"
  local first_pass
  if M.is_manager_role(role) then
    first_pass =
      "First pass: stay in plan mode, ground yourself in the repo, outline worker handoffs, and identify the next action for each role. Report blockers clearly. Do not implement the whole mission yourself."
  else
    first_pass =
      "First pass: stay in plan mode, ground yourself in the repo, and identify your role-specific next steps before executing. Report blockers and handoff notes clearly."
  end
  local prompt = table.concat({
    "Start your Mission Control role now.",
    "",
    "Mission: " .. tostring(mission_name or ""),
    "Role: " .. role_name,
    "",
    "Objective:",
    trim(objective),
    "",
    first_pass,
  }, "\n")
  return M.prompt_with_focus_packet(prompt, focus_packet)
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
  -- Product rule: every mission always includes a Manager role.
  roles = M.ensure_manager_in_roles(roles)
  local mission = {
    name = mission_name,
    safe_name = safe_name_or_error,
    mission_id = M.mission_id(safe_name_or_error),
    objective = objective,
    focus_packet = trim(opts.focus_packet or opts.mission_focus_packet)
      ~= "" and trim(opts.focus_packet or opts.mission_focus_packet) or M.default_focus_packet(mission_name, objective),
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
    normalized_role.instruction = M.role_instruction(mission.name, objective, normalized_role, {
      project_root = opts.project_root,
      mission_safe = mission.safe_name,
      instruction_directory = opts.instruction_directory,
    })
    normalized_role.initial_prompt = M.role_prompt(mission.name, objective, normalized_role, mission.focus_packet)
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

function M.preview_lines(mission, opts)
  mission = type(mission) == "table" and mission or {}
  local result = {
    "Launch Codux mission?",
    "",
    "Mission: " .. tostring(mission.name or ""),
  }
  if type(mission.agent_provider) == "string" and mission.agent_provider ~= "" then
    table.insert(result, "Agent: " .. tostring(mission.agent_provider))
  end
  if type(mission.permission_profile) == "string" and mission.permission_profile ~= "" then
    table.insert(
      result,
      "Profile: " .. tostring(mission.permission_profile == "danger" and "full" or mission.permission_profile)
    )
  end
  table.insert(result, "")
  table.insert(result, "Objective:")
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
  return truncate_preview_lines(result, opts)
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
          focus_packet = entry.mission_focus_packet,
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
      local left_mgr = M.is_manager_role(left)
      local right_mgr = M.is_manager_role(right)
      if left_mgr ~= right_mgr then
        return left_mgr
      end
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
