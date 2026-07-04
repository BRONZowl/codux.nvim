local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local mission_control_mod = require("codux.mission_control")
local workspace_ui = require("codux.workspace_ui")

do
  local controller = mission_control_mod.new({
    workspace_entries_for_project = function()
      return {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_id = "mission:alpha",
          mission_name = "Alpha",
          mission_role = "Builder",
          mission_objective = "Build the dashboard\nKeep it sharp",
          status = "active",
          codex_mode = "execute",
          permission_profile = "auto",
          target_path = "/repo/lua/codux/init.lua",
          workspace_kind = "worktree",
          worktree_branch = "dev/alpha-builder",
          worktree_base = "main",
          worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          window_id = "@1",
          created_at = "2026-07-03T12:00:00Z",
          last_activity_at = "2026-07-03T12:29:00Z",
        },
        {
          name = "alpha-reviewer",
          safe_name = "alpha-reviewer",
          mission_id = "mission:alpha",
          mission_name = "Alpha",
          mission_role = "Reviewer",
          mission_objective = "Build the dashboard\nKeep it sharp",
          status = "question",
          workspace_kind = "worktree",
          worktree_branch = "dev/alpha-reviewer",
          worktree_base = "main",
          worktree_base_commit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          created_at = "2026-07-03T11:30:00Z",
          last_activity_at = "2026-07-03T11:00:00Z",
        },
      }, nil
    end,
    mission_dirty_roles = function(name, root)
      assert_equal(name, "Alpha")
      assert_equal(root, "/repo")
      return {
        { name = "alpha-builder", reason = "dirty" },
      }
    end,
    workspace_branch_state = function(entry)
      return {
        worktree = entry.workspace_kind == "worktree",
        branch = entry.worktree_branch,
        base = entry.worktree_base,
        ahead_count = entry.safe_name == "alpha-reviewer" and 1 or 0,
        merged = entry.safe_name == "alpha-reviewer",
      }
    end,
  })
  local now = workspace_ui.parse_timestamp("2026-07-03T12:30:00Z")
  local lines, items = controller:dashboard_lines("/repo", { now = now, dashboard_width = 180 })
  assert_contains(lines[1], "1 mission | 2 roles | active 1 | question 1 | idle 0")
  assert_true(lines[1]:find("^%s+1 mission") ~= nil)
  assert_contains(table.concat(lines, "\n"), "2 roles")
  assert_contains(table.concat(lines, "\n"), "Alpha")
  assert_equal(lines[4]:find("attn", 1, true), nil)
  assert_equal(lines[4]:find("wt", 1, true), nil)
  assert_equal(lines[4]:find(" br ", 1, true), nil)
  assert_equal(lines[4]:find("merged", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("Mission Control", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("Output  Builder", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("builder output", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("Build the dashboard", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("objective", 1, true), nil)
  assert_contains(table.concat(lines, "\n"), "role            status")
  assert_contains(table.concat(lines, "\n"), "permission profile")
  assert_contains(table.concat(lines, "\n"), "last activity")
  assert_contains(table.concat(lines, "\n"), "needs review")
  assert_contains(table.concat(lines, "\n"), "worktree status")
  assert_contains(table.concat(lines, "\n"), "window status")
  assert_contains(table.concat(lines, "\n"), "cleanup status")
  assert_contains(table.concat(lines, "\n"), "target")
  assert_contains(table.concat(lines, "\n"), "Autopilot")
  assert_contains(table.concat(lines, "\n"), "execute")
  assert_contains(table.concat(lines, "\n"), "1m")
  assert_contains(table.concat(lines, "\n"), "yes")
  assert_contains(table.concat(lines, "\n"), "dirty")
  assert_contains(table.concat(lines, "\n"), "open")
  assert_contains(table.concat(lines, "\n"), "dev/alpha-builder")
  assert_contains(table.concat(lines, "\n"), "not ready")
  assert_contains(table.concat(lines, "\n"), "missing")
  assert_contains(table.concat(lines, "\n"), "merged")
  assert_contains(table.concat(lines, "\n"), "init.lua")
  assert_equal(table.concat(lines, "\n"):find("Commands", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("Tab search", 1, true), nil)
  assert_equal(items[3].kind, "mission")
  assert_equal(items[5].kind, "role")
  assert_equal(items[5].entry.safe_name, "alpha-builder")

  local filtered_lines, filtered_items, filtered_rows, best_match_row =
    controller:dashboard_lines("/repo", { query = "rev", now = now, dashboard_width = 180 })
  assert_contains(table.concat(filtered_lines, "\n"), "Alpha")
  assert_equal(filtered_items[6].kind, "role")
  assert_equal(filtered_items[6].entry.safe_name, "alpha-reviewer")
  assert_equal(best_match_row, 6)
  assert_equal(table.concat(filtered_rows, ","), "3,5,6")

  local mission_lines, mission_items, _, mission_best_row =
    controller:dashboard_lines("/repo", { query = "alp", now = now, dashboard_width = 180 })
  assert_contains(table.concat(mission_lines, "\n"), "Alpha")
  assert_equal(mission_items[3].kind, "mission")
  assert_equal(mission_best_row, 3)

  local reviewer_lines = controller:dashboard_lines("/repo", {
    now = now,
    dashboard_width = 180,
    selected_item = {
      kind = "role",
      entry = {
        safe_name = "alpha-reviewer",
        mission_role = "Reviewer",
        status = "question",
      },
    },
  })
  assert_equal(table.concat(reviewer_lines, "\n"):find("Output  Reviewer", 1, true), nil)
  assert_equal(table.concat(reviewer_lines, "\n"):find("reviewer output", 1, true), nil)
  assert_equal(table.concat(reviewer_lines, "\n"):find("Commands", 1, true), nil)

  local no_match_lines, no_match_items, no_match_rows = controller:dashboard_lines("/repo", { query = "zzz" })
  assert_contains(table.concat(no_match_lines, "\n"), "No matching Codux missions")
  assert_equal(#no_match_items, 0)
  assert_equal(#no_match_rows, 0)
end

do
  local controller = mission_control_mod.new({})
  local command_lines = controller:dashboard_command_lines(120)
  local command_text = table.concat(command_lines, "\n")
  assert_equal(#command_lines, 1)
  assert_equal(command_lines[1]:find("Tab search", 1, true), 11)
  assert_contains(command_text, "Tab search")
  assert_contains(command_text, "j/k move")
  assert_contains(command_text, "m menu")
  assert_contains(command_text, "p prompt")
  assert_contains(command_text, "O preview")
  assert_contains(command_text, "e edit")
  assert_contains(command_text, "x close")
  assert_contains(command_text, "d delete")
  assert_contains(command_text, "n mission")
  assert_contains(command_text, "w workspace")
  assert_contains(command_text, "q close")
end

do
  local old_api = vim.api
  local highlights = {}
  vim.api = {
    nvim_buf_clear_namespace = function() end,
    nvim_buf_add_highlight = function(bufnr, namespace, group, row, start_col, end_col)
      table.insert(highlights, {
        bufnr = bufnr,
        namespace = namespace,
        group = group,
        row = row,
        start_col = start_col,
        end_col = end_col,
      })
    end,
  }

  local controller = mission_control_mod.new({ namespace = 99 })
  local command_lines = controller:dashboard_command_lines(120)
  controller:highlight_command_bar(12, command_lines)

  local function assert_highlight(group, start_col, end_col)
    for _, highlight in ipairs(highlights) do
      if highlight.group == group and highlight.start_col == start_col and highlight.end_col == end_col then
        return true
      end
    end
    error("missing highlight " .. group .. " " .. tostring(start_col) .. "-" .. tostring(end_col), 2)
  end

  local line = command_lines[1]
  local commands = {
    { key = "Tab", label = "search" },
    { key = "j/k", label = "move" },
    { key = "m", label = "menu" },
    { key = "p", label = "prompt" },
    { key = "O", label = "preview" },
    { key = "e", label = "edit" },
    { key = "x", label = "close" },
    { key = "d", label = "delete" },
    { key = "n", label = "mission" },
    { key = "w", label = "workspace" },
    { key = "q", label = "close" },
  }
  local search_start = 1
  for _, command in ipairs(commands) do
    local pair = command.key .. " " .. command.label
    local pair_start = line:find(pair, search_start, true)
    assert_true(type(pair_start) == "number")
    local key_start = pair_start - 1
    local label_start = pair_start + #command.key
    assert_highlight("WhichKey", key_start, key_start + #command.key)
    assert_highlight("Comment", label_start, label_start + #command.label)
    search_start = pair_start + #pair
  end

  vim.api = old_api
end

do
  local dirty_calls = 0
  local branch_calls = 0
  local controller = mission_control_mod.new({
    workspace_entries_for_project = function()
      return {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_id = "mission:alpha",
          mission_name = "Alpha",
          mission_role = "Builder",
          status = "active",
          workspace_kind = "worktree",
          worktree_branch = "dev/alpha-builder",
          worktree_base = "main",
          worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        },
      }, nil
    end,
    mission_dirty_roles = function()
      dirty_calls = dirty_calls + 1
      return {}
    end,
    workspace_branch_state = function()
      branch_calls = branch_calls + 1
      return { worktree = true, merged = false, ahead_count = 0 }
    end,
  })

  controller:dashboard_lines("/repo", { now = 100, dashboard_width = 104 })
  controller:dashboard_lines("/repo", { now = 110, dashboard_width = 104 })
  assert_equal(dirty_calls, 1)
  assert_equal(branch_calls, 1)
  controller:dashboard_lines("/repo", { now = 116, dashboard_width = 104 })
  assert_equal(dirty_calls, 2)
  assert_equal(branch_calls, 2)
end

do
  local current_win = 20
  local cursors = {}
  local render_count = 0
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_search_win = 20,
      mission_dashboard_items = {
        [4] = { kind = "mission", mission = { name = "Alpha" } },
        [7] = { kind = "role", mission = { name = "Alpha" }, entry = { name = "alpha-builder" } },
        [8] = { kind = "role", mission = { name = "Alpha" }, entry = { name = "alpha-reviewer" } },
      },
      mission_dashboard_selectable_rows = { 4, 7, 8 },
      mission_dashboard_best_match_row = 7,
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 7,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20
    end,
    get_current_win = function()
      return current_win
    end,
    set_current_win = function(win)
      current_win = win
      return true
    end,
    set_window_cursor = function(win, cursor)
      cursors[win] = cursor
      return true
    end,
  })
  function controller:render_dashboard()
    render_count = render_count + 1
    return true
  end

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 10)
  assert_equal(cursors[10][1], 7)

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 20)

  assert_true(controller:move_mission_selection(1))
  assert_equal(controller.state.mission_dashboard_selected_row, 8)
  assert_equal(cursors[10][1], 8)
  assert_equal(controller:selected_item().entry.name, "alpha-reviewer")

  assert_true(controller:move_mission_selection(1))
  assert_equal(controller.state.mission_dashboard_selected_row, 8)

  assert_true(controller:move_mission_selection(-1))
  assert_equal(controller.state.mission_dashboard_selected_row, 7)
  assert_equal(controller:selected_item().entry.name, "alpha-builder")
  assert_equal(controller:selected_mission().name, "Alpha")
  assert_equal(render_count, 3)
end

do
  local current_win = nil
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_search_win = 20,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20
    end,
    set_current_win = function(win)
      current_win = win
      return true
    end,
  })

  assert_true(controller:open_search_input({ focus = false }))
  assert_nil(current_win)
  assert_true(controller:open_search_input())
  assert_equal(current_win, 20)
end

do
  local opened_kind
  local opened_target
  local notifications = {}
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_items = {
        [4] = { kind = "mission", mission = { name = "Alpha" } },
        [5] = { kind = "mission", mission = { name = "Alpha" } },
        [7] = { kind = "role", mission = { name = "Alpha" }, entry = { name = "alpha-builder" } },
      },
      mission_dashboard_selectable_rows = { 4, 7 },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 4,
    },
    notify = function(message)
      table.insert(notifications, message)
    end,
  })
  function controller:open_action_palette_for(target, kind)
    opened_target = target
    opened_kind = kind
    return true
  end

  assert_true(controller:open_action_palette())
  assert_equal(opened_kind, "mission")
  assert_equal(opened_target.name, "Alpha")

  controller.state.mission_dashboard_selected_row = 7
  assert_true(controller:open_action_palette())
  assert_equal(opened_kind, "workspace")
  assert_equal(opened_target.name, "alpha-builder")

  controller.state.mission_dashboard_selected_row = 5
  assert_false(controller:open_action_palette())
  assert_equal(notifications[#notifications], "No Codux mission or workspace selected")
end

do
  local old_api = vim.api
  local highlights = {}
  vim.api = {
    nvim_buf_clear_namespace = function() end,
    nvim_buf_add_highlight = function(bufnr, namespace, group, row, start_col, end_col)
      table.insert(highlights, {
        bufnr = bufnr,
        namespace = namespace,
        group = group,
        row = row,
        start_col = start_col,
        end_col = end_col,
      })
    end,
  }

  local rendered_lines
  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard_action_buf = 12,
      mission_dashboard_action_items = {
        { key = "v", action = "view_objective", label = "View Objective" },
      },
    },
    is_loaded_buf = function(bufnr)
      return bufnr == 12
    end,
    get_window_width = function()
      return 80
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
  })

  assert_true(controller:render_action_palette())
  assert_equal(rendered_lines[1], "v  View Objective")
  assert_equal(highlights[1].group, "WhichKey")
  assert_equal(highlights[1].start_col, 0)
  assert_equal(highlights[1].end_col, 1)
  assert_equal(highlights[2].group, "Normal")
  assert_equal(highlights[2].start_col, 1)
  assert_equal(highlights[2].end_col, 3)
  assert_equal(highlights[3].group, "Normal")
  assert_equal(highlights[3].start_col, 3)
  assert_equal(highlights[3].end_col, -1)
  vim.api = old_api
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_create_augroup = vim.api.nvim_create_augroup
  local old_create_autocmd = vim.api.nvim_create_autocmd
  local enter_rhs
  local focused_win
  vim.api.nvim_open_win = function()
    return 20
  end
  vim.api.nvim_create_augroup = function()
    return 91
  end
  vim.api.nvim_create_autocmd = function() end

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_command_win = 30,
      mission_dashboard_best_match_row = 7,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20 or win == 30
    end,
    is_loaded_buf = function()
      return true
    end,
    get_window_config = function()
      return { col = 0, row = 0 }
    end,
    get_window_width = function()
      return 80
    end,
    ui = {
      create_scratch_buffer = function()
        return 31
      end,
      printable_prompt_keys = function()
        return {}
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, _, lhs, rhs)
      if lhs == "<CR>" then
        enter_rhs = rhs
      end
    end,
    set_current_win = function(win)
      focused_win = win
      return true
    end,
  })
  function controller:render_dashboard()
    return true
  end

  assert_true(controller:open_search_input())
  assert_true(enter_rhs())
  assert_equal(controller.state.mission_dashboard_selected_row, 7)
  assert_equal(focused_win, 10)

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_create_augroup = vim.api.nvim_create_augroup
  local old_create_autocmd = vim.api.nvim_create_autocmd
  local search_config
  vim.api.nvim_open_win = function(_, _, config)
    search_config = config
    return 20
  end
  vim.api.nvim_create_augroup = function()
    return 91
  end
  vim.api.nvim_create_autocmd = function() end

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard_win = 10,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20
    end,
    is_loaded_buf = function()
      return true
    end,
    get_window_config = function()
      return { col = 5, row = 10, width = 88, height = 8 }
    end,
    get_window_width = function()
      return 88
    end,
    ui = {
      create_scratch_buffer = function()
        return 31
      end,
      printable_prompt_keys = function()
        return {}
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function() end,
  })

  assert_true(controller:open_search_input())
  assert_equal(search_config.title, " Codux mission: ")
  assert_equal(search_config.width, 88)
  assert_equal(search_config.height, 1)
  assert_equal(search_config.col, 5)
  assert_equal(search_config.row, 7)

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local window_config
  vim.api.nvim_open_win = function(_, _, config)
    window_config = config
    return 40
  end

  local controller = mission_control_mod.new({
    state = {},
    is_loaded_buf = function()
      return true
    end,
    ui = {
      create_scratch_buffer = function()
        return 31
      end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function() end,
  })

  assert_true(controller:open_command_sink())
  assert_equal(window_config.focusable, false)
  vim.api.nvim_open_win = old_open_win
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_create_augroup = vim.api.nvim_create_augroup
  local old_create_autocmd = vim.api.nvim_create_autocmd
  local window_config
  local rendered_lines
  vim.api.nvim_open_win = function(_, _, config)
    window_config = config
    return 42
  end
  vim.api.nvim_create_augroup = function()
    return 93
  end
  vim.api.nvim_create_autocmd = function() end

  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
    },
    is_loaded_buf = function(bufnr)
      return bufnr == 32
    end,
    is_valid_win = function(win)
      return win == 10 or win == 42
    end,
    get_window_config = function()
      return { col = 2, row = 3 }
    end,
    get_window_height = function()
      return 8
    end,
    get_window_width = function()
      return 100
    end,
    ui = {
      create_scratch_buffer = function()
        return 32
      end,
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
  })

  assert_true(controller:open_command_bar())
  assert_equal(window_config.title, " Commands ")
  assert_equal(window_config.focusable, false)
  assert_equal(controller.state.mission_dashboard_command_bar_buf, 32)
  assert_equal(controller.state.mission_dashboard_command_bar_win, 42)
  local command_text = table.concat(rendered_lines, "\n")
  assert_contains(command_text, "Tab search")
  assert_contains(command_text, "O preview")
  assert_contains(command_text, "q close")

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_win_set_cursor = vim.api.nvim_win_set_cursor
  local window_options
  vim.api.nvim_open_win = function()
    return 41
  end
  vim.api.nvim_win_set_cursor = function()
    return true
  end

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard_win = 10,
    },
    is_valid_win = function(win)
      return win == 10
    end,
    is_loaded_buf = function()
      return true
    end,
    get_window_config = function()
      return { col = 0, row = 0 }
    end,
    get_window_width = function()
      return 80
    end,
    get_window_height = function()
      return 10
    end,
    ui = {
      create_scratch_buffer = function()
        return 31
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function(_, opts)
        window_options = opts
      end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function() end,
  })

  assert_true(controller:open_action_palette_for({ name = "Alpha" }, "mission"))
  assert_equal(window_options.winhighlight, "FloatBorder:WhichKey,FloatTitle:WhichKey")
  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_win_set_cursor = old_win_set_cursor
end

do
  local bound = {}
  local controller = mission_control_mod.new({
    state = {},
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, mode, lhs, _rhs, desc)
      if mode == "n" then
        bound[lhs] = desc
      end
    end,
  })

  controller:bind_dashboard_commands(12)

  assert_equal(bound.m, "Open Codux Mission Menu")
  assert_equal(bound.j, "Next Codux Mission")
  assert_equal(bound.k, "Previous Codux Mission")
  assert_nil(bound["<CR>"])
  assert_equal(bound["<Tab>"], "Search/List Codux Missions")
  assert_equal(bound.p, "Prompt Codux Mission Role")
  assert_equal(bound.O, "Focus Codux Mission Output")
  assert_equal(bound.n, "Create Codux Mission")
  assert_equal(bound.w, "Create Codux Workspace")
  assert_equal(bound.e, "Edit Codux Mission Objective")
  assert_equal(bound.x, "Close Codux Mission")
  assert_equal(bound.d, "Delete Codux Mission")
  assert_nil(bound.r)
end

do
  local closed = false
  local opened = false
  local controller = mission_control_mod.new({
    create_workspace_prompt = function()
      opened = true
      return true
    end,
  })
  function controller:close_dashboard()
    closed = true
  end

  assert_true(controller:create_new_workspace())
  assert_true(closed)
  assert_true(opened)
end

do
  local current_cursor = { 1, 0 }
  local cursor_set
  local ran_action
  local closed = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_action_win = 30,
      mission_dashboard_action_buf = 31,
      mission_dashboard_action_items = workspace_ui.mission_action_items(),
      mission_dashboard_action_mission = { name = "Alpha" },
    },
    is_valid_win = function(win)
      return win == 30
    end,
    get_window_cursor = function()
      return current_cursor
    end,
    set_window_cursor = function(_, cursor)
      cursor_set = cursor
      current_cursor = cursor
      return true
    end,
    ui = {
      close_window = function()
        closed = true
      end,
      delete_buffer = function() end,
    },
  })
  function controller:edit_selected_mission(mission)
    ran_action = "edit:" .. tostring(mission.name)
    return true
  end
  function controller:view_mission_objective(mission)
    ran_action = "view:" .. tostring(mission.name)
    return true
  end
  function controller:start_selected_mission(mission)
    ran_action = "start:" .. tostring(mission.name)
    return true
  end

  assert_true(controller:move_action_cursor(1))
  assert_equal(cursor_set[1], 2)
  assert_true(controller:move_action_cursor(-1))
  assert_equal(cursor_set[1], 1)

  assert_true(controller:run_highlighted_action())
  assert_equal(ran_action, "start:Alpha")
  assert_true(closed)
  assert_nil(controller.state.mission_dashboard_action_win)
end

do
  local current_cursor = { 1, 0 }
  local ran_action
  local entry = { name = "alpha-builder", safe_name = "alpha-builder" }
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_action_win = 30,
      mission_dashboard_action_buf = 31,
      mission_dashboard_action_items = workspace_ui.role_workspace_action_items(entry),
      mission_dashboard_action_workspace = entry,
      mission_dashboard_action_kind = "workspace",
    },
    is_valid_win = function(win)
      return win == 30
    end,
    get_window_cursor = function()
      return current_cursor
    end,
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
    },
    open_saved_workspace = function(name)
      ran_action = "open:" .. tostring(name)
      return true
    end,
  })
  function controller:close_dashboard() end

  assert_true(controller:run_highlighted_action())
  assert_equal(ran_action, "open:alpha-builder")
end

do
  local calls = {}
  local entry = { name = "alpha-builder", safe_name = "alpha-builder" }
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function(message, choices, default)
    table.insert(calls, "confirm:" .. tostring(message) .. ":" .. tostring(choices) .. ":" .. tostring(default))
    assert_equal(choices, "&Delete\n&Cancel")
    assert_equal(default, 2)
    return 1
  end
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_action_workspace = entry,
    },
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
    },
    edit_saved_workspace_instruction = function(workspace)
      table.insert(calls, "edit:" .. tostring(workspace.name))
      return true
    end,
    close_saved_workspace_window = function(workspace)
      table.insert(calls, "close:" .. tostring(workspace.name))
      return true
    end,
    delete_saved_workspace = function(workspace)
      table.insert(calls, "delete:" .. tostring(workspace.name))
      return true
    end,
    open_saved_workspace = function(name)
      table.insert(calls, "open:" .. tostring(name))
      return true
    end,
  })
  function controller:close_dashboard() end

  assert_true(controller:run_action("open_workspace", entry))
  assert_true(controller:run_action("edit_instructions", entry))
  assert_true(controller:run_action("close_workspace", entry))
  assert_true(controller:run_action("delete_workspace", entry))
  assert_equal(calls[1], "open:alpha-builder")
  assert_equal(calls[2], "edit:alpha-builder")
  assert_equal(calls[3], "close:alpha-builder")
  assert_contains(calls[4], "confirm:Delete Codux workspace alpha-builder?")
  assert_equal(calls[5], "delete:alpha-builder")
  vim.fn.confirm = old_confirm
end

do
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    workspace_kind = "worktree",
    worktree_path = "/codux-worktrees/alpha-builder",
    worktree_branch = "dev/alpha-builder",
  }
  local message = workspace_ui.delete_workspace_message(entry)
  assert_contains(message, "Delete Codux workspace alpha-builder?")
  assert_contains(message, "Force delete will remove the Git worktree and delete its branch.")
  assert_contains(message, "Uncommitted and untracked work")
  assert_contains(message, "Worktree: /codux-worktrees/alpha-builder")
  assert_contains(message, "Branch: dev/alpha-builder")
  assert_true(workspace_ui.confirm_delete_workspace(entry, function(confirm_message, choices, default)
    assert_equal(confirm_message, message)
    assert_equal(choices, "&Delete\n&Cancel")
    assert_equal(default, 2)
    return 1
  end))
  assert_false(workspace_ui.confirm_delete_workspace(entry, function()
    return 2
  end))
end

do
  local captured = {}
  local events = {}
  local rendered = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_project_root = "/repo",
    },
    start_mission = function(name, root, opts)
      table.insert(events, "start")
      captured = { name = name, root = root, opts = opts }
      return true
    end,
  })
  function controller:close_dashboard()
    table.insert(events, "close")
  end
  function controller:render_dashboard()
    rendered = true
  end

  assert_true(controller:start_selected_mission({ name = "Alpha" }))
  assert_equal(captured.name, "Alpha")
  assert_equal(captured.root, "/repo")
  assert_true(captured.opts.restart_inactive)
  assert_true(captured.opts.prompt_roles)
  assert_true(captured.opts.focus_first)
  assert_equal(events[1], "close")
  assert_equal(events[2], "start")
  assert_false(rendered)
end

do
  local events = {}
  local rendered = false
  local reopened_root
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_project_root = "/repo",
    },
    start_mission = function()
      table.insert(events, "start")
      return false
    end,
  })
  function controller:close_dashboard()
    table.insert(events, "close")
  end
  function controller:render_dashboard()
    rendered = true
  end
  function controller:open_dashboard(root)
    reopened_root = root
    return true
  end

  assert_false(controller:start_selected_mission({ name = "Alpha" }))
  assert_equal(events[1], "close")
  assert_equal(events[2], "start")
  assert_false(rendered)
  assert_equal(reopened_root, "/repo")
end

do
  local old_schedule = vim.schedule
  local saved_root
  local reopened_root
  local on_save
  vim.schedule = function(callback)
    return callback()
  end
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_project_root = "/repo",
    },
    update_mission_objective = function(_, _, root)
      saved_root = root
      return true
    end,
  })
  function controller:close_dashboard() end
  function controller:open_objective_editor(_, _, opts)
    on_save = opts.on_save
    return true
  end
  function controller:open_dashboard(root)
    reopened_root = root
    return true
  end

  assert_true(controller:edit_selected_mission({ name = "Alpha", objective = "old" }))
  assert_true(on_save("Alpha", "new"))
  assert_equal(saved_root, "/repo")
  assert_equal(reopened_root, "/repo")
  vim.schedule = old_schedule
end

if type(vim.api) == "table" then
  local captured_mission
  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_control.test"),
    notify = function() end,
    set_buffer_keymap = function(bufnr, modes, lhs, rhs, desc, opts)
      opts = type(opts) == "table" and opts or {}
      return pcall(vim.keymap.set, modes, lhs, rhs, {
        buffer = bufnr,
        silent = opts.silent ~= false,
        desc = desc,
      })
    end,
    bind_close_keys = function() end,
  })
  function controller:open_preview(mission)
    captured_mission = mission
    return true
  end

  local old_columns = vim.o.columns
  local old_lines = vim.o.lines
  local old_cmdheight = vim.o.cmdheight
  vim.o.columns = 42
  vim.o.lines = 12
  vim.o.cmdheight = 1
  local objective_config = controller:objective_editor_config(20)
  local preview_config = controller:preview_config(20)
  local dashboard_config = controller:dashboard_config(20)
  local command_config = controller:dashboard_command_config(3)
  local output_config = controller:dashboard_output_config(2)
  assert_equal(objective_config.title, " Codux Mission Objective ")
  assert_equal(preview_config.title, " Codux Mission Control ")
  assert_equal(dashboard_config.title, " Mission Control ")
  assert_contains(dashboard_config.footer, "Commands shown below")
  assert_equal(dashboard_config.footer:find("Enter open", 1, true), nil)
  assert_equal(dashboard_config.footer:find("Tab search", 1, true), nil)
  assert_equal(dashboard_config.footer:find("m menu", 1, true), nil)
  assert_equal(dashboard_config.footer:find("p prompt", 1, true), nil)
  assert_equal(dashboard_config.footer:find("O preview", 1, true), nil)
  assert_equal(dashboard_config.footer:find("e edit", 1, true), nil)
  assert_equal(dashboard_config.footer:find("x close", 1, true), nil)
  assert_equal(dashboard_config.footer:find("d delete", 1, true), nil)
  assert_equal(dashboard_config.footer:find("n mission", 1, true), nil)
  assert_equal(dashboard_config.footer:find("w workspace", 1, true), nil)
  assert_equal(dashboard_config.footer:find("q close", 1, true), nil)
  assert_equal(dashboard_config.footer:find("output above", 1, true), nil)
  assert_equal(dashboard_config.footer:find("r refresh", 1, true), nil)
  assert_true(objective_config.width <= 38)
  assert_true(preview_config.width <= 38)
  assert_true(dashboard_config.width <= 38)
  assert_true(objective_config.height <= 7)
  assert_true(preview_config.height <= 7)
  assert_true(dashboard_config.height <= 7)
  assert_equal(command_config.title, " Commands ")
  assert_equal(command_config.focusable, false)
  assert_equal(output_config.title, " Output ")
  assert_contains(output_config.footer, "Ctrl-o workspace")
  assert_equal(output_config.footer:find("Ctrl-q", 1, true), nil)
  assert_equal(output_config.footer:find("Tab list", 1, true), nil)
  assert_equal(output_config.footer:find("r refresh", 1, true), nil)
  assert_equal(output_config.footer:find("p prompt", 1, true), nil)
  assert_equal(output_config.footer:find("o open", 1, true), nil)

  local old_is_valid_win = controller.is_valid_win
  local old_get_window_config = controller.get_window_config
  local old_get_window_height = controller.get_window_height
  local old_get_window_width = controller.get_window_width
  vim.o.columns = 120
  vim.o.lines = 24
  vim.o.cmdheight = 1
  local reserved_dashboard_config = controller:dashboard_config(18, {
    reserve_command_bar = true,
    reserve_output_panel = true,
  })
  local reserved_command_config
  controller.state.mission_dashboard_win = 91
  controller.state.mission_dashboard_command_bar_win = 92
  controller.is_valid_win = function(win)
    return win == 91 or win == 92
  end
  controller.get_window_config = function(win)
    if win == 92 then
      return reserved_command_config
    end
    return reserved_dashboard_config
  end
  controller.get_window_height = function(win)
    if win == 92 and reserved_command_config then
      return reserved_command_config.height
    end
    return reserved_dashboard_config.height
  end
  controller.get_window_width = function()
    return reserved_dashboard_config.width
  end
  reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
  local reserved_output_config = controller:dashboard_output_config(2)
  assert_equal(reserved_dashboard_config.height, 15)
  assert_equal(reserved_output_config.height, 1)
  assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
  assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
  assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)

  reserved_dashboard_config = controller:dashboard_config(18, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    selected_item = { kind = "mission", mission = { name = "Alpha" } },
  })
  reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
  reserved_output_config = controller:dashboard_output_config(2, {
    selected_item = { kind = "mission", mission = { name = "Alpha" } },
  })
  assert_equal(reserved_dashboard_config.height, 15)
  assert_equal(reserved_output_config.height, 1)
  assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
  assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
  assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)

  assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = { status = "inactive" } }), "compact")
  assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = {} }), "compact")
  assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = { status = "active" } }), "workspace")
  assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = { status = "idle" } }), "workspace")
  assert_equal(controller:dashboard_preview_mode({ kind = "role", entry = { status = "question" } }), "workspace")

  reserved_dashboard_config = controller:dashboard_config(18, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder" } },
  })
  reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
  reserved_output_config = controller:dashboard_output_config(2, {
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder" } },
  })
  assert_equal(reserved_dashboard_config.height, 15)
  assert_equal(reserved_output_config.height, 1)
  assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
  assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
  assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)

  reserved_dashboard_config = controller:dashboard_config(18, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
  })
  reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
  reserved_output_config = controller:dashboard_output_config(2, {
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
  })
  assert_equal(reserved_dashboard_config.height, 1)
  assert_equal(reserved_output_config.height, 15)
  assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
  assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
  assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)

  for _, status in ipairs({ "idle", "question" }) do
    reserved_dashboard_config = controller:dashboard_config(18, {
      reserve_command_bar = true,
      reserve_output_panel = true,
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = status } },
    })
    reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
    reserved_output_config = controller:dashboard_output_config(2, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = status } },
    })
    assert_equal(reserved_dashboard_config.height, 1)
    assert_equal(reserved_output_config.height, 15)
    assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
    assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
    assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)
  end

  vim.o.columns = 140
  vim.o.lines = 40
  reserved_dashboard_config = controller:dashboard_config(20, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
  })
  reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
  reserved_output_config = controller:dashboard_output_config(2, {
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
  })
  assert_equal(reserved_output_config.height, 31)
  assert_true(reserved_dashboard_config.height >= 1)
  assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
  assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
  assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)

  vim.o.columns = 42
  vim.o.lines = 12
  reserved_dashboard_config = controller:dashboard_config(20, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
  })
  reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
  reserved_output_config = controller:dashboard_output_config(2, {
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
  })
  assert_equal(reserved_output_config.height, 3)
  assert_equal(reserved_command_config.row, reserved_dashboard_config.row + reserved_dashboard_config.height + 2)
  assert_equal(reserved_output_config.row, reserved_command_config.row + reserved_command_config.height + 2)
  assert_true(reserved_output_config.row + reserved_output_config.height + 2 <= vim.o.lines - vim.o.cmdheight)
  controller.is_valid_win = old_is_valid_win
  controller.get_window_config = old_get_window_config
  controller.get_window_height = old_get_window_height
  controller.get_window_width = old_get_window_width

  do
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 4 },
      [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
    }
    local calls = {}
    local resize_controller = mission_control_mod.new({
      state = {
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
      },
      is_valid_win = function(win)
        return win == 91 or win == 92 or win == 93
      end,
      get_window_config = function(win)
        return configs[win] or {}
      end,
      get_window_height = function(win)
        return configs[win] and configs[win].height or nil
      end,
      get_window_width = function(win)
        return configs[win] and configs[win].width or nil
      end,
      set_window_config = function(win, config)
        configs[win] = config
        table.insert(calls, win)
        return true
      end,
    })

    vim.o.columns = 120
    vim.o.lines = 24
    assert_true(resize_controller:resize_dashboard_stack(18, {
      selected_item = { kind = "mission", mission = { name = "Alpha" } },
    }))
    assert_equal(table.concat(calls, ","), "91,92,93")
    assert_equal(configs[91].height, 15)
    assert_equal(configs[92].height, 1)
    assert_equal(configs[93].height, 1)
    assert_equal(configs[92].row, configs[91].row + configs[91].height + 2)
    assert_equal(configs[93].row, configs[92].row + configs[92].height + 2)
    assert_true(configs[93].row + configs[93].height + 2 <= vim.o.lines - vim.o.cmdheight)
    assert_equal(configs[92].width, configs[91].width)
    assert_equal(configs[93].width, configs[91].width)

    calls = {}
    assert_true(resize_controller:resize_dashboard_stack(18, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    }))
    assert_equal(table.concat(calls, ","), "91,92,93")
    assert_equal(configs[91].height, 1)
    assert_equal(configs[92].height, 1)
    assert_equal(configs[93].height, 15)
    assert_equal(configs[92].row, configs[91].row + configs[91].height + 2)
    assert_equal(configs[93].row, configs[92].row + configs[92].height + 2)
    assert_true(configs[93].row + configs[93].height + 2 <= vim.o.lines - vim.o.cmdheight)
    assert_equal(configs[92].width, configs[91].width)
    assert_equal(configs[93].width, configs[91].width)
  end

  do
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 128, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 128, height = 4 },
      [93] = { relative = "editor", row = 0, col = 0, width = 128, height = 6 },
      [94] = { relative = "editor", row = 0, col = 0, width = 128, height = 1 },
    }
    local calls = {}
    local resize_controller = mission_control_mod.new({
      state = {
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
        mission_dashboard_search_win = 94,
      },
      is_valid_win = function(win)
        return win == 91 or win == 92 or win == 93 or win == 94
      end,
      get_window_config = function(win)
        return configs[win] or {}
      end,
      get_window_height = function(win)
        return configs[win] and configs[win].height or nil
      end,
      get_window_width = function(win)
        return configs[win] and configs[win].width or nil
      end,
      set_window_config = function(win, config)
        configs[win] = config
        table.insert(calls, win)
        return true
      end,
    })

    vim.o.columns = 140
    vim.o.lines = 40
    assert_true(resize_controller:resize_dashboard_stack(20, {
      selected_item = { kind = "mission", mission = { name = "Alpha" } },
    }))
    assert_equal(table.concat(calls, ","), "91,94,92,93")
    local compact_dashboard_row = configs[91].row
    local compact_search_row = configs[94].row
    assert_equal(configs[94].row, configs[91].row - 3)
    assert_equal(configs[94].width, configs[91].width)
    assert_equal(configs[92].row, configs[91].row + configs[91].height + 2)
    assert_equal(configs[93].row, configs[92].row + configs[92].height + 2)
    assert_true(configs[93].row + configs[93].height + 2 <= vim.o.lines - vim.o.cmdheight)

    calls = {}
    assert_true(resize_controller:resize_dashboard_stack(20, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    }))
    assert_equal(table.concat(calls, ","), "91,94,92,93")
    assert_true(configs[91].row < compact_dashboard_row)
    assert_true(configs[94].row < compact_search_row)
    assert_equal(configs[94].row, configs[91].row - 3)
    assert_equal(configs[94].width, configs[91].width)
    assert_equal(configs[92].row, configs[91].row + configs[91].height + 2)
    assert_equal(configs[93].row, configs[92].row + configs[92].height + 2)
    assert_true(configs[93].row + configs[93].height + 2 <= vim.o.lines - vim.o.cmdheight)
  end

  do
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 4 },
      [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
    }
    local items = {
      [4] = { kind = "mission", mission = { name = "Alpha" } },
      [7] = { kind = "role", mission = { name = "Alpha" }, entry = { safe_name = "alpha-builder", status = "active" } },
    }
    local controller = mission_control_mod.new({
      state = {
        mission_dashboard_buf = 90,
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
        mission_dashboard_items = items,
        mission_dashboard_selectable_rows = { 4, 7 },
        mission_dashboard_search_confirmed = true,
        mission_dashboard_selected_row = 4,
      },
      is_loaded_buf = function(bufnr)
        return bufnr == 90
      end,
      is_valid_win = function(win)
        return win == 91 or win == 92 or win == 93
      end,
      get_window_config = function(win)
        return configs[win] or {}
      end,
      get_window_height = function(win)
        return configs[win] and configs[win].height or nil
      end,
      get_window_width = function(win)
        return configs[win] and configs[win].width or nil
      end,
      set_window_config = function(win, config)
        configs[win] = config
        return true
      end,
      set_window_cursor = function()
        return true
      end,
      ui = {
        set_lines = function()
          return true
        end,
      },
    })
    function controller:dashboard_lines()
      return { "Mission", "  Builder" }, items, { 4, 7 }, nil
    end
    function controller:highlight_dashboard()
      return true
    end
    function controller:render_command_bar()
      return true
    end
    function controller:render_output_panel()
      return true
    end

    vim.o.columns = 120
    vim.o.lines = 24
    assert_true(controller:render_dashboard())
    local compact_dashboard_height = configs[91].height
    assert_equal(configs[93].height, 1)
    assert_true(controller:move_mission_selection(1))
    assert_equal(controller.state.mission_dashboard_selected_row, 7)
    assert_true(configs[91].height < compact_dashboard_height)
    assert_true(configs[93].height > 1)
  end

  local codux = require("codux")
  codux.setup({ token_monitor = false })
  assert_true(codux._v5.should_select_permission_profile(nil))
  assert_false(codux._v5.should_select_permission_profile(12))
  assert_equal(codux._v5.remote_show_existing_codex_terminal(), "not_running")

  local profile_choices = codux._v5.permission_profile_choices()
  assert_equal(profile_choices[1].profile, "default")
  assert_equal(profile_choices[2].profile, "auto")
  assert_equal(profile_choices[3].profile, "danger")
  assert_equal(profile_choices[3].label, "Full Access")
  assert_true(codux._v5.suppress_startup_plan_warning_for_workspace({
    mission_id = "mission:alpha",
  }))
  assert_false(codux._v5.suppress_startup_plan_warning_for_workspace({
    mission_id = "",
  }))
  assert_false(codux._v5.suppress_startup_plan_warning_for_workspace({
    name = "review",
  }))

  local profile_calls = {}
  local function open_default(prompt)
    table.insert(profile_calls, "default:" .. tostring(prompt))
    return "default"
  end
  local function open_auto(prompt)
    table.insert(profile_calls, "auto:" .. tostring(prompt))
    return "auto"
  end
  local function open_danger(prompt)
    table.insert(profile_calls, "danger:" .. tostring(prompt))
    return "danger"
  end

  assert_equal(codux._v5.select_permission_profile_open({
    initial_prompt = "hello",
    selector = function(items, opts, callback)
      assert_equal(opts.prompt, "Codex permission profile:")
      assert_equal(opts.format_item(items[2]), "Autopilot")
      return callback(items[1])
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "default")
  assert_equal(profile_calls[#profile_calls], "default:hello")

  assert_equal(codux._v5.select_permission_profile_open({
    initial_prompt = "hello",
    selector = function(items, _, callback)
      return callback(items[2])
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "auto")
  assert_equal(profile_calls[#profile_calls], "auto:hello")

  assert_equal(codux._v5.select_permission_profile_open({
    initial_prompt = "hello",
    selector = function(items, _, callback)
      return callback(items[3])
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), "danger")
  assert_equal(profile_calls[#profile_calls], "danger:hello")

  assert_equal(codux._v5.select_permission_profile_open({
    selector = function(_, _, callback)
      return callback(nil)
    end,
    open_default = open_default,
    open_auto = open_auto,
    open_danger = open_danger,
  }), false)
  assert_equal(#profile_calls, 3)

  local mission_map = vim.fn.maparg("<leader>zm", "n", false, true)
  assert_true(vim.tbl_isempty(mission_map))
  local workspace_create_map = vim.fn.maparg("<leader>zw", "n", false, true)
  assert_true(vim.tbl_isempty(workspace_create_map))
  local workspaces_map = vim.fn.maparg("<leader>zW", "n", false, true)
  assert_true(vim.tbl_isempty(workspaces_map))
  local autopilot_map = vim.fn.maparg("<leader>za", "n", false, true)
  assert_true(vim.tbl_isempty(autopilot_map))
  local danger_map = vim.fn.maparg("<leader>zA", "n", false, true)
  assert_true(vim.tbl_isempty(danger_map))
  local missions_map = vim.fn.maparg("<leader>zM", "n", false, true)
  assert_equal(missions_map.desc, "mission control")
  vim.o.columns = 140
  vim.o.lines = 40
  vim.o.cmdheight = 1
  objective_config = controller:objective_editor_config(20)
  preview_config = controller:preview_config(20)
  dashboard_config = controller:dashboard_config(20)
  assert_equal(objective_config.width, 96)
  assert_equal(preview_config.width, 92)
  assert_equal(dashboard_config.width, 128)
  vim.o.columns = old_columns
  vim.o.lines = old_lines
  vim.o.cmdheight = old_cmdheight

  assert_true(controller:open_objective_editor("Save Test"))
  local bufnr = vim.api.nvim_get_current_buf()
  assert_contains(vim.api.nvim_buf_get_name(bufnr), "codux://mission-objective/")
  assert_equal(vim.b[bufnr].codux_disable_completion, true)
  assert_false(vim.bo[bufnr].modified)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "mission objective" })
  assert_true(vim.bo[bufnr].modified)
  vim.cmd("write")
  assert_equal(captured_mission.name, "Save Test")
  assert_equal(captured_mission.objective, "mission objective")

  local attempted_objective
  assert_true(controller:open_objective_editor("Failed Save", "old objective", {
    on_save = function(_, objective)
      attempted_objective = objective
      return false
    end,
  }))
  local failed_bufnr = vim.api.nvim_get_current_buf()
  assert_false(vim.bo[failed_bufnr].modified)
  vim.api.nvim_buf_set_lines(failed_bufnr, 0, -1, false, { "new objective" })
  assert_true(vim.bo[failed_bufnr].modified)
  vim.cmd("write")
  assert_equal(attempted_objective, "new objective")
  assert_equal(vim.api.nvim_get_current_buf(), failed_bufnr)
  assert_true(vim.bo[failed_bufnr].modified)
  pcall(vim.api.nvim_buf_delete, failed_bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local preview_entry
  local term_command
  local modified_at_termopen
  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_output.test"),
    state = {
      mission_dashboard_buf = 10,
      mission_dashboard_win = 11,
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
      mission_dashboard_items = {
        [3] = { kind = "mission", mission = { roles = { { safe_name = "alpha-builder", mission_role = "Builder" } } } },
        [5] = { kind = "role", entry = { safe_name = "alpha-reviewer", mission_role = "Reviewer", status = "idle" } },
      },
      mission_dashboard_selectable_rows = { 3, 5 },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 5,
    },
    is_loaded_buf = function(bufnr)
      return bufnr == 10 or vim.api.nvim_buf_is_loaded(bufnr)
    end,
    is_valid_win = function(win)
      return win == 11 or win == 13
    end,
    get_window_width = function()
      return 80
    end,
    get_window_height = function()
      return 6
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function(entry)
      preview_entry = entry
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function(command)
      term_command = command
      modified_at_termopen = vim.api.nvim_get_option_value("modified", { buf = bufnr })
      return 77
    end,
  })

  assert_equal(controller:selected_output_entry().safe_name, "alpha-reviewer")
  assert_true(controller:render_output_panel())
  assert_equal(preview_entry.safe_name, "alpha-reviewer")
  assert_equal(table.concat(term_command, " "), "env -u TMUX tmux attach-session -t codux-preview-test")
  assert_false(modified_at_termopen)
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  assert_contains(table.concat(rendered_lines, "\n"), "Output: Reviewer")
  assert_contains(table.concat(rendered_lines, "\n"), "Ctrl-o workspace")
  assert_equal(table.concat(rendered_lines, "\n"):find("Ctrl-q", 1, true), nil)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local old_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, { "opening workspace session preview..." })
  local win = vim.api.nvim_open_win(old_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 40,
    height = 3,
    style = "minimal",
  })
  vim.api.nvim_set_option_value("winfixbuf", true, { win = win })

  local visible_buf_at_termopen
  local winfixbuf_at_termopen
  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_output.winfixbuf.test"),
    state = {
      mission_dashboard_output_buf = old_buf,
      mission_dashboard_output_win = win,
      mission_dashboard_output_buf_kind = "status",
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function()
      visible_buf_at_termopen = vim.api.nvim_win_get_buf(win)
      winfixbuf_at_termopen = vim.api.nvim_get_option_value("winfixbuf", { win = win })
      return 77
    end,
  })
  controller:attach_output_buffer_autocmd(old_buf)

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  assert_equal(vim.api.nvim_win_get_buf(win), controller.state.mission_dashboard_output_buf)
  assert_equal(visible_buf_at_termopen, controller.state.mission_dashboard_output_buf)
  assert_false(winfixbuf_at_termopen)
  assert_false(vim.api.nvim_get_option_value("winfixbuf", { win = win }))
  assert_true(vim.api.nvim_win_is_valid(controller.state.mission_dashboard_output_win))
  assert_false(vim.api.nvim_buf_is_valid(old_buf))
  assert_nil(controller.state.mission_dashboard_output_replacing_buf)
  local output_buf = controller.state.mission_dashboard_output_buf
  vim.api.nvim_win_close(win, true)
  if vim.api.nvim_buf_is_valid(output_buf) then
    vim.api.nvim_buf_delete(output_buf, { force = true })
  end
end

if type(vim.api) == "table" then
  local output_buf = vim.api.nvim_create_buf(false, true)
  local other_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, { "other buffer" })
  local win = vim.api.nvim_open_win(output_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 40,
    height = 3,
    style = "minimal",
  })
  vim.api.nvim_set_option_value("winfixbuf", true, { win = win })

  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = output_buf,
      mission_dashboard_output_win = win,
      mission_dashboard_output_job = 77,
    },
  })

  assert_true(controller:focus_output_panel())
  assert_false(vim.api.nvim_get_option_value("winfixbuf", { win = win }))
  local ok, error_message = pcall(vim.cmd, "buffer " .. tostring(other_buf))
  assert_true(ok, tostring(error_message))
  assert_equal(vim.api.nvim_win_get_buf(win), other_buf)

  vim.api.nvim_win_close(win, true)
  if vim.api.nvim_buf_is_valid(output_buf) then
    vim.api.nvim_buf_delete(output_buf, { force = true })
  end
  if vim.api.nvim_buf_is_valid(other_buf) then
    vim.api.nvim_buf_delete(other_buf, { force = true })
  end
end

if type(vim.api) == "table" then
  local old_buf = vim.api.nvim_create_buf(false, true)
  local deleted = {}
  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_output.swap_failure.test"),
    state = {
      mission_dashboard_output_buf = old_buf,
      mission_dashboard_output_win = 13,
      mission_dashboard_output_buf_kind = "status",
    },
    ui = {
      create_scratch_buffer = function(options)
        local bufnr = vim.api.nvim_create_buf(false, true)
        for option, value in pairs(options or {}) do
          pcall(vim.api.nvim_set_option_value, option, value, { buf = bufnr })
        end
        return bufnr
      end,
      set_lines = function(target, lines)
        vim.api.nvim_set_option_value("modifiable", true, { buf = target })
        vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
        vim.api.nvim_set_option_value("modifiable", false, { buf = target })
        return true
      end,
      delete_buffer = function(target)
        table.insert(deleted, target)
        if vim.api.nvim_buf_is_valid(target) then
          vim.api.nvim_buf_delete(target, { force = true })
        end
      end,
    },
    set_buffer_keymap = function()
      return true
    end,
  })
  function controller:set_output_window_buffer()
    return false
  end

  assert_false(controller:replace_output_buffer("terminal"))
  assert_equal(controller.state.mission_dashboard_output_buf, old_buf)
  assert_equal(controller.state.mission_dashboard_output_buf_kind, "status")
  assert_nil(controller.state.mission_dashboard_output_replacing_buf)
  assert_equal(#deleted, 1)
  assert_true(deleted[1] ~= old_buf)
  assert_true(vim.api.nvim_buf_is_valid(old_buf))
  assert_false(vim.api.nvim_buf_is_valid(deleted[1]))
  vim.api.nvim_buf_delete(old_buf, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local modified_at_termopen
  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_output.modified.test"),
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(target, lines, opts)
        opts = type(opts) == "table" and opts or {}
        if opts.modifiable then
          vim.api.nvim_set_option_value("modifiable", true, { buf = target })
        end
        vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
        if opts.modifiable then
          vim.api.nvim_set_option_value("modifiable", false, { buf = target })
        end
        return true
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function()
      modified_at_termopen = vim.api.nvim_get_option_value("modified", { buf = bufnr })
      return 77
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_false(modified_at_termopen)
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local preview_called = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_buf = 10,
      mission_dashboard_win = 11,
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
      mission_dashboard_items = {
        [3] = {
          kind = "mission",
          mission = {
            roles = {
              { safe_name = "alpha-builder", mission_role = "Builder", status = "inactive" },
              { safe_name = "alpha-reviewer", mission_role = "Reviewer", status = "idle" },
            },
          },
        },
      },
      mission_dashboard_selectable_rows = { 3 },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 3,
    },
    is_loaded_buf = function(target)
      return target == 10 or (target == bufnr and vim.api.nvim_buf_is_loaded(target))
    end,
    is_valid_win = function(win)
      return win == 11 or win == 13
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function(entry)
      preview_called = true
      assert_equal(entry.safe_name, "alpha-reviewer")
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function()
      return 77
    end,
  })

  assert_equal(controller:selected_output_entry().safe_name, "alpha-reviewer")
  assert_true(controller:render_output_panel())
  assert_true(preview_called)
  assert_contains(table.concat(rendered_lines, "\n"), "Output: Reviewer")
  assert_equal(controller.state.mission_dashboard_output_entry.safe_name, "alpha-reviewer")
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local preview_entry
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_buf = 10,
      mission_dashboard_win = 11,
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
      mission_dashboard_items = {
        [3] = {
          kind = "mission",
          mission = {
            roles = {
              { safe_name = "alpha-architect", mission_role = "Architect", status = "active" },
              { safe_name = "alpha-reviewer", mission_role = "Reviewer", status = "question" },
            },
          },
        },
      },
      mission_dashboard_selectable_rows = { 3 },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 3,
    },
    is_loaded_buf = function(target)
      return target == 10 or (target == bufnr and vim.api.nvim_buf_is_loaded(target))
    end,
    is_valid_win = function(win)
      return win == 11 or win == 13
    end,
    ui = {
      set_lines = function()
        return true
      end,
    },
    workspace_interactive_preview = function(entry)
      preview_entry = entry
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function()
      return 77
    end,
  })

  assert_equal(controller:selected_output_entry().safe_name, "alpha-reviewer")
  assert_true(controller:render_output_panel())
  assert_equal(preview_entry.safe_name, "alpha-reviewer")
  assert_equal(controller.state.mission_dashboard_output_entry.safe_name, "alpha-reviewer")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local preview_called = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_buf = 10,
      mission_dashboard_win = 11,
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
      mission_dashboard_items = {
        [3] = {
          kind = "mission",
          mission = {
            roles = {
              { safe_name = "alpha-builder", mission_role = "Builder", status = "inactive" },
              { safe_name = "alpha-reviewer", mission_role = "Reviewer", status = "inactive" },
            },
          },
        },
      },
      mission_dashboard_selectable_rows = { 3 },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 3,
    },
    is_loaded_buf = function(target)
      return target == 10 or (target == bufnr and vim.api.nvim_buf_is_loaded(target))
    end,
    is_valid_win = function(win)
      return win == 11 or win == 13
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      preview_called = true
      return nil, "should not be called"
    end,
  })

  assert_equal(controller:selected_output_entry().safe_name, "alpha-builder")
  assert_true(controller:render_output_panel())
  assert_false(preview_called)
  assert_equal(table.concat(rendered_lines, "\n"), "Output: workspace inactive")
  assert_equal(controller.state.mission_dashboard_output_entry.safe_name, "alpha-builder")
  assert_nil(controller.state.mission_dashboard_output_job)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local closed_preview
  local termopen_calls = 0
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
    termopen = function()
      termopen_calls = termopen_calls + 1
      error("permission denied")
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  local rendered_text = table.concat(rendered_lines, "\n")
  assert_contains(rendered_text, "failed to attach workspace session preview: ")
  assert_contains(rendered_text, "permission denied")
  assert_contains(rendered_text, "env -u TMUX tmux attach-session -t codux-preview-test")
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
  assert_equal(termopen_calls, 1)
  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(termopen_calls, 1)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local on_exit
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    termopen = function(_, opts)
      on_exit = opts.on_exit
      return 77
    end,
    jobstop = function()
      return true
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_true(controller:render_output_panel({
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "inactive",
  }))
  on_exit(77, 2)
  assert_equal(table.concat(rendered_lines, "\n"), "Output: workspace inactive")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local closed_preview
  local termopen_calls = 0
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
    termopen = function()
      termopen_calls = termopen_calls + 1
      return 0
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  local rendered_text = table.concat(rendered_lines, "\n")
  assert_contains(rendered_text, "failed to attach workspace session preview: invalid job id 0")
  assert_contains(rendered_text, "env -u TMUX tmux attach-session -t codux-preview-test")
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
  assert_equal(termopen_calls, 1)
  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(termopen_calls, 1)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local closed_preview
  local on_exit
  local termopen_calls = 0
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      return {
        command = { "env", "-u", "TMUX", "tmux", "attach-session", "-t", "codux-preview-test" },
        preview_session = "codux-preview-test",
      }, nil
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
    termopen = function(_, opts)
      termopen_calls = termopen_calls + 1
      on_exit = opts.on_exit
      return 77
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(controller.state.mission_dashboard_output_job, 77)
  on_exit(77, 2)
  assert_contains(table.concat(rendered_lines, "\n"), "workspace preview exited with code 2")
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
  assert_equal(termopen_calls, 1)
  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "idle",
  }))
  assert_equal(termopen_calls, 1)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  local rendered_lines
  local preview_called = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_buf = bufnr,
      mission_dashboard_output_win = 13,
    },
    is_loaded_buf = function(target)
      return target == bufnr and vim.api.nvim_buf_is_loaded(target)
    end,
    ui = {
      set_lines = function(_, lines)
        rendered_lines = lines
      end,
    },
    workspace_interactive_preview = function()
      preview_called = true
      return nil, "should not be called"
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "inactive",
  }))
  assert_false(preview_called)
  local rendered_text = table.concat(rendered_lines, "\n")
  assert_contains(rendered_text, "Output: workspace inactive")
  assert_equal(rendered_text:find("Output: Reviewer", 1, true), nil)
  assert_equal(rendered_text:find("alpha-reviewer", 1, true), nil)
  assert_equal(rendered_text:find("Ctrl-o workspace", 1, true), nil)
  assert_equal(rendered_text:find("Ctrl-q", 1, true), nil)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

if type(vim.api) == "table" then
  local terminal_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_call(terminal_buf, function()
    vim.fn.termopen({ "sh", "-c", "printf stale-terminal; exit 0" })
  end)
  vim.wait(100)

  local controller = mission_control_mod.new({
    namespace = vim.api.nvim_create_namespace("codux.mission_output.replace_terminal.test"),
    state = {
      mission_dashboard_output_buf = terminal_buf,
      mission_dashboard_output_win = 13,
      mission_dashboard_output_buf_kind = "terminal",
    },
    is_valid_win = function()
      return false
    end,
  })

  assert_true(controller:render_output_panel({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "inactive",
  }))
  assert_true(controller.state.mission_dashboard_output_buf ~= terminal_buf)
  assert_equal(vim.api.nvim_get_option_value("buftype", { buf = controller.state.mission_dashboard_output_buf }), "nofile")
  local lines = vim.api.nvim_buf_get_lines(controller.state.mission_dashboard_output_buf, 0, -1, false)
  assert_equal(table.concat(lines, "\n"), "Output: workspace inactive")
  assert_false(vim.api.nvim_buf_is_valid(terminal_buf))
  vim.api.nvim_buf_delete(controller.state.mission_dashboard_output_buf, { force = true })
end

do
  local bound = {}
  local closed = false
  local opened_name
  local opened_root
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_entry = {
        name = "Builder",
        safe_name = "alpha-builder",
        project_root = "/repo",
        mission_role = "Builder",
        status = "idle",
      },
    },
    set_buffer_keymap = function(_, mode, lhs, rhs, desc)
      local modes = type(mode) == "table" and table.concat(mode, ",") or mode
      if modes:find("n", 1, true) or modes:find("t", 1, true) then
        bound[lhs] = { rhs = rhs, desc = desc, mode = modes }
      end
    end,
  })
  function controller:close_dashboard()
    closed = true
    return true
  end
  function controller:render_output_panel()
    return true
  end
  controller.open_saved_workspace = function(name, root)
    opened_name = name
    opened_root = root
    return true
  end

  controller:bind_output_panel_commands(12)
  assert_equal(bound["<C-q>"].desc, "Close Codux Missions")
  assert_equal(bound["<C-o>"].desc, "Open Codux Mission Workspace")
  assert_nil(bound.r)
  assert_nil(bound.o)
  assert_nil(bound.p)
  assert_nil(bound.e)
  assert_nil(bound.x)
  assert_nil(bound.d)
  assert_nil(bound.n)
  assert_nil(bound.w)
  assert_true(bound["<C-q>"].rhs())
  assert_true(closed)
  assert_true(bound["<C-o>"].rhs())
  assert_equal(opened_name, "alpha-builder")
  assert_equal(opened_root, "/repo")
end

do
  local closed = false
  local opened_name
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_items = {
        [5] = {
          kind = "role",
          entry = {
            name = "Builder",
            safe_name = "alpha-builder",
            project_root = "/repo",
            mission_role = "Builder",
            status = "idle",
          },
        },
      },
      mission_dashboard_search_confirmed = true,
      mission_dashboard_selected_row = 5,
      mission_dashboard_output_entry = {
        name = "Stale",
        safe_name = "stale-builder",
        project_root = "/repo",
      },
    },
    open_saved_workspace = function(name)
      opened_name = name
      return true
    end,
  })
  function controller:close_dashboard()
    closed = true
    return true
  end

  assert_true(controller:open_output_workspace())
  assert_equal(opened_name, "alpha-builder")
  assert_true(closed)
end

do
  local closed = false
  local opened_name
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_entry = {
        name = "Builder",
        safe_name = "alpha-builder",
        project_root = "/repo",
      },
    },
    open_saved_workspace = function(name)
      opened_name = name
      return false
    end,
  })
  function controller:close_dashboard()
    closed = true
    return true
  end

  assert_false(controller:open_output_workspace())
  assert_equal(opened_name, "alpha-builder")
  assert_false(closed)
end

do
  local notifications = {}
  local controller = mission_control_mod.new({
    state = {},
    notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end,
  })

  assert_false(controller:open_output_workspace())
  assert_equal(notifications[1].message, "No Codux workspace selected")
  assert_equal(notifications[1].level, vim.log.levels.WARN)
end

do
  local stopped_job
  local closed_preview
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_output_job = 77,
      mission_dashboard_output_preview = { preview_session = "codux-preview-test" },
    },
    jobstop = function(job_id)
      stopped_job = job_id
      return true
    end,
    close_workspace_interactive_preview = function(preview)
      closed_preview = preview
      return true
    end,
  })

  controller:close_output_preview()
  assert_equal(stopped_job, 77)
  assert_equal(closed_preview.preview_session, "codux-preview-test")
  assert_nil(controller.state.mission_dashboard_output_job)
  assert_nil(controller.state.mission_dashboard_output_preview)
end

do
  local sent_prompt
  local notifications = {}
  local entry = { name = "alpha-builder", safe_name = "alpha-builder", mission_role = "Builder", status = "idle" }
  local controller = mission_control_mod.new({
    notify = function(message)
      table.insert(notifications, message)
    end,
    ui = {
      single_line_prompt = function(opts, callback)
        assert_contains(opts.prompt, "Builder")
        callback("  /plan  ")
        return true
      end,
    },
    send_prompt_to_workspace = function(workspace, prompt)
      assert_equal(workspace.safe_name, "alpha-builder")
      sent_prompt = prompt
      return true, nil
    end,
  })

  assert_true(controller:open_workspace_prompt(entry))
  assert_equal(sent_prompt, "  /plan  ")
  assert_contains(notifications[#notifications], "Sent prompt to Builder")
end

do
  local notifications = {}
  local prompted = false
  local sent = false
  local controller = mission_control_mod.new({
    notify = function(message)
      table.insert(notifications, message)
    end,
    ui = {
      single_line_prompt = function()
        prompted = true
        return true
      end,
    },
    send_prompt_to_workspace = function()
      sent = true
      return true, nil
    end,
  })

  assert_false(controller:open_workspace_prompt({
    name = "alpha-reviewer",
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "inactive",
  }))
  assert_false(prompted)
  assert_false(sent)
  assert_equal(notifications[#notifications], "workspace is inactive")
end

do
  local confirmed_message
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function(message, choices, default)
    confirmed_message = message
    assert_equal(choices, "&Yes\n&No")
    assert_equal(default, 2)
    return 2
  end
  local controller = mission_control_mod.new({
    mission_dirty_roles = function()
      return {
        { name = "mission-builder", reason = "dirty" },
        { name = "mission-reviewer", reason = "unknown" },
      }
    end,
  })

  assert_false(controller:confirm_delete_mission({ name = "Mission" }, "/repo"))
  assert_contains(confirmed_message, "permanently remove every role workspace")
  assert_contains(confirmed_message, "mission-builder")
  assert_contains(confirmed_message, "mission-reviewer (status unknown)")
  assert_contains(confirmed_message, "nuke uncommitted and untracked work")
  vim.fn.confirm = old_confirm
end

print("mission_control_spec.lua: ok")
