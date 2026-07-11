local M = {}
M.__index = M

local control_defaults = require("codux.mission_control_defaults")
local dashboard_actions = require("codux.mission_dashboard_actions")
local dashboard_action_palette = require("codux.mission_dashboard_action_palette")
local dashboard_command_bar = require("codux.mission_dashboard_command_bar")
local dashboard_layout = require("codux.mission_dashboard_layout")
local dashboard_render = require("codux.mission_dashboard_render")
local dashboard_search_controller = require("codux.mission_dashboard_search_controller")
local mission_dashboard = require("codux.mission_dashboard")
local dashboard_selection = require("codux.mission_dashboard_selection")
local dashboard_viewport = require("codux.mission_dashboard_viewport")
local dashboard_windows = require("codux.mission_dashboard_windows")
local mission_objective_editor = require("codux.mission_objective_editor")
local mission_preview = require("codux.mission_preview")
local providers = require("codux.providers")
local text_util = require("codux.text")
local ui = require("codux.ui")
local output_panel = require("codux.mission_output_panel")

local trim = text_util.trim

local dashboard_command_items = mission_dashboard.command_items()

function M.new(opts)
  return setmetatable(control_defaults.normalize(opts), M)
end

function M:action_palette_controller()
  if self._action_palette then
    return self._action_palette
  end
  self._action_palette = dashboard_action_palette.new(self)
  return self._action_palette
end

function M:dashboard_search_controller()
  if self._search then
    return self._search
  end
  self._search = dashboard_search_controller.new(self)
  return self._search
end

function M:window_height()
  return dashboard_layout.window_height(self)
end

function M:window_width()
  return dashboard_layout.window_width(self)
end

function M:mission_filter_score(mission, query)
  return dashboard_render.mission_filter_score(self, mission, query)
end

function M:filter_missions(missions, query)
  return dashboard_render.filter_missions(self, missions, query)
end

function M:objective_editor_config(line_count, opts)
  return dashboard_layout.objective_editor_config(self, line_count, opts)
end

function M:preview_config(line_count)
  return dashboard_layout.preview_config(self, line_count)
end

function M:dashboard_workspace_preview_active(entry)
  return dashboard_layout.dashboard_workspace_preview_active(self, entry)
end

function M:dashboard_preview_mode(item)
  return dashboard_layout.dashboard_preview_mode(self, item)
end

function M:dashboard_preview_height(total_height, command_height, mode, dashboard_min_height)
  return dashboard_layout.dashboard_preview_height(self, total_height, command_height, mode, dashboard_min_height)
end

function M:dashboard_config(line_count, opts)
  return dashboard_layout.dashboard_config(self, line_count, opts)
end

function M:dashboard_search_config()
  return dashboard_layout.dashboard_search_config(self)
end

function M:dashboard_command_config(line_count)
  return dashboard_layout.dashboard_command_config(self, line_count)
end

function M:dashboard_output_config(line_count, opts)
  return dashboard_layout.dashboard_output_config(self, line_count, opts)
end

function M:resize_dashboard_stack(line_count, opts)
  return dashboard_layout.resize_dashboard_stack(self, line_count, opts)
end

function M:open_objective_editor(name, default_objective, opts)
  return mission_objective_editor.open(self, name, default_objective, opts)
end

function M:open_preview(mission)
  return mission_preview.open(self, mission)
end

function M:open_prompt(opts)
  opts = type(opts) == "table" and opts or {}
  local prompt = require("codux.ui").single_line_prompt
  return prompt({ prompt = "Codux mission: ", zindex = 80 }, function(input)
    local name = trim(input)
    if name == "" then
      return
    end
    self:open_mission_provider_menu(name, opts)
  end, {
    notify = self.notify,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
  })
end

function M:open_mission_provider_menu(name, opts)
  opts = type(opts) == "table" and opts or {}
  if type(self.select_provider_profile) == "function" then
    local agent_provider = providers.normalize_provider(opts.agent_provider)
    if not agent_provider and type(self.default_agent_provider) == "function" then
      agent_provider = providers.normalize_provider(self.default_agent_provider())
    end
    return self.select_provider_profile({
      agent_provider = agent_provider,
      provider_title = " Codux mission agent ",
      provider_filetype = "codux-mission-provider",
      provider_zindex = 81,
      provider_cancel_desc = "Cancel Codux Mission Provider",
      provider_create_error = "Failed to create Codux mission provider menu",
      provider_open_error = "Failed to open Codux mission provider menu",
      profile_title = " Codux mission profile ",
      profile_filetype = "codux-mission-profile",
      profile_zindex = 82,
      profile_cancel_desc = "Cancel Codux Mission Profile",
      profile_create_error = "Failed to create Codux mission profile menu",
      profile_open_error = "Failed to open Codux mission profile menu",
      on_select = function(choice)
        if type(choice) ~= "table" then
          return false
        end
        return self:open_objective_editor(name, nil, {
          agent_provider = choice.agent_provider,
          permission_profile = choice.profile,
        })
      end,
    })
  end

  return ui.key_choice_menu({
    title = " Codux mission agent ",
    filetype = "codux-mission-provider",
    zindex = 81,
    choices = providers.provider_choices(),
    cancel_desc = "Cancel Codux Mission Provider",
    create_error = "Failed to create Codux mission provider menu",
    open_error = "Failed to open Codux mission provider menu",
  }, function(choice)
    if type(choice) ~= "table" then
      return false
    end
    return self:open_objective_editor(name, nil, { agent_provider = choice.agent_provider })
  end, {
    notify = self.notify,
    create_scratch_buffer = self.ui.create_scratch_buffer,
    set_lines = self.ui.set_lines,
    set_window_options = self.ui.set_window_options,
    close_window = self.ui.close_window,
    delete_buffer = self.ui.delete_buffer,
    set_buffer_keymap = self.set_buffer_keymap,
    bind_close_keys = self.bind_close_keys,
  })
end

function M:dashboard_now(opts)
  return dashboard_render.dashboard_now(self, opts)
end

function M:cached_mission_dirty_roles(root, mission, now)
  return dashboard_render.cached_mission_dirty_roles(self, root, mission, now)
end

function M:cached_workspace_branch_state(entry, now)
  return dashboard_render.cached_workspace_branch_state(self, entry, now)
end

function M:role_freshness(entry, now)
  return dashboard_render.role_freshness(self, entry, now)
end

function M:mission_dirty_status_by_role(root, mission, now)
  return dashboard_render.mission_dirty_status_by_role(self, root, mission, now)
end

function M:mission_workspace_details(entry, dirty_by_role, now)
  return dashboard_render.mission_workspace_details(self, entry, dirty_by_role, now)
end

function M:permission_profile_label(entry)
  return dashboard_render.permission_profile_label(self, entry)
end

function M:mission_mode_label(entry)
  return dashboard_render.mission_mode_label(self, entry)
end

function M:mission_dashboard_line(mission, counts, status, dashboard_width)
  return mission_dashboard.mission_line(self, mission, counts, status, dashboard_width)
end

function M:mission_role_header_line(dashboard_width)
  return mission_dashboard.role_header_line(self, dashboard_width)
end

function M:mission_role_table_width(dashboard_width)
  return mission_dashboard.role_table_width(dashboard_width)
end

function M:mission_role_column_widths(dashboard_width)
  return mission_dashboard.role_column_widths(dashboard_width)
end

function M:mission_role_table_line(columns, values)
  return mission_dashboard.role_table_line(self.workspace_ui, columns, values)
end

function M:mission_role_line(entry, dashboard_width, now, dirty_by_role)
  return mission_dashboard.role_line(self, entry, dashboard_width, now, dirty_by_role)
end

function M:dashboard_row_highlight_range(line)
  return mission_dashboard.row_highlight_range(line)
end

function M:dashboard_command_lines(dashboard_width)
  return mission_dashboard.command_lines(self, dashboard_width)
end

function M:dashboard_token_usage_line(dashboard_width)
  return mission_dashboard.token_usage_line(self, dashboard_width)
end

function M:dashboard_min_height_for_lines(lines)
  return mission_dashboard.min_height_for_lines(lines)
end

function M:refresh_dashboard_token_usage(force, opts)
  return dashboard_render.refresh_dashboard_token_usage(self, force, opts)
end

function M:dashboard_token_agent_provider()
  return dashboard_render.dashboard_token_agent_provider(self)
end

function M:dashboard_token_usage_provider()
  return self:dashboard_token_agent_provider()
end

function M:missions_for_root(root)
  return dashboard_render.missions_for_root(self, root)
end

function M:dashboard_lines(root, opts)
  return mission_dashboard.lines(self, root, opts)
end

function M:mission_for_name(root, name)
  local missions, error_message = self:missions_for_root(root)
  if error_message then
    return nil, error_message
  end

  return self.mission.find_mission(missions, name)
end

local function open_saved_mission_text_editor(controller, name, root, opts)
  opts = type(opts) == "table" and opts or {}
  root = root or controller.project_root()
  local mission, mission_error = controller:mission_for_name(root, name)
  if not mission then
    controller.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  return controller:open_objective_editor(mission.name, opts.value(mission), {
    title = opts.title,
    footer = " Ctrl-s/:w save | Ctrl-q cancel ",
    on_save = function(_, value)
      return opts.update(mission.name, value, root)
    end,
  })
end

function M:open_saved_objective_editor(name, root)
  return open_saved_mission_text_editor(self, name, root, {
    title = " Edit Codux Mission Objective ",
    value = function(mission)
      return mission.objective
    end,
    update = self.update_mission_objective,
  })
end

function M:open_saved_focus_editor(name, root)
  return open_saved_mission_text_editor(self, name, root, {
    title = " Edit Codux Mission Focus ",
    value = function(mission)
      return mission.focus_packet or ""
    end,
    update = self.update_mission_focus_packet,
  })
end

function M:objective_preview_config(line_count)
  return dashboard_layout.objective_preview_config(self, line_count)
end

function M:view_mission_objective(mission)
  mission = type(mission) == "table" and mission or self:selected_mission()
  if not mission then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end

  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-mission-objective-preview",
    modifiable = true,
  })
  if not bufnr then
    self.notify("Failed to create Codux mission objective preview", vim.log.levels.ERROR)
    return false
  end
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })

  local lines = vim.split(tostring(mission.objective or "No objective"), "\n", { plain = true })
  if #lines == 0 then
    lines = { "No objective" }
  end
  self.ui.set_lines(bufnr, lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:objective_preview_config(#lines))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux mission objective preview", vim.log.levels.ERROR)
    return false
  end

  self.ui.set_window_options(win, {
    wrap = true,
    linebreak = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  local function close_preview()
    self.ui.close_window(win)
    self.ui.delete_buffer(bufnr)
  end
  self.bind_close_keys(bufnr, close_preview, "Close Codux Mission Objective", "n", { escape = true, q = true })
  return true
end

function M:delete_saved_mission(name, root, opts)
  opts = type(opts) == "table" and opts or {}
  root = root or self.project_root()
  local mission, mission_error = self:mission_for_name(root, name)
  if not mission then
    self.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  if opts.confirm ~= false and not self:confirm_delete_mission(mission, root) then
    return false
  end

  local ok = self.delete_mission(mission.name or mission.mission_id, root)
  local dashboard_root = self.state.mission_dashboard_project_root or root
  if ok and dashboard_root == root and self:dashboard_is_visible() then
    self:update_dashboard_after_mission_delete(dashboard_root)
  end
  return ok
end

function M:close_saved_mission(name, root)
  root = root or self.project_root()
  local mission, mission_error = self:mission_for_name(root, name)
  if not mission then
    self.notify(mission_error or "mission not found", vim.log.levels.ERROR)
    return false
  end

  return self.close_mission(mission.name or mission.mission_id, root)
end

function M:confirm_delete_mission(mission, root)
  mission = type(mission) == "table" and mission or {}
  local name = mission.name or mission.mission_id
  local dirty_roles = self.mission_dirty_roles(name, root)
  dirty_roles = type(dirty_roles) == "table" and dirty_roles or {}

  local message = "Delete Codux mission " .. tostring(name) .. "?\n\n"
    .. "This will permanently remove every role workspace, Git worktree, instruction file, and branch."

  if #dirty_roles > 0 then
    local labels = {}
    for _, role in ipairs(dirty_roles) do
      local label = type(role) == "table" and (role.name or role.safe_name or role.label) or role
      local reason = type(role) == "table" and role.reason or nil
      if reason == "unknown" then
        label = tostring(label) .. " (status unknown)"
      end
      table.insert(labels, "  - " .. tostring(label))
    end
    message = message
      .. "\n\nDirty or unknown role worktrees:\n"
      .. table.concat(labels, "\n")
      .. "\n\nForce delete will nuke uncommitted and untracked work."
  end

  local choice = vim.fn.confirm(message, "&Yes\n&No", 2)
  return choice == 1
end

function M:highlight_dashboard(bufnr, lines, items)
  return mission_dashboard.highlight(self, bufnr, lines, items)
end

function M:refresh_dashboard_highlight(lines, items)
  if not self.is_loaded_buf(self.state.mission_dashboard_buf) then
    return false
  end
  lines = type(lines) == "table" and lines or self.state.mission_dashboard_lines
  items = type(items) == "table" and items or self.state.mission_dashboard_items
  if type(lines) ~= "table" then
    return false
  end
  self:highlight_dashboard(self.state.mission_dashboard_buf, lines, items or {})
  return true
end

function M:highlight_command_bar(bufnr, lines)
  return dashboard_command_bar.highlight(self, bufnr, lines, dashboard_command_items)
end

function M:render_command_bar()
  return dashboard_command_bar.render(self)
end

function M:open_command_bar()
  return dashboard_command_bar.open(self)
end

function M:close_command_bar()
  return dashboard_command_bar.close(self)
end

function M:render_dashboard(opts)
  opts = type(opts) == "table" and opts or {}
  if not self.is_loaded_buf(self.state.mission_dashboard_buf) then
    return false
  end

  if opts.skip_token_refresh ~= true then
    self:refresh_dashboard_token_usage(false)
  end
  local root = self.state.mission_dashboard_project_root or self.project_root()
  local query = tostring(self.state.mission_dashboard_query or "")
  local selected = self:selected_item()
  local lines, items, selectable_rows, best_match_row = self:dashboard_lines(root, {
    query = query,
    selected_item = selected,
  })
  self.state.mission_dashboard_lines = lines
  self.state.mission_dashboard_items = items
  self.state.mission_dashboard_selectable_rows = selectable_rows
  self.state.mission_dashboard_best_match_row = best_match_row

  local selected_item = self:selected_item()
  local dashboard_min_height = self:dashboard_min_height_for_lines(lines)
  local preview_anchor = self:capture_output_preview_anchor()
  self:resize_dashboard_stack(#lines, { selected_item = selected_item, dashboard_min_height = dashboard_min_height })
  self.ui.set_lines(self.state.mission_dashboard_buf, lines, { modifiable = true })
  self:render_command_bar()
  self:render_output_panel(self:dashboard_output_entry(selected_item))
  if
    not self:restore_stationary_output_preview_anchor(opts.stationary_preview_anchor)
    and not self:restore_output_preview_anchor(preview_anchor)
  then
    self:reveal_selected_dashboard_row()
  end
  self:refresh_dashboard_highlight(lines, items)
  self.state.mission_dashboard_focus_match = false

  return true
end

function M:render_search()
  return self:dashboard_search_controller():render()
end

function M:update_query(query)
  return self:dashboard_search_controller():update_query(query)
end

function M:append_query(input)
  return self:dashboard_search_controller():append_query(input)
end

function M:delete_query_char()
  return self:dashboard_search_controller():delete_query_char()
end

function M:clear_query()
  return self:dashboard_search_controller():clear_query()
end

function M:selected_row()
  return dashboard_selection.selected_row(self)
end

function M:selected_item()
  return dashboard_selection.selected_item(self)
end

function M:selected_selectable_item()
  return dashboard_selection.selected_selectable_item(self)
end

function M:mission_list_focus_row()
  return dashboard_selection.mission_list_focus_row(self)
end

function M:focus_mission_list()
  return dashboard_selection.focus_mission_list(self)
end

function M:focus_search_input()
  return self:dashboard_search_controller():focus()
end

function M:toggle_search_list_focus()
  return self:dashboard_search_controller():toggle_list_focus()
end

function M:move_mission_selection(delta)
  return dashboard_selection.move_mission_selection(self, delta)
end

function M:capture_stationary_output_preview_anchor()
  return dashboard_viewport.capture_stationary_output_preview_anchor(self)
end

function M:capture_output_preview_anchor()
  return dashboard_viewport.capture_output_preview_anchor(self)
end

function M:restore_stationary_output_preview_anchor(anchor)
  return dashboard_viewport.restore_stationary_output_preview_anchor(self, anchor)
end

function M:restore_output_preview_anchor(anchor)
  return dashboard_viewport.restore_output_preview_anchor(self, anchor)
end

function M:reveal_output_preview_row()
  return dashboard_viewport.reveal_output_preview_row(self)
end

function M:reveal_selected_dashboard_row()
  return dashboard_viewport.reveal_selected_dashboard_row(self)
end

function M:open_search_input(opts)
  return self:dashboard_search_controller():open(opts)
end

function M:lock_dashboard_mouse()
  return dashboard_windows.lock_dashboard_mouse(self)
end

function M:restore_dashboard_mouse()
  return dashboard_windows.restore_dashboard_mouse(self)
end

function M:lock_dashboard_cursor()
  return dashboard_windows.lock_dashboard_cursor(self)
end

function M:restore_dashboard_cursor()
  return dashboard_windows.restore_dashboard_cursor(self)
end

function M:enable_output_control_mouse()
  return dashboard_windows.enable_output_control_mouse(self)
end

function M:relock_output_control_mouse()
  return dashboard_windows.relock_output_control_mouse(self)
end

function M:enable_output_control_cursor()
  return dashboard_windows.enable_output_control_cursor(self)
end

function M:relock_output_control_cursor()
  return dashboard_windows.relock_output_control_cursor(self)
end

function M:close_dashboard()
  return dashboard_windows.close_dashboard(self)
end

function M:stop_monitor_timer()
  return dashboard_windows.stop_monitor_timer(self)
end

function M:start_monitor_timer()
  return dashboard_windows.start_monitor_timer(self)
end

function M:open_command_sink()
  return dashboard_windows.open_command_sink(self)
end

function M:selected_mission()
  return dashboard_actions.selected_mission(self)
end

function M:selected_mission_or_notify()
  return dashboard_actions.selected_mission_or_notify(self)
end

function M:close_action_palette()
  return dashboard_actions.close_action_palette(self)
end

function M:action_palette_width()
  return dashboard_actions.action_palette_width(self)
end

function M:action_palette_config(target, item_count, kind)
  return dashboard_actions.action_palette_config(self, target, item_count, kind)
end

function M:render_action_palette()
  return dashboard_actions.render_action_palette(self)
end

function M:dashboard_is_visible()
  return dashboard_windows.dashboard_is_visible(self)
end

function M:refresh_loaded_dashboard()
  return dashboard_windows.refresh_loaded_dashboard(self)
end

function M:refresh_or_open_dashboard(root)
  return dashboard_windows.refresh_or_open_dashboard(self, root)
end

function M:mission_count(root)
  local missions, error_message = self:missions_for_root(root)
  if error_message then
    return nil, error_message
  end
  return #missions
end

function M:mission_residue_for_root(root)
  if type(self.mission_residue_for_project) ~= "function" then
    return { count = 0, empty_project_buckets = {}, leftover_directories = {} }, nil
  end
  return self.mission_residue_for_project(root)
end

function M:cleanup_empty_mission_residue(root)
  root = root or self.state.mission_dashboard_project_root or self.project_root()
  if type(self.cleanup_mission_residue) ~= "function" then
    self.notify("Codux mission residue cleanup is unavailable", vim.log.levels.WARN)
    return false
  end

  local ok, result = self.cleanup_mission_residue(root)
  if not ok then
    self.notify(result or "Failed to clean Codux mission residue", vim.log.levels.ERROR)
    return false
  end

  result = type(result) == "table" and result or {}
  self.notify(
    "Cleaned Codux mission residue: "
      .. tostring(result.removed_buckets or 0)
      .. " state buckets, "
      .. tostring(result.removed_directories or 0)
      .. " directories"
  )
  return self:refresh_loaded_dashboard(root)
end

function M:update_dashboard_after_mission_delete(root)
  local remaining_count, error_message = self:mission_count(root)
  if error_message then
    return self:refresh_loaded_dashboard(root)
  end
  if remaining_count == 0 then
    return self:close_dashboard()
  end
  return self:refresh_loaded_dashboard(root)
end

for _, method in ipairs({
  "edit_selected_mission",
  "edit_selected_mission_focus",
  "delete_selected_mission",
  "close_selected_mission",
  "start_selected_mission",
  "action_palette_target",
  "run_workspace_action",
  "run_mission_action",
  "run_action",
  "run_highlighted_action",
  "move_action_cursor",
  "open_action_palette_for",
  "selected_role_workspace_or_notify",
  "mission_context_for_workspace",
  "open_workspace_prompt",
  "workspace_question_pending",
  "open_workspace_question_answer",
  "open_question_option_input",
  "open_question_note_input",
  "open_workspace_prompt_input",
  "interrupt_workspace_action",
  "interrupt_selected_workspace",
  "switch_selected_workspace_mode",
  "switch_selected_workspace_profile",
  "rename_selected_role",
  "delete_role_workspace",
  "open_action_palette",
}) do
  M[method] = function(self, ...)
    return dashboard_actions[method](self, ...)
  end
end

function M:refresh_dashboard()
  self:close_dashboard()
  return self:open_dashboard()
end

function M:create_new_mission()
  return self:open_prompt()
end

function M:create_new_workspace(workspace)
  workspace = workspace or self.state.mission_dashboard_action_workspace or self:selected_role_workspace_or_notify()
  local mission_context = self:mission_context_for_workspace(workspace)
  if not mission_context then
    self.notify("No Codux mission selected", vim.log.levels.WARN)
    return false
  end

  return self.create_workspace_prompt(mission_context)
end

function M:bind_dashboard_commands(bufnr)
  self.bind_close_keys(bufnr, function()
    return self:close_dashboard()
  end, "Close Codux Missions", "n", { escape = true })
  self.set_buffer_keymap(bufnr, "n", "<Tab>", function()
    return self:toggle_search_list_focus()
  end, "Search/List Codux Missions", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "j", function()
    return self:move_mission_selection(1)
  end, "Next Codux Mission", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "k", function()
    return self:move_mission_selection(-1)
  end, "Previous Codux Mission", {
    nowait = true,
  })
  self.set_buffer_keymap(bufnr, "n", "m", function()
    return self:open_action_palette()
  end, "Open Codux Mission Menu")
  self.set_buffer_keymap(bufnr, "n", "n", function()
    return self:create_new_mission()
  end, "Create Codux Mission")
  self.set_buffer_keymap(bufnr, "n", "c", function()
    return self:cleanup_empty_mission_residue()
  end, "Clean Codux Mission Residue")
  self.set_buffer_keymap(bufnr, "n", "h", function()
    return self.doctor()
  end, "Run Codux Doctor")
  self.set_buffer_keymap(bufnr, "n", "<C-o>", function()
    return self:enter_output_control()
  end, "Control Codux Mission Role Output")
end

function M:open_dashboard(root)
  return dashboard_windows.open_dashboard(self, root)
end

for name, method in pairs(output_panel) do
  M[name] = method
end

return M
