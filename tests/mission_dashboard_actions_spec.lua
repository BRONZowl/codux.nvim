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
local dashboard_controller = fixtures.dashboard_controller
local notifications_fixture = fixtures.notifications

do
  local opened_kind
  local opened_target
  local notifications, notify = notifications_fixture()
  local controller = dashboard_controller({
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
    notify = notify,
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
  assert_equal(bound["<C-o>"], "Control Codux Mission Role Output")
  assert_equal(bound.n, "Create Codux Mission")
  assert_equal(bound.c, "Clean Codux Mission Residue")
  assert_nil(bound.a)
  assert_nil(bound.o)
  assert_nil(bound.p)
  assert_nil(bound.i)
  assert_nil(bound.s)
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
  local prompted = false
  local controller = mission_control_mod.new({})
  function controller:open_prompt()
    prompted = true
    return true
  end
  function controller:close_dashboard()
    closed = true
  end

  assert_true(controller:create_new_mission())
  assert_true(prompted)
  assert_false(closed)
end

do
  local old_single_line_prompt = ui_mod.single_line_prompt
  local prompt_opts
  local opened_name
  ui_mod.single_line_prompt = function(opts, callback)
    prompt_opts = opts
    callback("Alpha")
    return true
  end

  local controller = mission_control_mod.new({})
  function controller:open_mission_provider_menu(name)
    opened_name = name
    return true
  end

  assert_true(controller:open_prompt())
  assert_equal(prompt_opts.prompt, "Codux mission: ")
  assert_equal(prompt_opts.zindex, 80)
  assert_equal(opened_name, "Alpha")
  ui_mod.single_line_prompt = old_single_line_prompt
end

do
  local opened
  local selected_opts
  local controller = mission_control_mod.new({
    select_provider_profile = function(opts)
      selected_opts = opts
      assert_equal(opts.open_provider, nil)
      assert_equal(opts.open_default, nil)
      assert_equal(opts.open_auto, nil)
      assert_equal(opts.open_danger, nil)
      return opts.on_select({
        agent_provider = "grok",
        profile = "auto",
      })
    end,
  })
  function controller:open_objective_editor(name, _, opts)
    opened = { name = name, agent_provider = opts.agent_provider, permission_profile = opts.permission_profile }
    return true
  end

  assert_true(controller:open_mission_provider_menu("Alpha"))
  assert_equal(selected_opts.provider_filetype, "codux-mission-provider")
  assert_equal(selected_opts.profile_filetype, "codux-mission-profile")
  assert_nil(selected_opts.agent_provider)
  assert_equal(opened.name, "Alpha")
  assert_equal(opened.agent_provider, "grok")
  assert_equal(opened.permission_profile, "auto")
end

do
  local selected_opts
  local opened
  local controller = mission_control_mod.new({
    default_agent_provider = function()
      return "codex"
    end,
    select_provider_profile = function(opts)
      selected_opts = opts
      return opts.on_select({
        agent_provider = opts.agent_provider,
        profile = "auto",
      })
    end,
  })
  function controller:open_objective_editor(name, _, opts)
    opened = { name = name, agent_provider = opts.agent_provider, permission_profile = opts.permission_profile }
    return true
  end

  assert_true(controller:open_mission_provider_menu("Alpha"))
  assert_equal(selected_opts.agent_provider, "codex")
  assert_equal(opened.agent_provider, "codex")
  assert_equal(opened.permission_profile, "auto")
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
        permission_profile = "danger",
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
  assert_false(closed)
  assert_equal(context.mission_id, "mission:alpha")
  assert_equal(context.mission_name, "Alpha")
  assert_equal(context.mission_objective, "Build it")
  assert_equal(context.permission_profile, "danger")
end

do
  local notifications, notify = notifications_fixture()
  local closed = false
  local prompted = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_action_workspace = {
        name = "plain",
        safe_name = "plain",
      },
    },
    notify = notify,
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
  local closed = false
  local refreshed_root
  local calls = {}
  local remaining_entries = {}
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_project_root = "/repo",
    },
    workspace_entries_for_project = function(root)
      assert_equal(root, "/repo")
      return remaining_entries
    end,
    close_mission = function(name, root)
      table.insert(calls, "close:" .. tostring(name) .. ":" .. tostring(root))
      return true
    end,
    delete_mission = function(name, root)
      table.insert(calls, "delete:" .. tostring(name) .. ":" .. tostring(root))
      return true
    end,
  })
  function controller:close_dashboard()
    closed = true
  end
  function controller:refresh_loaded_dashboard(root)
    refreshed_root = root
    return true
  end
  function controller:confirm_delete_mission()
    return true
  end

  assert_true(controller:close_selected_mission({ name = "Alpha" }))
  assert_equal(calls[1], "close:Alpha:/repo")
  assert_equal(refreshed_root, "/repo")
  assert_false(closed)

  refreshed_root = nil
  remaining_entries = { mission_role_entry("Beta") }
  assert_true(controller:delete_selected_mission({ name = "Alpha" }))
  assert_equal(calls[2], "delete:Alpha:/repo")
  assert_equal(refreshed_root, "/repo")
  assert_false(closed)
end

do
  local events = {}
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_project_root = "/repo",
    },
    workspace_entries_for_project = function(root)
      assert_equal(root, "/repo")
      return {}
    end,
    delete_mission = function(name, root)
      table.insert(events, "delete:" .. tostring(name) .. ":" .. tostring(root))
      return true
    end,
  })
  function controller:close_dashboard()
    table.insert(events, "close_dashboard")
    return true
  end
  function controller:refresh_loaded_dashboard()
    table.insert(events, "refresh")
    return true
  end
  function controller:confirm_delete_mission()
    return true
  end

  assert_true(controller:delete_selected_mission({ name = "Alpha" }))
  assert_equal(events[1], "delete:Alpha:/repo")
  assert_equal(events[2], "close_dashboard")
  assert_nil(events[3])
end

do
  local events = {}
  local confirmed = false
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_project_root = "/repo",
    },
    workspace_entries_for_project = function()
      error("dashboard should not update when delete is canceled or fails")
    end,
    delete_mission = function(name, root)
      table.insert(events, "delete:" .. tostring(name) .. ":" .. tostring(root))
      return false
    end,
  })
  function controller:close_dashboard()
    table.insert(events, "close_dashboard")
    return true
  end
  function controller:refresh_loaded_dashboard()
    table.insert(events, "refresh")
    return true
  end
  function controller:confirm_delete_mission()
    return confirmed
  end

  assert_false(controller:delete_selected_mission({ name = "Alpha" }))
  assert_nil(events[1])

  confirmed = true
  assert_false(controller:delete_selected_mission({ name = "Alpha" }))
  assert_equal(events[1], "delete:Alpha:/repo")
  assert_nil(events[2])
end

do
  local deleted = false
  local events = {}
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_buf = 22,
    },
    is_loaded_buf = function(bufnr)
      return bufnr == 22
    end,
    workspace_entries_for_project = function(root)
      assert_equal(root, "/repo")
      if deleted then
        return {}
      end
      return { mission_role_entry("Alpha") }
    end,
    delete_mission = function(name, root)
      deleted = true
      table.insert(events, "delete:" .. tostring(name) .. ":" .. tostring(root))
      return true
    end,
  })
  function controller:close_dashboard()
    table.insert(events, "close_dashboard")
    return true
  end
  function controller:refresh_loaded_dashboard()
    table.insert(events, "refresh")
    return true
  end
  function controller:confirm_delete_mission()
    return true
  end

  assert_true(controller:delete_saved_mission("Alpha", "/repo"))
  assert_equal(events[1], "delete:Alpha:/repo")
  assert_equal(events[2], "close_dashboard")
  assert_nil(events[3])
end

do
  local deleted = false
  local events = {}
  local controller = mission_control_mod.new({
    is_loaded_buf = function()
      return false
    end,
    workspace_entries_for_project = function(root)
      assert_equal(root, "/repo")
      return { mission_role_entry("Alpha") }
    end,
    delete_mission = function(name, root)
      deleted = true
      table.insert(events, "delete:" .. tostring(name) .. ":" .. tostring(root))
      return true
    end,
  })
  function controller:close_dashboard()
    table.insert(events, "close_dashboard")
    return true
  end
  function controller:refresh_loaded_dashboard()
    table.insert(events, "refresh")
    return true
  end
  function controller:confirm_delete_mission()
    return true
  end

  assert_true(controller:delete_saved_mission("Alpha", "/repo"))
  assert_true(deleted)
  assert_equal(events[1], "delete:Alpha:/repo")
  assert_nil(events[2])
end

do
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
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
    },
  })

  assert_false(controller:move_action_cursor(1))
  assert_false(controller:run_highlighted_action())
end

do
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
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
    },
  })
  function controller:close_dashboard() end

  assert_false(controller:run_highlighted_action())
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
  })
  local dashboard_closed = false
  function controller:close_dashboard()
    dashboard_closed = true
  end

  assert_true(controller:run_action("edit_instructions", entry))
  assert_true(controller:run_action("close_workspace", entry))
  assert_true(controller:run_action("delete_workspace", entry))
  assert_equal(calls[1], "edit:alpha-builder")
  assert_equal(calls[2], "close:alpha-builder")
  assert_contains(calls[3], "confirm:Delete Codux workspace alpha-builder?")
  assert_equal(calls[4], "delete:alpha-builder")
  assert_false(dashboard_closed)
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
  local refreshed_root
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
  function controller:refresh_loaded_dashboard(root)
    table.insert(events, "refresh")
    refreshed_root = root
  end

  assert_true(controller:start_selected_mission({ name = "Alpha" }))
  assert_equal(captured.name, "Alpha")
  assert_equal(captured.root, "/repo")
  assert_true(captured.opts.restart_inactive)
  assert_nil(captured.opts.prompt_roles)
  assert_false(captured.opts.focus_first)
  assert_equal(events[1], "start")
  assert_equal(events[2], "refresh")
  assert_equal(refreshed_root, "/repo")
end

do
  local events = {}
  local refreshed_root
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
  function controller:refresh_loaded_dashboard(root)
    table.insert(events, "refresh")
    refreshed_root = root
    return true
  end

  assert_false(controller:start_selected_mission({ name = "Alpha" }))
  assert_equal(events[1], "start")
  assert_equal(events[2], "refresh")
  assert_equal(refreshed_root, "/repo")
end

do
  local events = {}
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_project_root = "/repo",
    },
    is_loaded_buf = function()
      table.insert(events, "loaded")
      return false
    end,
    start_mission = function()
      table.insert(events, "start")
      return true
    end,
  })
  function controller:open_dashboard()
    error("mission actions should not open the dashboard while refreshing")
  end

  assert_true(controller:start_selected_mission({ name = "Alpha" }))
  assert_equal(events[1], "start")
  assert_equal(events[2], "loaded")
  assert_nil(events[3])
end

do
  local old_schedule = vim.schedule
  local saved_root
  local refreshed_root
  local closed = false
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
  function controller:close_dashboard()
    closed = true
  end
  function controller:open_objective_editor(_, _, opts)
    on_save = opts.on_save
    return true
  end
  function controller:refresh_loaded_dashboard(root)
    refreshed_root = root
    return true
  end

  assert_true(controller:edit_selected_mission({ name = "Alpha", objective = "old" }))
  assert_true(on_save("Alpha", "new"))
  assert_false(closed)
  assert_equal(saved_root, "/repo")
  assert_equal(refreshed_root, "/repo")
  vim.schedule = old_schedule
end

do
  local old_schedule = vim.schedule
  local saved_root
  local saved_focus
  local refreshed_root
  local on_save
  vim.schedule = function(callback)
    return callback()
  end
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_project_root = "/repo",
    },
    update_mission_focus_packet = function(_, focus_packet, root)
      saved_focus = focus_packet
      saved_root = root
      return true
    end,
  })
  function controller:open_objective_editor(_, default_focus, opts)
    assert_equal(default_focus, "old focus")
    on_save = opts.on_save
    return true
  end
  function controller:refresh_loaded_dashboard(root)
    refreshed_root = root
    return true
  end

  assert_true(controller:edit_selected_mission_focus({ name = "Alpha", focus_packet = "old focus" }))
  assert_true(on_save("Alpha", "new focus"))
  assert_equal(saved_focus, "new focus")
  assert_equal(saved_root, "/repo")
  assert_equal(refreshed_root, "/repo")
  vim.schedule = old_schedule
end


print("mission_dashboard_actions_spec.lua: ok")
