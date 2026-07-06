local dashboard_viewport = require("codux.mission_dashboard_viewport")
local mission_mod = require("codux.mission")
local ui = require("codux.ui")

local M = {}

local function noop() end

local function opt_function(opts, key, fallback)
  return type(opts[key]) == "function" and opts[key] or fallback
end

function M.normalize(opts)
  opts = type(opts) == "table" and opts or {}

  return {
    state = type(opts.state) == "table" and opts.state or {},
    mission = type(opts.mission) == "table" and opts.mission or mission_mod,
    ui = type(opts.ui) == "table" and opts.ui or ui,
    workspace_ui = type(opts.workspace_ui) == "table" and opts.workspace_ui or require("codux.workspace_ui"),
    is_valid_win = opt_function(opts, "is_valid_win", ui.is_valid_win),
    is_loaded_buf = opt_function(opts, "is_loaded_buf", ui.is_loaded_buf),
    window_buffer = opt_function(opts, "window_buffer", function()
      return nil
    end),
    buffer_filetype = opt_function(opts, "buffer_filetype", function()
      return nil
    end),
    get_window_config = opt_function(opts, "get_window_config", function(win)
      local ok, config = pcall(vim.api.nvim_win_get_config, win)
      return ok and type(config) == "table" and config or {}
    end),
    set_window_config = opt_function(opts, "set_window_config", function(win, config)
      return pcall(vim.api.nvim_win_set_config, win, config)
    end),
    get_window_height = opt_function(opts, "get_window_height", function(win)
      local ok, height = pcall(vim.api.nvim_win_get_height, win)
      return ok and type(height) == "number" and height or nil
    end),
    get_window_width = opt_function(opts, "get_window_width", function(win)
      local ok, width = pcall(vim.api.nvim_win_get_width, win)
      return ok and type(width) == "number" and width or nil
    end),
    get_current_win = opt_function(opts, "get_current_win", function()
      local ok, win = pcall(vim.api.nvim_get_current_win)
      return ok and type(win) == "number" and win or nil
    end),
    get_window_cursor = opt_function(opts, "get_window_cursor", function(win)
      local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
      return ok and type(cursor) == "table" and cursor or nil
    end),
    set_current_win = opt_function(opts, "set_current_win", function(win)
      return pcall(vim.api.nvim_set_current_win, win)
    end),
    set_window_cursor = opt_function(opts, "set_window_cursor", function(win, cursor)
      return pcall(vim.api.nvim_win_set_cursor, win, cursor)
    end),
    reveal_window_row = opt_function(opts, "reveal_window_row", dashboard_viewport.reveal_window_row),
    notify = opt_function(opts, "notify", noop),
    token_usage_label = opt_function(opts, "token_usage_label", function()
      return ""
    end),
    refresh_token_usage = opt_function(opts, "refresh_token_usage", noop),
    token_usage_refresh_ms = opt_function(opts, "token_usage_refresh_ms", function()
      return 60000
    end),
    token_usage_now_ms = opt_function(opts, "token_usage_now_ms", function()
      local loop = vim.uv or vim.loop
      if loop and type(loop.now) == "function" then
        return loop.now()
      end
      return os.time() * 1000
    end),
    create_mission = opt_function(opts, "create_mission", noop),
    create_workspace_prompt = opt_function(opts, "create_workspace_prompt", noop),
    workspace_entries_for_project = opt_function(opts, "workspace_entries_for_project", function()
      return {}
    end),
    missions_for_project = opt_function(opts, "missions_for_project", nil),
    edit_saved_workspace_instruction = opt_function(opts, "edit_saved_workspace_instruction", noop),
    delete_saved_workspace = opt_function(opts, "delete_saved_workspace", noop),
    close_saved_workspace_window = opt_function(opts, "close_saved_workspace_window", noop),
    workspace_interactive_preview = opt_function(opts, "workspace_interactive_preview", function()
      return nil, "workspace preview unavailable"
    end),
    close_workspace_interactive_preview = opt_function(opts, "close_workspace_interactive_preview", noop),
    send_prompt_to_workspace = opt_function(opts, "send_prompt_to_workspace", function()
      return false, "workspace prompt unavailable"
    end),
    select_workspace_question_option = opt_function(opts, "select_workspace_question_option", function()
      return false, "workspace answer unavailable"
    end),
    submit_workspace_question_note = opt_function(opts, "submit_workspace_question_note", function()
      return false, "workspace note unavailable"
    end),
    interrupt_workspace = opt_function(opts, "interrupt_workspace", function()
      return false, "workspace interrupt unavailable"
    end),
    switch_workspace_mode = opt_function(opts, "switch_workspace_mode", function()
      return false, "workspace mode switch unavailable"
    end),
    update_mission_objective = opt_function(opts, "update_mission_objective", noop),
    mission_dirty_roles = opt_function(opts, "mission_dirty_roles", function()
      return {}
    end),
    workspace_branch_state = opt_function(opts, "workspace_branch_state", function(entry)
      entry = type(entry) == "table" and entry or {}
      return {
        worktree = entry.workspace_kind == "worktree",
        branch = entry.worktree_branch,
        base = entry.worktree_base,
        ahead_count = 0,
        merged = false,
      }
    end),
    start_mission = opt_function(opts, "start_mission", noop),
    close_mission = opt_function(opts, "close_mission", noop),
    delete_mission = opt_function(opts, "delete_mission", noop),
    project_root = opt_function(opts, "project_root", function()
      return vim.loop.cwd()
    end),
    set_buffer_keymap = opt_function(opts, "set_buffer_keymap", ui.set_keymap),
    bind_close_keys = opt_function(opts, "bind_close_keys", ui.bind_close_keys),
    termopen = opt_function(opts, "termopen", function(command, term_opts)
      return vim.fn.termopen(command, term_opts)
    end),
    jobstop = opt_function(opts, "jobstop", function(job_id)
      return vim.fn.jobstop(job_id)
    end),
    namespace = opts.namespace
      or (vim.api and vim.api.nvim_create_namespace and vim.api.nvim_create_namespace("codux.mission_control"))
      or 0,
  }
end

return M
