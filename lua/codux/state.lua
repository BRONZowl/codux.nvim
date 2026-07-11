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
  -- list chrome
  "buf",
  "win",
  "footer_buf",
  "footer_win",
  "search_buf",
  "search_win",
  "command_buf",
  "command_win",
  -- action palette
  "action_buf",
  "action_win",
  "action_items",
  "action_workspace",
  -- list state
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
  -- list chrome
  "buf",
  "win",
  "search_buf",
  "search_win",
  "command_buf",
  "command_win",
  "command_bar_buf",
  "command_bar_win",
  -- action palette
  "action_buf",
  "action_win",
  "action_items",
  "action_mission",
  "action_workspace",
  "action_kind",
  "action_sink_buf",
  "action_sink_win",
  -- list state
  "items",
  "lines",
  "selectable_rows",
  "query",
  "best_match_row",
  "selected_row",
  "focus_match",
  "search_confirmed",
  "project_root",
  -- output panel
  "output_buf",
  "output_win",
  "output_buf_kind",
  "output_entry",
  "output_key",
  "output_blocked_key",
  "output_job",
  "output_preview",
  "output_generation",
  "output_replacing_buf",
  "output_retry_generation",
  "output_retry_key",
  "output_control",
  "output_control_key",
  "output_control_mouse",
  "output_control_cursor",
  "output_terminal_controller",
  "output_terminal_state",
  -- window chrome / timers / caches
  "monitor_timer",
  "resize_augroup",
  "saved_mouse",
  "saved_guicursor",
  "branch_cache",
  "dirty_cache",
  "last_dispatch",
  "token_usage_provider",
  "token_usage_refreshed_at",
  "token_usage_refreshed_at_by_provider",
}

--- Resolve a UI field key for nested mission/workspace state.
--- Accepts nested flat-style keys ("mission_dashboard_win") for dynamic accessors
--- (dashboard_search, action_palette) and returns the nest table + field name.
function M.ui_slot(state, key)
  if type(state) ~= "table" or type(key) ~= "string" or key == "" then
    return nil, nil
  end

  -- Lua patterns do not support | alternation; match each nest prefix explicitly.
  local field = key:match("^mission_dashboard_(.+)$")
  if field then
    local sub = state.mission_dashboard
    if type(sub) ~= "table" then
      sub = {}
      state.mission_dashboard = sub
    end
    return sub, field
  end

  field = key:match("^workspace_manager_(.+)$")
  if field then
    local sub = state.workspace_manager
    if type(sub) ~= "table" then
      sub = {}
      state.workspace_manager = sub
    end
    return sub, field
  end

  return state, key
end

function M.get(state, key)
  local slot, field = M.ui_slot(state, key)
  if not slot then
    return nil
  end
  return slot[field]
end

function M.set(state, key, value)
  local slot, field = M.ui_slot(state, key)
  if not slot then
    return
  end
  slot[field] = value
end

--- Ensure nested UI tables exist on an existing state object (controllers/tests).
function M.ensure_ui_nests(state)
  if type(state) ~= "table" then
    return state
  end
  if type(state.workspace_manager) ~= "table" then
    state.workspace_manager = ui_subtable("workspace_manager", WORKSPACE_MANAGER_FIELDS)
  end
  if type(state.mission_dashboard) ~= "table" then
    state.mission_dashboard = ui_subtable("mission_dashboard", MISSION_DASHBOARD_FIELDS)
  end
  return state
end

function M.initial()
  return {
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
end

return M
