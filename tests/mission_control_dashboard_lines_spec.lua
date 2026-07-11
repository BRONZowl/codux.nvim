local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains
local fixtures = require("tests.mission_control_fixtures")

local mission_control_mod = require("codux.mission_control")
local ui_mod = require("codux.ui")
local workspace_ui = require("codux.workspace_ui")

local mission_role_entry = fixtures.mission_role_entry

do
  local controller = mission_control_mod.new({})
  assert_equal(controller:permission_profile_label({ permission_profile = "default" }), "Codex Default")
  assert_equal(controller:permission_profile_label({ permission_profile = "auto" }), "Codex Auto")
  assert_equal(controller:permission_profile_label({ permission_profile = "danger" }), "Codex Full")
  assert_equal(
    controller:permission_profile_label({ agent_provider = "grok", permission_profile = "default" }),
    "Grok Default"
  )
  assert_equal(controller:permission_profile_label({ agent_provider = "grok", permission_profile = "auto" }), "Grok Auto")
  assert_equal(controller:permission_profile_label({ agent_provider = "grok", permission_profile = "danger" }), "Grok Full")
end

do
  local controller = mission_control_mod.new({
    missions_for_project = function(root)
      assert_equal(root, "/repo")
      return {
        {
          name = "Alpha",
          mission_id = "mission:alpha",
          objective = "Build it",
          focus_packet = "# Mission Focus Packet\n\nCurrent User Intent:\nBuild dashboard UX",
          roles = {
            {
              name = "alpha-builder",
              safe_name = "alpha-builder",
              project_root = "/codux-worktrees/alpha-builder",
              mission_role = "Builder",
              status = "inactive",
              workspace_kind = "worktree",
            },
          },
        },
      }
    end,
    workspace_entries_for_project = function()
      error("dashboard should use mission lookup when available")
    end,
  })

  local lines, items, rows = controller:dashboard_lines("/repo", { dashboard_width = 100, now = 100 })
  local text = table.concat(lines, "\n")
  assert_equal(controller:mission_count("/repo"), 1)
  assert_contains(text, "Alpha")
  assert_contains(text, "focus: Build dashboard UX")
  assert_contains(text, "Builder")
  assert_equal(items[3].kind, "mission")
  assert_nil(items[4])
  assert_equal(items[6].kind, "role")
  assert_equal(table.concat(rows, ","), "3,6")
end

do
  local controller = mission_control_mod.new({
    missions_for_project = function()
      return {}, nil
    end,
    mission_residue_for_project = function()
      return {
        count = 2,
        empty_project_buckets = { { path = "/codux-worktrees/debug-builder" } },
        leftover_directories = { { path = "/codux-worktrees/debug-reviewer", cleanable = true } },
      }, nil
    end,
  })

  local lines = controller:dashboard_lines("/repo", { dashboard_width = 100 })
  local text = table.concat(lines, "\n")
  assert_contains(text, "No Codux missions")
  assert_contains(text, "Stale Mission Control residue found")
  assert_contains(text, "1 empty state buckets | 1 leftover directories")
  assert_contains(text, "c cleanup empty residue | n create mission")
end

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
          agent_mode = "execute",
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
  assert_true(lines[3]:find("^%s+Alpha", 1, false) ~= nil)
  assert_equal(#(lines[3]:match("^(%s*)") or ""), #(lines[4]:match("^(%s*)") or "") - 2)
  assert_equal(lines[4]:find("attn", 1, true), nil)
  assert_equal(lines[4]:find("wt", 1, true), nil)
  assert_equal(lines[4]:find(" br ", 1, true), nil)
  assert_equal(lines[4]:find("merged", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("Mission Control", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("Output  Builder", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("builder output", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("Build the dashboard", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("objective", 1, true), nil)
  assert_contains(table.concat(lines, "\n"), "role")
  assert_contains(table.concat(lines, "\n"), "profile")
  assert_contains(table.concat(lines, "\n"), "age")
  assert_contains(table.concat(lines, "\n"), "review")
  assert_equal(table.concat(lines, "\n"):find("permission profile", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("last activity", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("needs review", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("worktree status", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find("window status", 1, true), nil)
  assert_equal(table.concat(lines, "\n"):find(" worktree ", 1, true), nil)
  assert_contains(table.concat(lines, "\n"), "cleanup")
  assert_equal(table.concat(lines, "\n"):find("cleanup status", 1, true), nil)
  assert_contains(table.concat(lines, "\n"), "target")
  assert_contains(table.concat(lines, "\n"), "Codex Auto")
  assert_contains(table.concat(lines, "\n"), "execute")
  assert_contains(table.concat(lines, "\n"), "1m")
  assert_contains(table.concat(lines, "\n"), "yes")
  assert_contains(table.concat(lines, "\n"), "dev/alpha-builder")
  assert_contains(table.concat(lines, "\n"), "not ready")
  assert_contains(table.concat(lines, "\n"), "merged")
  assert_contains(table.concat(lines, "\n"), "init.lua")
  assert_true(lines[4]:find("^%s+role%s+", 1, false) ~= nil)
  assert_true(workspace_ui.display_width(lines[4]) <= 180)
  local narrow_lines = controller:dashboard_lines("/repo", { now = now, dashboard_width = 80 })
  assert_true(workspace_ui.display_width(narrow_lines[3]) <= 80)
  assert_true(workspace_ui.display_width(narrow_lines[4]) <= 80)
  assert_true(workspace_ui.display_width(narrow_lines[5]) <= 80)
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
  assert_equal(controller:dashboard_min_height_for_lines(lines), 2, "codex usage line reserves height")
end

do
  local mission_dashboard = require("codux.mission_dashboard")
  assert_true(mission_dashboard.is_token_usage_line("usage | 5hr 12% | wk 34%"))
  assert_false(mission_dashboard.is_token_usage_line("quota | tpm 100% left | rpm 100% left"))
  assert_false(mission_dashboard.is_token_usage_line("1 mission | 1 role"))
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
    { key = "<C-o>", label = "control" },
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
  local old_api = vim.api
  local extmarks = {}
  vim.api = {
    nvim_buf_clear_namespace = function() end,
    nvim_buf_add_highlight = function() end,
    nvim_buf_set_extmark = function(bufnr, namespace, row, col, opts)
      table.insert(extmarks, {
        bufnr = bufnr,
        namespace = namespace,
        row = row,
        col = col,
        opts = opts,
      })
      return 1
    end,
  }

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard = {
        search_confirmed = true,
        selected_row = 2,
      }},
  })
  controller:highlight_dashboard(12, {
    "summary",
    "    Builder    active",
  }, {
    [2] = { kind = "role", entry = { status = "active" } },
  })

  assert_equal(#extmarks, 1)
  assert_equal(extmarks[1].row, 1)
  assert_equal(extmarks[1].col, 4)
  assert_equal(extmarks[1].opts.end_col, #"    Builder    active")
  assert_equal(extmarks[1].opts.hl_group, "IncSearch")
  assert_false(extmarks[1].opts.hl_eol)

  vim.api = old_api
end

do
  local old_api = vim.api
  local extmarks = {}
  vim.api = {
    nvim_buf_clear_namespace = function() end,
    nvim_buf_add_highlight = function() end,
    nvim_buf_set_extmark = function(bufnr, namespace, row, col, opts)
      table.insert(extmarks, {
        bufnr = bufnr,
        namespace = namespace,
        row = row,
        col = col,
        opts = opts,
      })
      return 1
    end,
  }

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard = {
        search_confirmed = false,
        selected_row = 2,
      }},
  })
  controller:highlight_dashboard(12, {
    "summary",
    "  Alpha    question  2 roles",
  }, {
    [2] = { kind = "mission", mission = { name = "Alpha" } },
  })

  assert_equal(#extmarks, 1)
  assert_equal(extmarks[1].row, 1)
  assert_equal(extmarks[1].col, 2)
  assert_equal(extmarks[1].opts.end_col, #"  Alpha    question  2 roles")
  assert_equal(extmarks[1].opts.hl_group, "IncSearch")
  assert_false(extmarks[1].opts.hl_eol)

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
    nvim_buf_set_extmark = function()
      error("extmark unavailable")
    end,
  }

  local controller = mission_control_mod.new({
    namespace = 99,
    state = {
      mission_dashboard = {
        best_match_row = 2,
      }},
  })
  controller:highlight_dashboard(12, {
    "summary",
    "  Alpha    question  2 roles",
  }, {
    [2] = { kind = "mission", mission = { name = "Alpha" } },
  })

  local selected_highlight
  for _, highlight in ipairs(highlights) do
    if highlight.group == "Visual" and highlight.row == 1 then
      selected_highlight = highlight
      break
    end
  end
  assert_true(type(selected_highlight) == "table")
  assert_equal(selected_highlight.start_col, 2)
  assert_equal(selected_highlight.end_col, #"  Alpha    question  2 roles")

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

print("mission_control_dashboard_lines_spec.lua: ok")
