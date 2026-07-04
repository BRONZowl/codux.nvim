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
  local controller = mission_control_mod.new({
    token_usage_label = function()
      return "usage | 5hr 12% | wk 34%"
    end,
    workspace_entries_for_project = function()
      return {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_id = "mission:alpha",
          mission_name = "Alpha",
          mission_role = "Builder",
          status = "idle",
        },
      }, nil
    end,
  })

  local lines, items, rows = controller:dashboard_lines("/repo", { dashboard_width = 80 })
  assert_contains(lines[1], "1 mission | 1 role | active 0 | question 0 | idle 1")
  assert_contains(lines[2], "usage | 5hr 12% | wk 34%")
  assert_equal(items[4].kind, "mission")
  assert_equal(items[6].kind, "role")
  assert_equal(table.concat(rows, ","), "4,6")
end

do
  local controller = mission_control_mod.new({
    token_usage_label = function()
      return "usage | 5hr --% | wk --%"
    end,
    workspace_entries_for_project = function()
      return {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_id = "mission:alpha",
          mission_name = "Alpha",
          mission_role = "Builder",
          status = "idle",
        },
      }, nil
    end,
  })

  local lines, items, rows = controller:dashboard_lines("/repo", { dashboard_width = 80 })
  assert_contains(lines[2], "usage | 5hr --% | wk --%")
  assert_equal(items[4].kind, "mission")
  assert_equal(items[6].kind, "role")
  assert_equal(table.concat(rows, ","), "4,6")
end

do
  local controller = mission_control_mod.new({
    token_usage_label = function()
      return ""
    end,
    workspace_entries_for_project = function()
      return {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_id = "mission:alpha",
          mission_name = "Alpha",
          mission_role = "Builder",
          status = "idle",
        },
      }, nil
    end,
  })

  local lines, items, rows = controller:dashboard_lines("/repo", { dashboard_width = 80 })
  assert_equal(table.concat(lines, "\n"):find("usage |", 1, true), nil)
  assert_equal(items[3].kind, "mission")
  assert_equal(items[5].kind, "role")
  assert_equal(table.concat(rows, ","), "3,5")
end

do
  local controller = mission_control_mod.new({})
  local command_lines = controller:dashboard_command_lines(120)
  local command_text = table.concat(command_lines, "\n")
  assert_equal(#command_lines, 1)
  assert_true(command_lines[1]:find("Tab search", 1, true) ~= nil)
  assert_contains(command_text, "Tab search")
  assert_contains(command_text, "m menu")
  assert_contains(command_text, "p prompt")
  assert_contains(command_text, "i interrupt")
  assert_contains(command_text, "s mode")
  assert_equal(command_text:find("O preview", 1, true), nil)
  assert_equal(command_text:find("e edit", 1, true), nil)
  assert_equal(command_text:find("x close", 1, true), nil)
  assert_equal(command_text:find("d delete", 1, true), nil)
  assert_equal(command_text:find("j/k move", 1, true), nil)
  assert_equal(command_text:find("n mission", 1, true), nil)
  assert_equal(command_text:find("w workspace", 1, true), nil)
  assert_equal(command_text:find("q close", 1, true), nil)
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
    { key = "m", label = "menu" },
    { key = "p", label = "prompt" },
    { key = "i", label = "interrupt" },
    { key = "s", label = "mode" },
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
  controller:highlight_dashboard(12, {
    "1 mission | 1 role | active 0 | question 0 | idle 1",
    "usage | 5hr 12% | wk 34%",
  }, {})

  local found_usage = false
  for _, highlight in ipairs(highlights) do
    if highlight.group == "CoduxWhichKeyUsage" and highlight.row == 1 and highlight.start_col == 0 and highlight.end_col == -1 then
      found_usage = true
      break
    end
  end
  assert_true(found_usage)

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
      return 140
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
  assert_equal(command_text:find("O preview", 1, true), nil)
  assert_equal(command_text:find("e edit", 1, true), nil)
  assert_equal(command_text:find("x close", 1, true), nil)
  assert_equal(command_text:find("d delete", 1, true), nil)
  assert_equal(command_text:find("q close", 1, true), nil)

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
end

if type(vim.api) == "table" then
  local old_mouse = vim.o.mouse
  local old_open_win = vim.api.nvim_open_win
  local old_create_augroup = vim.api.nvim_create_augroup
  local old_create_autocmd = vim.api.nvim_create_autocmd
  local old_schedule = vim.schedule
  local output_entry = "unset"
  local token_refreshes = {}
  local search_opened = false
  vim.o.mouse = "a"
  vim.api.nvim_open_win = function()
    return 20
  end
  vim.api.nvim_create_augroup = function()
    return 91
  end
  vim.api.nvim_create_autocmd = function() end
  vim.schedule = function(callback)
    return callback()
  end

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {},
    is_valid_win = function(win)
      return win == 20
    end,
    is_loaded_buf = function(bufnr)
      return bufnr == 31
    end,
    get_window_config = function()
      return { col = 0, row = 0, width = 80, height = 8 }
    end,
    get_window_height = function()
      return 8
    end,
    get_window_width = function()
      return 80
    end,
    ui = {
      create_scratch_buffer = function()
        return 31
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
    set_buffer_keymap = function() end,
    set_window_cursor = function()
      return true
    end,
    refresh_token_usage = function(force)
      table.insert(token_refreshes, force)
      return true
    end,
  })
  function controller:dashboard_lines()
    return {
      "1 mission | 1 role | active 1 | question 0 | idle 0",
      "",
      "Alpha",
      "role",
      "Builder",
    }, {
      [3] = {
        kind = "mission",
        mission = {
          name = "Alpha",
          roles = {
            { safe_name = "alpha-builder", mission_role = "Builder", status = "active" },
          },
        },
      },
      [5] = {
        kind = "role",
        entry = { safe_name = "alpha-builder", mission_role = "Builder", status = "active" },
      },
    }, { 3, 5 }, nil
  end
  function controller:highlight_dashboard() end
  function controller:bind_dashboard_commands() end
  function controller:open_command_bar()
    return true
  end
  function controller:open_output_panel(entry)
    output_entry = entry
    return true
  end
  function controller:open_command_sink()
    return true
  end
  function controller:start_monitor_timer()
    return true
  end
  function controller:open_search_input()
    search_opened = true
    return true
  end

  assert_true(controller:open_dashboard("/repo"))
  assert_equal(controller.state.mission_dashboard_selected_row, 3)
  assert_nil(output_entry)
  assert_equal(#token_refreshes, 1)
  assert_true(token_refreshes[1])
  assert_true(search_opened)
  controller:close_dashboard()
  assert_equal(vim.o.mouse, "a")

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
  vim.schedule = old_schedule
  vim.o.mouse = old_mouse
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
  local close_opts
  local controller = mission_control_mod.new({
    state = {},
    bind_close_keys = function(_, _, _, _, opts)
      close_opts = opts
    end,
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
  assert_equal(bound.i, "Interrupt Codux Mission Role")
  assert_equal(bound.s, "Switch Codux Mission Role Mode")
  assert_nil(bound.n)
  assert_nil(bound.w)
  assert_nil(bound.O)
  assert_nil(bound.e)
  assert_nil(bound.x)
  assert_nil(bound.d)
  assert_nil(bound.q)
  assert_nil(bound.r)
  assert_true(close_opts.escape)
  assert_nil(close_opts.q)
end

do
  local closed = false
  local context
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_action_workspace = {
        name = "alpha-builder",
        safe_name = "alpha-builder",
        mission_id = "mission:alpha",
        mission_name = "Alpha",
        mission_objective = "Build it",
      },
    },
    create_workspace_prompt = function(opts)
      context = opts
      return true
    end,
  })
  function controller:close_dashboard()
    closed = true
  end

  assert_true(controller:create_new_workspace())
  assert_true(closed)
  assert_equal(context.mission_id, "mission:alpha")
  assert_equal(context.mission_name, "Alpha")
  assert_equal(context.mission_objective, "Build it")
end

do
  local notifications = {}
  local closed = false
  local prompted = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_action_workspace = {
        name = "plain",
        safe_name = "plain",
      },
    },
    notify = function(message)
      table.insert(notifications, message)
    end,
    create_workspace_prompt = function()
      prompted = true
      return true
    end,
  })
  function controller:close_dashboard()
    closed = true
  end

  assert_false(controller:create_new_workspace())
  assert_false(closed)
  assert_false(prompted)
  assert_equal(notifications[#notifications], "No Codux mission selected")
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
  local calls = {}
  local controller = mission_control_mod.new({})
  function controller:close_action_palette()
    table.insert(calls, "close_palette")
    return true
  end
  function controller:create_new_mission()
    table.insert(calls, "create_mission")
    return true
  end
  function controller:create_new_workspace()
    table.insert(calls, "create_workspace")
    return true
  end

  assert_true(controller:run_action("create_mission"))
  assert_true(controller:run_action("create_workspace"))
  assert_equal(calls[1], "close_palette")
  assert_equal(calls[2], "create_mission")
  assert_equal(calls[3], "close_palette")
  assert_equal(calls[4], "create_workspace")
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
  assert_nil(captured.opts.prompt_roles)
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
  local calls = {}
  local notifications = {}
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "active",
    codex_status = "working",
  }
  local controller = mission_control_mod.new({
    notify = function(message)
      table.insert(notifications, message)
    end,
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
      single_line_prompt = function(opts, callback)
        table.insert(calls, "prompt:" .. tostring(opts.prompt))
        callback("next task")
        return true
      end,
    },
    interrupt_workspace = function(workspace)
      table.insert(calls, "interrupt:" .. tostring(workspace.safe_name))
      return true, nil
    end,
    send_prompt_to_workspace = function(workspace, prompt)
      table.insert(calls, "send:" .. tostring(workspace.safe_name) .. ":" .. prompt)
      return true, nil
    end,
  })

  assert_true(controller:interrupt_selected_workspace(entry))
  assert_equal(calls[1], "interrupt:alpha-builder")
  assert_contains(calls[2], "prompt:Prompt Builder")
  assert_equal(calls[3], "send:alpha-builder:next task")
  assert_contains(notifications[#notifications], "Sent prompt to Builder")
end

do
  local calls = {}
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    codex_status = "idle",
  }
  local controller = mission_control_mod.new({
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
      single_line_prompt = function()
        table.insert(calls, "prompt")
        return true
      end,
    },
    interrupt_workspace = function()
      table.insert(calls, "interrupt")
      return true, nil
    end,
    send_prompt_to_workspace = function()
      table.insert(calls, "send")
      return true, nil
    end,
  })

  assert_false(controller:interrupt_selected_workspace(entry))
  assert_equal(#calls, 0)
end

do
  local prompted = false
  local notifications = {}
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "active",
    codex_status = "working",
  }
  local controller = mission_control_mod.new({
    notify = function(message)
      table.insert(notifications, message)
    end,
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
      single_line_prompt = function()
        prompted = true
        return true
      end,
    },
    interrupt_workspace = function()
      return false, "interrupt failed"
    end,
  })

  assert_false(controller:interrupt_selected_workspace(entry))
  assert_false(prompted)
  assert_equal(notifications[#notifications], "interrupt failed")
end

do
  local calls = {}
  local notifications = {}
  local rendered = false
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    codex_mode = "plan",
  }
  local controller = mission_control_mod.new({
    notify = function(message)
      table.insert(notifications, message)
    end,
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
    },
    switch_workspace_mode = function(workspace)
      table.insert(calls, "switch:" .. tostring(workspace.safe_name))
      return true, nil
    end,
  })
  function controller:render_dashboard()
    rendered = true
  end

  assert_true(controller:switch_selected_workspace_mode(entry))
  assert_equal(calls[1], "switch:alpha-builder")
  assert_true(rendered)
  assert_equal(notifications[#notifications], "Switched Codux mode for Builder")
end

do
  local notifications = {}
  local rendered = false
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    codex_mode = "plan",
  }
  local controller = mission_control_mod.new({
    notify = function(message)
      table.insert(notifications, message)
    end,
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
    },
    switch_workspace_mode = function()
      return false, "workspace is inactive"
    end,
  })
  function controller:render_dashboard()
    rendered = true
  end

  assert_false(controller:switch_selected_workspace_mode(entry))
  assert_false(rendered)
  assert_equal(notifications[#notifications], "workspace is inactive")
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

do
  local old_mouse = vim.o.mouse
  vim.o.mouse = "a"
  local controller = mission_control_mod.new({ state = {} })

  assert_true(controller:lock_dashboard_mouse())
  assert_equal(vim.o.mouse, "")
  assert_equal(controller.state.mission_dashboard_saved_mouse, "a")

  vim.o.mouse = "n"
  assert_true(controller:lock_dashboard_mouse())
  assert_equal(vim.o.mouse, "")
  assert_equal(controller.state.mission_dashboard_saved_mouse, "a")

  assert_true(controller:restore_dashboard_mouse())
  assert_equal(vim.o.mouse, "a")
  assert_nil(controller.state.mission_dashboard_saved_mouse)
  vim.o.mouse = old_mouse
end

if type(vim.api) == "table" then
  local old_mouse = vim.o.mouse
  local old_open_win = vim.api.nvim_open_win
  local deleted_buf
  vim.o.mouse = "a"
  vim.api.nvim_open_win = function()
    error("open failed")
  end

  local controller = mission_control_mod.new({
    notify = function() end,
    ui = {
      create_scratch_buffer = function()
        return 33
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function(bufnr)
        deleted_buf = bufnr
      end,
    },
  })
  function controller:dashboard_lines()
    return { "Mission" }, {}, {}, nil
  end
  function controller:highlight_dashboard() end

  assert_false(controller:open_dashboard("/repo"))
  assert_equal(vim.o.mouse, "a")
  assert_nil(controller.state.mission_dashboard_saved_mouse)
  assert_equal(deleted_buf, 33)

  vim.api.nvim_open_win = old_open_win
  vim.o.mouse = old_mouse
end

if type(vim.api) == "table" then
  local old_mouse = vim.o.mouse
  local controller = mission_control_mod.new({ state = {} })
  vim.o.mouse = "a"

  assert_true(controller:lock_dashboard_mouse())
  assert_equal(vim.o.mouse, "")
  assert_true(controller:close_dashboard())
  assert_equal(vim.o.mouse, "a")
  assert_nil(controller.state.mission_dashboard_saved_mouse)
  vim.o.mouse = old_mouse
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
  assert_equal(output_config.focusable, false)
  assert_nil(output_config.footer)

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

  reserved_dashboard_config = controller:dashboard_config(18, {
    reserve_command_bar = true,
    reserve_output_panel = true,
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    dashboard_min_height = 2,
  })
  reserved_command_config = controller:dashboard_command_config(#controller:dashboard_command_lines(reserved_dashboard_config.width))
  reserved_output_config = controller:dashboard_output_config(2, {
    selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
    dashboard_min_height = 2,
  })
  assert_equal(reserved_dashboard_config.height, 2)
  assert_equal(reserved_output_config.height, 14)
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

    calls = {}
    assert_true(resize_controller:resize_dashboard_stack(18, {
      selected_item = { kind = "role", entry = { safe_name = "alpha-builder", status = "active" } },
      dashboard_min_height = 2,
    }))
    assert_equal(table.concat(calls, ","), "91,92,93")
    assert_equal(configs[91].height, 2)
    assert_equal(configs[92].height, 1)
    assert_equal(configs[93].height, 14)
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

  do
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 4 },
      [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
    }
    local items = {
      [4] = { kind = "mission", mission = { name = "Alpha" } },
      [6] = { kind = "role", mission = { name = "Alpha" }, entry = { safe_name = "alpha-builder", status = "active" } },
    }
    local controller = mission_control_mod.new({
      state = {
        mission_dashboard_buf = 90,
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
        mission_dashboard_items = items,
        mission_dashboard_selectable_rows = { 4, 6 },
        mission_dashboard_search_confirmed = true,
        mission_dashboard_selected_row = 6,
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
      ui = {
        set_lines = function()
          return true
        end,
      },
    })
    function controller:dashboard_lines()
      return { "Mission", "usage | 5hr 12% | wk 34%", "", "Alpha", "role", "Builder" }, items, { 4, 6 }, nil
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
    assert_equal(configs[91].height, 2)
    assert_equal(configs[93].height, 14)
  end

  do
    local now_ms = 1000
    local refresh_calls = 0
    local configs = {
      [91] = { relative = "editor", row = 0, col = 0, width = 80, height = 8 },
      [92] = { relative = "editor", row = 0, col = 0, width = 80, height = 1 },
      [93] = { relative = "editor", row = 0, col = 0, width = 80, height = 6 },
    }
    local items = {
      [3] = { kind = "mission", mission = { name = "Alpha" } },
    }
    local controller = mission_control_mod.new({
      state = {
        mission_dashboard_buf = 90,
        mission_dashboard_win = 91,
        mission_dashboard_command_bar_win = 92,
        mission_dashboard_output_win = 93,
        mission_dashboard_items = items,
        mission_dashboard_selectable_rows = { 3 },
        mission_dashboard_search_confirmed = true,
        mission_dashboard_selected_row = 3,
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
      refresh_token_usage = function(force)
        assert_false(force)
        refresh_calls = refresh_calls + 1
        return true
      end,
      token_usage_refresh_ms = function()
        return 60000
      end,
      token_usage_now_ms = function()
        return now_ms
      end,
      ui = {
        set_lines = function()
          return true
        end,
      },
    })
    function controller:dashboard_lines()
      return { "Mission", "usage | 5hr --% | wk --%" }, items, { 3 }, nil
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

    assert_true(controller:render_dashboard())
    assert_equal(refresh_calls, 1)
    assert_true(controller:render_dashboard())
    assert_equal(refresh_calls, 1)
    now_ms = 62000
    assert_true(controller:render_dashboard())
    assert_equal(refresh_calls, 2)
  end

  local codux = require("codux")
  codux.setup({ token_monitor = false })
  assert_true(codux._v5.should_select_permission_profile(nil))
  assert_false(codux._v5.should_select_permission_profile(12))
  assert_equal(codux._v5.remote_show_existing_codex_terminal(), "not_running")
  assert_equal(codux._v5.remote_interrupt_codex_session(), "failed")
  assert_equal(codux._v5.remote_switch_codex_mode(), "failed")

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
  assert_equal(mission_map.desc, "create codux mission")
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

print("mission_control_spec.lua: ok")
