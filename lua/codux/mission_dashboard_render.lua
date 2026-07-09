local M = {}

local function entry_key(entry)
  entry = type(entry) == "table" and entry or {}
  return tostring(entry.safe_name or entry.name or entry.mission_role or "")
end

local function mission_cache_key(root, mission)
  mission = type(mission) == "table" and mission or {}
  return tostring(root or "") .. "\0" .. tostring(mission.mission_id or mission.name or "")
end

local function role_cache_key(entry)
  entry = type(entry) == "table" and entry or {}
  return table.concat({
    tostring(entry.project_root or entry.worktree_path or ""),
    tostring(entry.safe_name or entry.name or entry.mission_role or ""),
    tostring(entry.worktree_branch or ""),
    tostring(entry.worktree_base or ""),
    tostring(entry.worktree_base_commit or ""),
  }, "\0")
end

function M.mission_filter_score(controller, mission, query)
  mission = type(mission) == "table" and mission or {}
  query = tostring(query or "")
  if query == "" then
    return nil
  end

  local best = nil
  local best_kind = "mission"
  local best_entry = nil
  for _, value in ipairs({ mission.name, mission.mission_id }) do
    local score = controller.workspace_ui.fuzzy_workspace_score(value, query)
    if score and (not best or score < best) then
      best = score
      best_kind = "mission"
      best_entry = nil
    end
  end

  for _, entry in ipairs(type(mission.roles) == "table" and mission.roles or {}) do
    for _, value in ipairs({ entry.mission_role, entry.name, entry.safe_name }) do
      local score = controller.workspace_ui.fuzzy_workspace_score(value, query)
      if score and (not best or score < best) then
        best = score
        best_kind = "role"
        best_entry = entry
      end
    end
  end

  return best, best_kind, best_entry
end

function M.filter_missions(controller, missions, query)
  missions = type(missions) == "table" and missions or {}
  query = tostring(query or "")
  if query == "" then
    return missions
  end

  local scored = {}
  for _, mission in ipairs(missions) do
    local score, match_kind, match_entry = M.mission_filter_score(controller, mission, query)
    if score then
      table.insert(scored, {
        mission = mission,
        score = score,
        match_kind = match_kind,
        match_entry_key = match_entry and entry_key(match_entry) or nil,
      })
    end
  end

  table.sort(scored, function(left, right)
    if left.score == right.score then
      return tostring(left.mission.name or left.mission.mission_id):lower()
        < tostring(right.mission.name or right.mission.mission_id):lower()
    end
    return left.score < right.score
  end)

  local filtered = {}
  for _, item in ipairs(scored) do
    item.mission._codux_match_kind = item.match_kind
    item.mission._codux_match_entry_key = item.match_entry_key
    table.insert(filtered, item.mission)
  end
  return filtered
end

function M.dashboard_now(_, opts)
  opts = type(opts) == "table" and opts or {}
  return tonumber(opts.now) or os.time()
end

function M.cached_mission_dirty_roles(controller, root, mission, now)
  local cache = type(controller.state.mission_dashboard_dirty_cache) == "table"
      and controller.state.mission_dashboard_dirty_cache
    or {}
  controller.state.mission_dashboard_dirty_cache = cache
  local key = mission_cache_key(root, mission)
  local cached = cache[key]
  if type(cached) == "table" and now - (tonumber(cached.checked_at) or 0) <= 15 then
    return cached.roles, cached.error
  end

  local name = mission.name or mission.mission_id
  local roles, error_message = controller.mission_dirty_roles(name, root)
  roles = type(roles) == "table" and roles or {}
  cache[key] = {
    checked_at = now,
    roles = roles,
    error = error_message,
  }
  return roles, error_message
end

function M.cached_workspace_branch_state(controller, entry, now)
  local cache = type(controller.state.mission_dashboard_branch_cache) == "table"
      and controller.state.mission_dashboard_branch_cache
    or {}
  controller.state.mission_dashboard_branch_cache = cache
  local key = role_cache_key(entry)
  local cached = cache[key]
  if type(cached) == "table" and now - (tonumber(cached.checked_at) or 0) <= 15 then
    return cached.state
  end

  local state = controller.workspace_branch_state(entry)
  state = type(state) == "table" and state or {}
  cache[key] = {
    checked_at = now,
    state = state,
  }
  return state
end

function M.role_freshness(controller, entry, now)
  entry = type(entry) == "table" and entry or {}
  if entry.status == "inactive" then
    return "--"
  end

  local timestamp = controller.workspace_ui.activity_timestamp(entry)
  local seconds = controller.workspace_ui.parse_timestamp(timestamp)
  if not seconds then
    return "stale"
  end

  local elapsed = math.max(0, now - seconds)
  if elapsed < 300 then
    return "live"
  end
  if elapsed < 1800 then
    return "quiet"
  end
  return "stale"
end

function M.mission_dirty_status_by_role(controller, root, mission, now)
  local dirty_roles = M.cached_mission_dirty_roles(controller, root, mission, now)
  local dirty_by_role = {}
  for _, role in ipairs(dirty_roles) do
    local label = type(role) == "table" and (role.name or role.safe_name or role.label) or role
    local reason = type(role) == "table" and role.reason or "dirty"
    dirty_by_role[tostring(label or "")] = reason
  end
  return dirty_by_role
end

function M.mission_workspace_details(controller, entry, dirty_by_role, now)
  entry = type(entry) == "table" and entry or {}
  dirty_by_role = type(dirty_by_role) == "table" and dirty_by_role or {}
  local status = entry.status or "inactive"
  local dirty_status = dirty_by_role[tostring(entry.name or "")]
    or dirty_by_role[tostring(entry.safe_name or "")]
    or dirty_by_role[tostring(entry.mission_role or "")]
    or nil
  local branch_state = M.cached_workspace_branch_state(controller, entry, now)
  local window_status = "not running"
  if status ~= "inactive" then
    window_status = type(entry.window_id) == "string" and entry.window_id ~= "" and "open" or "missing"
  end

  local worktree = "unknown"
  local worktree_status = "unknown"
  if entry.workspace_kind == "worktree" then
    worktree = "yes"
    worktree_status = dirty_status == "dirty" and "dirty" or dirty_status == "unknown" and "unknown" or "clean"
  elseif type(entry.workspace_kind) == "string" and entry.workspace_kind ~= "" then
    worktree = "no"
    worktree_status = "not a worktree"
  end

  local freshness = M.role_freshness(controller, entry, now)
  local needs_review = status == "question"
    or dirty_status == "dirty"
    or dirty_status == "unknown"
    or ((status == "active" or status == "idle") and freshness == "stale")
    or (status ~= "inactive" and window_status == "missing")
    or branch_state.merged == true

  return {
    last_activity = controller.workspace_ui
      .relative_age_label(controller.workspace_ui.activity_timestamp(entry), now)
      :gsub("^%-%-$", "unknown"),
    needs_review = needs_review and "yes" or "no",
    worktree_status = worktree_status,
    window_status = window_status,
    worktree = worktree,
    branch = entry.worktree_branch or entry.git_branch or "none",
    cleanup_status = branch_state.merged and "merged" or "not ready",
  }
end

function M.permission_profile_label(_, entry)
  entry = type(entry) == "table" and entry or {}
  local is_grok = entry.agent_provider == "grok"
  local provider = is_grok and "Grok" or ""
  local profile = entry.permission_profile or "default"
  if profile == "default" then
    return is_grok and (provider .. " Default") or "Default"
  end
  if profile == "auto" then
    return is_grok and (provider .. " Auto") or "Autopilot"
  end
  if profile == "danger" then
    return is_grok and (provider .. " Full") or "Full Access"
  end
  return is_grok and (provider .. " " .. tostring(profile)) or tostring(profile)
end

function M.mission_mode_label(_, entry)
  entry = type(entry) == "table" and entry or {}
  if entry.status == "inactive" then
    return "not set"
  end
  if entry.codex_mode == "execute" then
    return "execute"
  end
  if entry.codex_mode == "plan" then
    return "plan"
  end
  return "not set"
end

function M.refresh_dashboard_token_usage(controller, force)
  local now = tonumber(controller.token_usage_now_ms()) or (os.time() * 1000)
  local refresh_ms = tonumber(controller.token_usage_refresh_ms()) or 60000
  refresh_ms = math.max(10000, refresh_ms)
  local last = tonumber(controller.state.mission_dashboard_token_usage_refreshed_at)
  if not force and last and now - last < refresh_ms then
    return false
  end

  controller.state.mission_dashboard_token_usage_refreshed_at = now
  return controller.refresh_token_usage(force == true)
end

function M.missions_for_root(controller, root)
  if type(controller.missions_for_project) == "function" then
    return controller.missions_for_project(root)
  end

  local entries, error_message = controller.workspace_entries_for_project(root)
  if error_message then
    return nil, error_message
  end
  return controller.mission.group_entries(entries)
end

return M
