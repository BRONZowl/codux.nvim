local dashboard_search_mod = require("codux.dashboard_search")
local ui = require("codux.ui")

local M = {}

function M.new(controller)
  return dashboard_search_mod.new({
    state = controller.state,
    ui = controller.ui,
    is_valid_win = controller.is_valid_win,
    is_loaded_buf = controller.is_loaded_buf,
    set_current_win = controller.set_current_win,
    get_current_win = controller.get_current_win,
    set_window_cursor = controller.set_window_cursor,
    set_window_config = controller.set_window_config,
    set_buffer_keymap = controller.set_buffer_keymap,
    bind_close_keys = controller.bind_close_keys,
    notify = controller.notify,
    main_win = function()
      return controller.state.mission_dashboard_win
    end,
    cursor_width = function()
      return controller:window_width()
    end,
    window_config = function()
      return controller:dashboard_search_config()
    end,
    render_owner = function()
      return controller:render_dashboard()
    end,
    focus_list = function()
      return controller:focus_mission_list()
    end,
    close_owner = function()
      return controller:close_dashboard()
    end,
    after_create_buffer = function(bufnr)
      ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })
    end,
    create_buffer_options = {
      bufhidden = "wipe",
      filetype = "codux-missions-search",
      buftype = "nofile",
      swapfile = false,
      modifiable = false,
    },
    win_key = "mission_dashboard_search_win",
    buf_key = "mission_dashboard_search_buf",
    query_key = "mission_dashboard_query",
    selected_key = "mission_dashboard_selected_row",
    best_match_key = "mission_dashboard_best_match_row",
    focus_match_key = "mission_dashboard_focus_match",
    confirmed_key = "mission_dashboard_search_confirmed",
    create_error = "Failed to create Codux mission search",
    open_error = "Failed to open Codux mission search",
    close_desc = "Close Codux Missions",
    focus_list_desc = "Focus Codux Mission List",
    select_desc = "Select Codux Mission",
    select_error = "No Codux mission selected",
    delete_desc = "Delete Codux Mission Search Character",
    clear_desc = "Clear Codux Mission Search",
    search_desc = "Search Codux Missions",
    augroup_prefix = "codux-mission-search-",
  })
end

return M
