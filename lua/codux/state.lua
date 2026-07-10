local M = {}

local function ui_subtable(flat_prefix, fields)
  local sub = {}
  for _, field in ipairs(fields) do
    sub[field] = nil
  end
  -- defaults that are not nil
  if flat_prefix == "workspace_manager" then
    sub.action_items = {}
    sub.items = {}
    sub.query = ""
    sub.focus_match = false
    sub.search_confirmed = false
    if type(vim) == "table" and type(vim.api) == "table" and type(vim.api.nvim_create_namespace) == "function" then
      sub.ns = vim.api.nvim_create_namespace("codux.workspace_manager")
    else
      sub.ns = 0
    end
  elseif flat_prefix == "mission_dashboard" then
    sub.action_items = {}
    sub.items = {}
    sub.lines = {}
    sub.selectable_rows = {}
    sub.query = ""
    sub.focus_match = false
    sub.search_confirmed = false
  end
  return sub
end

local WORKSPACE_MANAGER_FIELDS = {
  "buf",
  "win",
  "footer_buf",
  "footer_win",
  "search_buf",
  "search_win",
  "command_buf",
  "command_win",
  "action_buf",
  "action_win",
  "action_items",
  "action_workspace",
  "items",
  "query",
  "best_match_index",
  "selected_index",
  "focus_match",
  "search_confirmed",
  "project_root",
  "refresh_timer",
  "ns",
}

local MISSION_DASHBOARD_FIELDS = {
  "buf",
  "win",
  "search_buf",
  "search_win",
  "command_buf",
  "command_win",
  "action_buf",
  "action_win",
  "action_items",
  "action_mission",
  "action_workspace",
  "action_kind",
  "items",
  "lines",
  "selectable_rows",
  "query",
  "best_match_row",
  "selected_row",
  "focus_match",
  "search_confirmed",
  "project_root",
  "output_buf",
  "output_win",
}

local function flat_ui_key(key)
  if type(key) ~= "string" then
    return nil, nil
  end
  local field = key:match("^workspace_manager_(.+)$")
  if field then
    return "workspace_manager", field
  end
  field = key:match("^mission_dashboard_(.+)$")
  if field then
    return "mission_dashboard", field
  end
  return nil, nil
end

--- Nest manager/dashboard UI state while keeping flat key access for call sites.
function M.with_ui_proxy(state)
  if type(state) ~= "table" then
    return state
  end
  if getmetatable(state) and getmetatable(state).__codux_ui_proxy then
    return state
  end

  if type(state.workspace_manager) ~= "table" then
    state.workspace_manager = ui_subtable("workspace_manager", WORKSPACE_MANAGER_FIELDS)
  end
  if type(state.mission_dashboard) ~= "table" then
    state.mission_dashboard = ui_subtable("mission_dashboard", MISSION_DASHBOARD_FIELDS)
  end

  -- Migrate any flat keys already present on the root table into the nest.
  for _, field in ipairs(WORKSPACE_MANAGER_FIELDS) do
    local flat = "workspace_manager_" .. field
    if rawget(state, flat) ~= nil and state.workspace_manager[field] == nil then
      state.workspace_manager[field] = rawget(state, flat)
      rawset(state, flat, nil)
    end
  end
  for _, field in ipairs(MISSION_DASHBOARD_FIELDS) do
    local flat = "mission_dashboard_" .. field
    if rawget(state, flat) ~= nil and state.mission_dashboard[field] == nil then
      state.mission_dashboard[field] = rawget(state, flat)
      rawset(state, flat, nil)
    end
  end

  return setmetatable(state, {
    __codux_ui_proxy = true,
    __index = function(t, key)
      local nest, field = flat_ui_key(key)
      if nest then
        local sub = rawget(t, nest)
        if type(sub) == "table" then
          return sub[field]
        end
        return nil
      end
      return nil
    end,
    __newindex = function(t, key, value)
      local nest, field = flat_ui_key(key)
      if nest then
        local sub = rawget(t, nest)
        if type(sub) ~= "table" then
          sub = {}
          rawset(t, nest, sub)
        end
        sub[field] = value
        return
      end
      rawset(t, key, value)
    end,
  })
end

function M.initial()
  local state = {
    buf = nil,
    win = nil,
    job_id = nil,
    mode = "not running",
    working_buf = nil,
    working_win = nil,
    working_timer = nil,
    working_idle_timer = nil,
    working_frame = 1,
    agent_working = false,
    last_working_activity = 0,
    last_prompt_line = nil,
    token_usage = {
      five_hour_percent = nil,
      weekly_percent = nil,
      tpm_percent = nil,
      rpm_percent = nil,
      usage_provider = nil,
      last_error = nil,
      in_flight = false,
      in_flight_provider = nil,
      job_id = nil,
      stdout = "",
      initialized = false,
      timeout_timer = nil,
      refresh_timer = nil,
      by_provider = {
        codex = {},
        grok = {},
      },
    },
    terminal_attached_buf = nil,
    terminal_prompt_input = "",
    terminal_prompt_tracking_valid = true,
    terminal_mode_sync_pending = false,
    permission_profile = "default",
    last_permission_profile = "default",
    agent_provider = "codex",
    last_agent_provider = "codex",
    workspace = nil,
    workspace_manager = ui_subtable("workspace_manager", WORKSPACE_MANAGER_FIELDS),
    mission_dashboard = ui_subtable("mission_dashboard", MISSION_DASHBOARD_FIELDS),
    workspace_instruction_ignore_warnings = {},
    workspace_target_signature = nil,
    workspace_target_update_pending = false,
    closing_popup = false,
    focus_lock_pending = false,
    focus_lock_autocmd = nil,
    exiting_jobs = {},
    pending_delete_buffers = {},
    installed_mappings = {},
  }

  return M.with_ui_proxy(state)
end

return M
