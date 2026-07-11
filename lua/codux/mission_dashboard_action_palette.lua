local action_palette_mod = require("codux.action_palette")
local ui = require("codux.ui")

local M = {}

function M.new(controller)
  return action_palette_mod.new({
    state = controller.state,
    ui = controller.ui,
    is_valid_win = controller.is_valid_win,
    is_loaded_buf = controller.is_loaded_buf,
    get_window_cursor = controller.get_window_cursor,
    set_window_cursor = controller.set_window_cursor,
    set_buffer_keymap = controller.set_buffer_keymap,
    bind_close_keys = controller.bind_close_keys,
    notify = controller.notify,
    namespace = controller.namespace,
    win_key = "mission_dashboard_action_win",
    buf_key = "mission_dashboard_action_buf",
    sink_win_key = "mission_dashboard_action_sink_win",
    sink_buf_key = "mission_dashboard_action_sink_buf",
    items_key = "mission_dashboard_action_items",
    key_only = true,
    create_buffer_options = {
      bufhidden = "wipe",
      filetype = "codux-missions-actions",
      buftype = "nofile",
      swapfile = false,
      modifiable = false,
    },
    items = function(target, kind)
      if kind == "workspace" then
        return controller.workspace_ui.role_workspace_action_items(target)
      end
      return controller.workspace_ui.mission_action_items(target)
    end,
    line_for = function(item, width, target, kind)
      if kind == "workspace" then
        return controller.workspace_ui.role_workspace_action_line(item, width)
      end
      return controller.workspace_ui.mission_action_line(item, width)
    end,
    width = function()
      return controller:action_palette_width()
    end,
    window_config = function(target, item_count, kind)
      return controller:action_palette_config(target, item_count, kind)
    end,
    target = function()
      return controller:action_palette_target()
    end,
    assign_open_state = function(palette, target, kind, action_items, bufnr)
      palette.state.mission_dashboard.action_buf = bufnr
      palette.state.mission_dashboard.action_items = action_items
      palette.state.mission_dashboard.action_mission = kind == "workspace" and nil or target
      palette.state.mission_dashboard.action_workspace = kind == "workspace" and target or nil
      palette.state.mission_dashboard.action_kind = kind
    end,
    clear_state = function(palette)
      palette.state.mission_dashboard.action_win = nil
      palette.state.mission_dashboard.action_buf = nil
      palette.state.mission_dashboard.action_sink_win = nil
      palette.state.mission_dashboard.action_sink_buf = nil
      palette.state.mission_dashboard.action_items = {}
      palette.state.mission_dashboard.action_mission = nil
      palette.state.mission_dashboard.action_workspace = nil
      palette.state.mission_dashboard.action_kind = nil
    end,
    action_label = function(_, kind)
      return kind == "workspace" and "Workspace" or "Mission"
    end,
    create_error = function(_, kind)
      local label = kind == "workspace" and "workspace" or "mission"
      return "Failed to create Codux " .. label .. " actions"
    end,
    open_error = function(_, kind)
      local label = kind == "workspace" and "workspace" or "mission"
      return "Failed to open Codux " .. label .. " actions"
    end,
    after_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })
    end,
    run_action = function(action, target)
      return controller:run_action(action, target)
    end,
  })
end

return M
