local json = require("codux.json")
local mission_mod = require("codux.mission")
local text_util = require("codux.text")
local workspace_status = require("codux.workspace_status")

local M = {}

local trim = text_util.trim
local inactive_like_status = workspace_status.inactive_like_status

local MAX_PROMPT_CHARS = 32000
local MAX_ACTIONS_PER_FILE = 20
local MAX_ACTIONS_PER_TICK = 3

local function safe_name(value)
  return trim(value):lower():gsub("[^%w_.-]+", "-"):gsub("-+", "-"):gsub("^-+", ""):gsub("-+$", "")
end

local function default_fs()
  return {
    isdirectory = function(path)
      return vim.fn.isdirectory(path) == 1
    end,
    mkdir = function(path)
      return vim.fn.mkdir(path, "p")
    end,
    readdir = function(path)
      local ok, entries = pcall(vim.fn.readdir, path)
      if not ok or type(entries) ~= "table" then
        return {}
      end
      return entries
    end,
    readfile = function(path)
      local ok, lines = pcall(vim.fn.readfile, path)
      if not ok or type(lines) ~= "table" then
        return nil
      end
      return table.concat(lines, "\n")
    end,
    writefile = function(path, content)
      local lines = vim.split(tostring(content or ""), "\n", { plain = true })
      local ok = pcall(vim.fn.writefile, lines, path)
      return ok
    end,
    rename = function(from_path, to_path)
      local ok = pcall(vim.fn.rename, from_path, to_path)
      return ok
    end,
    filereadable = function(path)
      return vim.fn.filereadable(path) == 1
    end,
  }
end

function M.with_fs(fs)
  fs = type(fs) == "table" and fs or {}
  local base = default_fs()
  for key, value in pairs(fs) do
    base[key] = value
  end
  return base
end

--- Shared project path for mission dispatch files (not per-worktree).
function M.dispatch_base(project_root, mission_safe, instruction_directory)
  project_root = tostring(project_root or ""):gsub("/+$", "")
  mission_safe = safe_name(mission_safe)
  instruction_directory = trim(instruction_directory)
  if instruction_directory == "" then
    instruction_directory = ".agents/codux"
  end
  instruction_directory = instruction_directory:gsub("^/+", ""):gsub("/+$", "")
  if project_root == "" or mission_safe == "" then
    return nil
  end
  return project_root .. "/" .. instruction_directory .. "/missions/" .. mission_safe .. "/dispatch"
end

function M.dispatch_dirs(project_root, mission_safe, instruction_directory)
  local base = M.dispatch_base(project_root, mission_safe, instruction_directory)
  if not base then
    return nil
  end
  return {
    base = base,
    pending = base .. "/pending",
    done = base .. "/done",
    failed = base .. "/failed",
  }
end

function M.ensure_dispatch_dirs(project_root, mission_safe, opts)
  opts = type(opts) == "table" and opts or {}
  local fs = M.with_fs(opts.fs)
  local dirs = M.dispatch_dirs(project_root, mission_safe, opts.instruction_directory)
  if not dirs then
    return false, "dispatch path unavailable"
  end
  for _, path in ipairs({ dirs.base, dirs.pending, dirs.done, dirs.failed }) do
    if not fs.isdirectory(path) then
      local ok = pcall(fs.mkdir, path)
      if not ok and not fs.isdirectory(path) then
        return false, "failed to create dispatch directory: " .. path
      end
    end
  end
  return true, nil, dirs
end

function M.find_role(mission, role_name)
  mission = type(mission) == "table" and mission or {}
  local want = safe_name(role_name)
  if want == "" then
    return nil
  end
  for _, entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    -- Avoid packing nils into a list (ipairs stops at the first nil).
    for _, key in ipairs({
      entry.mission_role or false,
      entry.name or false,
      entry.safe_name or false,
    }) do
      if key then
        local normalized = safe_name(key)
        if normalized == want then
          return entry
        end
        -- Workspace safe names are often "{mission}-{role}".
        if normalized:match("%-" .. want:gsub("%-", "%%-") .. "$") then
          return entry
        end
      end
    end
  end
  return nil
end

function M.list_roles(mission)
  mission = type(mission) == "table" and mission or {}
  local roles = {}
  for _, entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    table.insert(roles, entry)
  end
  return roles
end

local function normalize_op(op)
  op = trim(op):lower():gsub("%s+", "_")
  if op == "start_and_prompt" or op == "start" or op == "prompt" or op == "create_role" or op == "update_focus" then
    return op
  end
  return nil
end

function M.validate_action(action)
  if type(action) ~= "table" then
    return nil, "action must be a table"
  end
  local op = normalize_op(action.op or action.action)
  if not op then
    return nil, "unsupported op: " .. tostring(action.op or action.action or "")
  end

  local normalized = { op = op }

  if op == "update_focus" then
    local packet = action.focus_packet or action.packet or action.focus
    if type(packet) ~= "string" or trim(packet) == "" then
      return nil, "update_focus requires focus_packet"
    end
    if #packet > MAX_PROMPT_CHARS then
      return nil, "focus_packet exceeds " .. tostring(MAX_PROMPT_CHARS) .. " characters"
    end
    normalized.focus_packet = packet
    return normalized
  end

  local role = trim(action.role or action.role_name or action.name)
  if role == "" then
    return nil, op .. " requires role"
  end
  normalized.role = role

  if op == "prompt" or op == "start_and_prompt" then
    local prompt = action.prompt or action.message or action.task
    if type(prompt) ~= "string" or trim(prompt) == "" then
      return nil, op .. " requires prompt"
    end
    if #prompt > MAX_PROMPT_CHARS then
      return nil, "prompt exceeds " .. tostring(MAX_PROMPT_CHARS) .. " characters"
    end
    normalized.prompt = prompt
  end

  if op == "create_role" then
    if type(action.focus) == "string" then
      normalized.focus = action.focus
    end
    if type(action.agent_provider) == "string" then
      normalized.agent_provider = action.agent_provider
    end
    if type(action.permission_profile) == "string" then
      normalized.permission_profile = action.permission_profile
    end
    if type(action.prompt) == "string" and trim(action.prompt) ~= "" then
      if #action.prompt > MAX_PROMPT_CHARS then
        return nil, "prompt exceeds " .. tostring(MAX_PROMPT_CHARS) .. " characters"
      end
      normalized.prompt = action.prompt
    end
  end

  return normalized
end

function M.parse_dispatch_document(raw)
  if type(raw) ~= "string" or trim(raw) == "" then
    return nil, "empty dispatch document"
  end
  local decoded = json.decode(raw)
  if type(decoded) ~= "table" then
    return nil, "invalid JSON"
  end

  local actions = decoded.actions
  if type(actions) ~= "table" then
    -- Allow a bare action object.
    if decoded.op or decoded.action then
      actions = { decoded }
    else
      return nil, "dispatch document requires actions[]"
    end
  end

  local normalized = {}
  for index, action in ipairs(actions) do
    if index > MAX_ACTIONS_PER_FILE then
      break
    end
    local ok_action, err = M.validate_action(action)
    if not ok_action then
      return nil, "action " .. tostring(index) .. ": " .. tostring(err)
    end
    table.insert(normalized, ok_action)
  end
  if #normalized == 0 then
    return nil, "no valid actions"
  end
  return {
    version = tonumber(decoded.version) or 1,
    source = type(decoded.source) == "string" and decoded.source or nil,
    actions = normalized,
  }
end

--- Apply a single validated action using injected runtime operations.
--- ops: {
---   start_workspace(entry) -> ok, err
---   send_prompt(entry, prompt) -> ok, err
---   create_role(mission, role_name, opts) -> ok, err, entry?
---   update_focus(mission, focus_packet) -> ok, err
--- }
function M.apply_action(ops, mission, action)
  ops = type(ops) == "table" and ops or {}
  mission = type(mission) == "table" and mission or {}
  local validated, validate_error = M.validate_action(action)
  if not validated then
    return false, validate_error
  end
  action = validated

  if action.op == "update_focus" then
    if type(ops.update_focus) ~= "function" then
      return false, "update_focus unavailable"
    end
    local ok, err = ops.update_focus(mission, action.focus_packet)
    if ok == false then
      return false, err or "update_focus failed"
    end
    return true
  end

  if action.op == "create_role" then
    local existing = M.find_role(mission, action.role)
    if existing then
      if action.prompt and type(ops.send_prompt) == "function" then
        if type(ops.start_workspace) == "function" and inactive_like_status(existing.status) then
          local started, start_err = ops.start_workspace(existing)
          if started == false then
            return false, start_err or "failed to start existing role"
          end
        end
        local sent, send_err = ops.send_prompt(existing, action.prompt)
        if sent == false then
          return false, send_err or "failed to prompt existing role"
        end
      end
      return true, nil, existing
    end
    if type(ops.create_role) ~= "function" then
      return false, "create_role unavailable"
    end
    local created, create_err, entry = ops.create_role(mission, action.role, {
      focus = action.focus,
      agent_provider = action.agent_provider,
      permission_profile = action.permission_profile,
      prompt = action.prompt,
    })
    if created == false then
      return false, create_err or "create_role failed"
    end
    return true, nil, entry
  end

  local entry = M.find_role(mission, action.role)
  if not entry then
    return false, "role not found: " .. tostring(action.role)
  end

  if action.op == "start" or action.op == "start_and_prompt" then
    if type(ops.start_workspace) ~= "function" then
      return false, "start_workspace unavailable"
    end
    if inactive_like_status(entry.status) or action.op == "start" or action.op == "start_and_prompt" then
      local started, start_err = ops.start_workspace(entry)
      if started == false then
        return false, start_err or "failed to start role"
      end
    end
  end

  if action.op == "prompt" or action.op == "start_and_prompt" then
    if type(ops.send_prompt) ~= "function" then
      return false, "send_prompt unavailable"
    end
    local sent, send_err = ops.send_prompt(entry, action.prompt)
    if sent == false then
      return false, send_err or "failed to send prompt"
    end
  end

  return true, nil, entry
end

local function move_file(fs, from_path, to_dir, basename, suffix)
  local dest = to_dir .. "/" .. basename
  if suffix then
    dest = dest .. suffix
  end
  if fs.filereadable(dest) or fs.isdirectory(dest) then
    dest = to_dir .. "/" .. tostring(os.time()) .. "-" .. basename
    if suffix then
      dest = dest .. suffix
    end
  end
  if not fs.rename(from_path, dest) then
    return false, dest
  end
  return true, dest
end

function M.process_pending_for_mission(ops, project_root, mission, opts)
  opts = type(opts) == "table" and opts or {}
  local fs = M.with_fs(opts.fs)
  local max_actions = math.max(1, tonumber(opts.max_actions) or MAX_ACTIONS_PER_TICK)
  local mission_safe = safe_name(mission and (mission.safe_name or mission.name or mission.mission_id))
  if mission_safe:match("^mission%-") then
    mission_safe = mission_safe:gsub("^mission%-", "")
  end
  if type(mission) == "table" and type(mission.mission_id) == "string" then
    local from_id = mission.mission_id:match("^mission:(.+)$")
    if from_id then
      mission_safe = safe_name(from_id)
    end
  end

  local ok_dirs, dir_err, dirs = M.ensure_dispatch_dirs(project_root, mission_safe, {
    fs = fs,
    instruction_directory = opts.instruction_directory,
  })
  if not ok_dirs then
    return {
      processed = 0,
      succeeded = 0,
      failed = 0,
      errors = { dir_err or "dispatch dirs unavailable" },
      mission = mission and (mission.name or mission.mission_id),
    }
  end

  local files = fs.readdir(dirs.pending)
  table.sort(files)
  local summary = {
    processed = 0,
    succeeded = 0,
    failed = 0,
    errors = {},
    mission = mission and (mission.name or mission.mission_id),
    files = {},
  }
  local actions_left = max_actions

  for _, name in ipairs(files) do
    if actions_left <= 0 then
      break
    end
    if type(name) == "string" and name:match("%.json$") then
      local path = dirs.pending .. "/" .. name
      local raw = fs.readfile(path)
      local doc, parse_err = M.parse_dispatch_document(raw or "")
      if not doc then
        summary.processed = summary.processed + 1
        summary.failed = summary.failed + 1
        table.insert(summary.errors, name .. ": " .. tostring(parse_err))
        fs.writefile(path .. ".err", tostring(parse_err))
        move_file(fs, path, dirs.failed, name)
        move_file(fs, path .. ".err", dirs.failed, name, ".err")
        table.insert(summary.files, { name = name, ok = false, error = parse_err })
      else
        local file_ok = true
        local file_errors = {}
        for _, action in ipairs(doc.actions) do
          if actions_left <= 0 then
            break
          end
          actions_left = actions_left - 1
          summary.processed = summary.processed + 1
          local applied, apply_err = M.apply_action(ops, mission, action)
          if applied == false then
            file_ok = false
            summary.failed = summary.failed + 1
            table.insert(file_errors, apply_err or "action failed")
            table.insert(summary.errors, name .. ": " .. tostring(apply_err or "action failed"))
          else
            summary.succeeded = summary.succeeded + 1
          end
        end
        if file_ok then
          move_file(fs, path, dirs.done, name)
          table.insert(summary.files, { name = name, ok = true })
        else
          fs.writefile(path .. ".err", table.concat(file_errors, "\n"))
          move_file(fs, path, dirs.failed, name)
          move_file(fs, path .. ".err", dirs.failed, name, ".err")
          table.insert(summary.files, { name = name, ok = false, error = table.concat(file_errors, "; ") })
        end
      end
    end
  end

  return summary
end

function M.process_project(ops, project_root, missions, opts)
  opts = type(opts) == "table" and opts or {}
  missions = type(missions) == "table" and missions or {}
  local combined = {
    processed = 0,
    succeeded = 0,
    failed = 0,
    errors = {},
    missions = {},
  }
  local actions_left = math.max(1, tonumber(opts.max_actions) or MAX_ACTIONS_PER_TICK)
  for _, mission in ipairs(missions) do
    if actions_left <= 0 then
      break
    end
    local summary = M.process_pending_for_mission(ops, project_root, mission, {
      fs = opts.fs,
      instruction_directory = opts.instruction_directory,
      max_actions = actions_left,
    })
    actions_left = actions_left - (summary.processed or 0)
    combined.processed = combined.processed + (summary.processed or 0)
    combined.succeeded = combined.succeeded + (summary.succeeded or 0)
    combined.failed = combined.failed + (summary.failed or 0)
    for _, err in ipairs(summary.errors or {}) do
      table.insert(combined.errors, err)
    end
    table.insert(combined.missions, summary)
  end
  return combined
end

--- Help text embedded in Manager instructions.
function M.manager_dispatch_help(project_root, mission_safe, instruction_directory)
  local dirs = M.dispatch_dirs(project_root, mission_safe, instruction_directory)
  local pending = dirs and dirs.pending or ".agents/codux/missions/<mission>/dispatch/pending"
  return table.concat({
    "To activate worker roles, write a JSON file into:",
    pending,
    "",
    "Example start_and_prompt.json:",
    "{",
    '  "version": 1,',
    '  "source": "manager",',
    '  "actions": [',
    "    {",
    '      "op": "start_and_prompt",',
    '      "role": "Agent",',
    '      "prompt": "Implement the next scoped task. Stay in plan mode first."',
    "    }",
    "  ]",
    "}",
    "",
    "Supported ops: start, prompt, start_and_prompt, create_role, update_focus.",
    "Codux processes pending files while Mission Control is open (or via :CoduxMissionProcessDispatch).",
  }, "\n")
end

-- Expose limits for tests.
M.MAX_PROMPT_CHARS = MAX_PROMPT_CHARS
M.MAX_ACTIONS_PER_FILE = MAX_ACTIONS_PER_FILE
M.MAX_ACTIONS_PER_TICK = MAX_ACTIONS_PER_TICK
M.safe_name = safe_name

return M
