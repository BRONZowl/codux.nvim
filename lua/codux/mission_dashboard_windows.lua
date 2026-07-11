local filetypes = require("codux.filetypes")
local ui = require("codux.ui")

local M = {}

local mission_control_filetypes = filetypes.mission_control

local function ensure_dashboard_cursor_highlight()
  if vim.api and type(vim.api.nvim_set_hl) == "function" then
    pcall(vim.api.nvim_set_hl, 0, "CoduxDashboardCursor", {
      fg = "NONE",
      bg = "NONE",
      blend = 100,
      nocombine = true,
    })
  end
end

function M.dashboard_is_visible(controller)
  return controller.is_loaded_buf(controller.state.mission_dashboard.buf)
end

function M.refresh_loaded_dashboard(controller)
  if not controller:dashboard_is_visible() then
    return false
  end
  return controller:render_dashboard()
end

function M.refresh_or_open_dashboard(controller, root)
  if controller:dashboard_is_visible() then
    return controller:render_dashboard()
  end
  return controller:open_dashboard(root)
end

function M.lock_dashboard_mouse(controller)
  if controller.state.mission_dashboard.saved_mouse == nil then
    controller.state.mission_dashboard.saved_mouse = vim.o.mouse
  end
  vim.o.mouse = ""
  return true
end

function M.restore_dashboard_mouse(controller)
  local saved = controller.state.mission_dashboard.saved_mouse
  controller.state.mission_dashboard.saved_mouse = nil
  controller.state.mission_dashboard.output_control_mouse = nil
  if saved ~= nil then
    vim.o.mouse = saved
  end
  return true
end

function M.lock_dashboard_cursor(controller)
  if controller.state.mission_dashboard.saved_guicursor == nil then
    controller.state.mission_dashboard.saved_guicursor = vim.o.guicursor
  end
  ensure_dashboard_cursor_highlight()
  vim.o.guicursor = "a:CoduxDashboardCursor"
  return true
end

function M.restore_dashboard_cursor(controller)
  local saved = controller.state.mission_dashboard.saved_guicursor
  controller.state.mission_dashboard.saved_guicursor = nil
  controller.state.mission_dashboard.output_control_cursor = nil
  if saved ~= nil then
    vim.o.guicursor = saved
  end
  return true
end

function M.enable_output_control_mouse(controller)
  vim.o.mouse = "a"
  controller.state.mission_dashboard.output_control_mouse = true
  return true
end

function M.relock_output_control_mouse(controller)
  if controller.state.mission_dashboard.output_control_mouse then
    vim.o.mouse = ""
    controller.state.mission_dashboard.output_control_mouse = nil
  end
  return true
end

function M.enable_output_control_cursor(controller)
  local saved = controller.state.mission_dashboard.saved_guicursor
  if saved ~= nil then
    vim.o.guicursor = saved
    controller.state.mission_dashboard.output_control_cursor = true
  end
  return true
end

function M.relock_output_control_cursor(controller)
  if controller.state.mission_dashboard.output_control_cursor then
    controller.state.mission_dashboard.output_control_cursor = nil
    if controller.state.mission_dashboard.saved_guicursor ~= nil then
      ensure_dashboard_cursor_highlight()
      vim.o.guicursor = "a:CoduxDashboardCursor"
    end
  end
  return true
end

function M.close_dashboard(controller)
  controller:stop_monitor_timer()
  if controller.state.mission_dashboard.resize_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, controller.state.mission_dashboard.resize_augroup)
    controller.state.mission_dashboard.resize_augroup = nil
  end
  controller:close_action_palette()
  controller:close_output_panel()
  controller:close_command_bar()
  controller.ui.close_window(controller.state.mission_dashboard.search_win)
  controller.ui.close_window(controller.state.mission_dashboard.command_win)
  controller.ui.close_window(controller.state.mission_dashboard.win)
  controller.ui.delete_buffer(controller.state.mission_dashboard.search_buf)
  controller.ui.delete_buffer(controller.state.mission_dashboard.command_bar_buf)
  controller.ui.delete_buffer(controller.state.mission_dashboard.command_buf)
  controller.ui.delete_buffer(controller.state.mission_dashboard.buf)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = controller.window_buffer(win)
    if controller.is_loaded_buf(bufnr) and mission_control_filetypes[controller.buffer_filetype(bufnr)] then
      controller.ui.close_window(win)
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if controller.is_loaded_buf(bufnr) and mission_control_filetypes[controller.buffer_filetype(bufnr)] then
      controller.ui.delete_buffer(bufnr)
    end
  end

  controller.state.mission_dashboard.buf = nil
  controller.state.mission_dashboard.win = nil
  controller.state.mission_dashboard.search_buf = nil
  controller.state.mission_dashboard.search_win = nil
  controller.state.mission_dashboard.command_buf = nil
  controller.state.mission_dashboard.command_win = nil
  controller.state.mission_dashboard.command_bar_buf = nil
  controller.state.mission_dashboard.command_bar_win = nil
  controller:clear_output_panel_state()
  controller.state.mission_dashboard.action_buf = nil
  controller.state.mission_dashboard.action_win = nil
  controller.state.mission_dashboard.action_items = {}
  controller.state.mission_dashboard.action_mission = nil
  controller.state.mission_dashboard.action_workspace = nil
  controller.state.mission_dashboard.action_kind = nil
  controller.state.mission_dashboard.items = {}
  controller.state.mission_dashboard.lines = {}
  controller.state.mission_dashboard.selectable_rows = {}
  controller.state.mission_dashboard.query = ""
  controller.state.mission_dashboard.best_match_row = nil
  controller.state.mission_dashboard.selected_row = nil
  controller.state.mission_dashboard.focus_match = false
  controller.state.mission_dashboard.search_confirmed = false
  controller.state.mission_dashboard.project_root = nil
  controller.state.mission_dashboard.resize_augroup = nil
  controller.state.mission_dashboard.token_usage_refreshed_at = nil
  controller:restore_dashboard_mouse()
  controller:restore_dashboard_cursor()
  return true
end

function M.stop_monitor_timer(controller)
  local timer = controller.state.mission_dashboard.monitor_timer
  controller.state.mission_dashboard.monitor_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

function M.start_monitor_timer(controller)
  if controller.state.mission_dashboard.monitor_timer then
    return true
  end

  local loop = vim.uv or vim.loop
  local timer = loop and type(loop.new_timer) == "function" and loop.new_timer() or nil
  if not timer then
    return false
  end

  controller.state.mission_dashboard.monitor_timer = timer
  local function tick()
    if
      not controller.is_valid_win(controller.state.mission_dashboard.win)
      or not controller.is_loaded_buf(controller.state.mission_dashboard.buf)
    then
      controller:stop_monitor_timer()
      return
    end
    if type(controller.process_mission_dispatch) == "function" then
      local summary = controller.process_mission_dispatch()
      if type(summary) == "table" then
        local actions = require("codux.mission_dashboard_actions")
        if type(actions.record_dispatch_summary) == "function" then
          actions.record_dispatch_summary(controller, summary)
        end
        if (summary.processed or 0) > 0 and type(controller.notify) == "function" then
          local mission_label =
            tostring(summary.missions and summary.missions[1] and summary.missions[1].mission or "mission")
          controller.notify(
            string.format(
              "Dispatched %d action(s) for %s (%d ok, %d failed)",
              tonumber(summary.processed) or 0,
              mission_label,
              tonumber(summary.succeeded) or 0,
              tonumber(summary.failed) or 0
            )
          )
        end
      end
    end
    controller:render_dashboard()
  end
  local scheduled_tick = type(vim.schedule_wrap) == "function" and vim.schedule_wrap(tick) or tick
  timer:start(1000, 1000, scheduled_tick)
  return true
end

function M.open_command_sink(controller)
  local bufnr, win = ui.open_hidden_command_sink({
    ui = controller.ui,
    filetype = "codux-missions-command",
    focusable = true,
    enter = true,
    on_create_buffer = function(target_bufnr)
      ui.disable_buffer_completion(target_bufnr, { is_loaded_buf = controller.is_loaded_buf })
    end,
    bind = function(target_bufnr)
      controller:bind_dashboard_commands(target_bufnr)
    end,
  })
  if not bufnr then
    return false
  end

  controller.state.mission_dashboard.command_buf = bufnr
  controller.state.mission_dashboard.command_win = win
  return true
end

function M.open_dashboard(controller, root)
  controller:close_dashboard()
  root = root or controller.project_root()
  local existing_count, count_error = controller:mission_count(root)
  if count_error then
    controller.notify(count_error, vim.log.levels.ERROR)
    return false
  end
  if existing_count == 0 then
    local residue, residue_error = controller:mission_residue_for_root(root)
    if residue_error then
      controller.notify(residue_error, vim.log.levels.ERROR)
      return false
    end
    if not residue or (tonumber(residue.count) or 0) == 0 then
      return controller:open_prompt()
    end
  end

  local lines, items, selectable_rows, best_match_row = controller:dashboard_lines(root)
  local initial_selected_item = items[selectable_rows[1]]
  local bufnr = controller.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions",
    modifiable = false,
  })
  if not bufnr then
    controller.notify("Failed to create Codux missions dashboard", vim.log.levels.ERROR)
    return false
  end
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })
  controller:lock_dashboard_mouse()
  controller:lock_dashboard_cursor()

  controller.ui.set_lines(bufnr, lines, { modifiable = true })
  controller.state.mission_dashboard.buf = bufnr
  controller.state.mission_dashboard.project_root = root
  controller.state.mission_dashboard.lines = lines
  controller.state.mission_dashboard.items = items
  controller.state.mission_dashboard.selectable_rows = selectable_rows
  controller.state.mission_dashboard.best_match_row = best_match_row
  controller.state.mission_dashboard.selected_row = selectable_rows[1]
  controller.state.mission_dashboard.query = ""
  controller.state.mission_dashboard.focus_match = false
  controller.state.mission_dashboard.search_confirmed = false
  controller:highlight_dashboard(bufnr, lines, items)
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, controller:dashboard_config(#lines, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    reserve_search_input = true,
    selected_item = initial_selected_item,
    dashboard_min_height = controller:dashboard_min_height_for_lines(lines),
  }))
  if not win_ok then
    controller:restore_dashboard_mouse()
    controller:restore_dashboard_cursor()
    controller.ui.delete_buffer(bufnr)
    controller.state.mission_dashboard.buf = nil
    controller.state.mission_dashboard.project_root = nil
    controller.state.mission_dashboard.lines = {}
    controller.state.mission_dashboard.items = {}
    controller.state.mission_dashboard.selectable_rows = {}
    controller.state.mission_dashboard.best_match_row = nil
    controller.state.mission_dashboard.selected_row = nil
    controller.state.mission_dashboard.query = ""
    controller.state.mission_dashboard.focus_match = false
    controller.state.mission_dashboard.search_confirmed = false
    controller.notify("Failed to open Codux missions dashboard", vim.log.levels.ERROR)
    return false
  end
  ensure_dashboard_cursor_highlight()
  controller.ui.set_window_options(win, {
    cursorline = false,
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey,Cursor:CoduxDashboardCursor,CursorIM:CoduxDashboardCursor",
  })
  controller.state.mission_dashboard.win = win
  controller:refresh_dashboard_token_usage(true)
  -- Lines were built before items/selection existed, so usage may have used the
  -- default provider. Re-render now that selection is set (Grok-only crews must
  -- not keep a stale Codex usage line until the monitor timer fires).
  controller:render_dashboard({ skip_token_refresh = true })
  controller.state.mission_dashboard.resize_augroup = vim.api.nvim_create_augroup(
    "codux-mission-dashboard-" .. tostring(bufnr),
    { clear = true }
  )
  vim.api.nvim_create_autocmd("VimResized", {
    group = controller.state.mission_dashboard.resize_augroup,
    callback = function()
      if
        controller.is_valid_win(controller.state.mission_dashboard.win)
        and controller.is_loaded_buf(controller.state.mission_dashboard.buf)
      then
        controller:render_dashboard()
      end
    end,
  })

  controller:bind_dashboard_commands(bufnr)
  controller:open_command_bar()
  controller:open_output_panel(controller:selected_output_entry())
  controller:refresh_dashboard_highlight(lines, items)
  controller:open_command_sink()
  controller:start_monitor_timer()
  vim.schedule(function()
    if
      controller.is_valid_win(controller.state.mission_dashboard.win)
      and controller.is_loaded_buf(controller.state.mission_dashboard.buf)
    then
      controller:open_search_input({ focus = false })
    end
  end)
  return true
end

return M
