package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

if type(vim) ~= "table" then
  local function deepcopy(value)
    if type(value) ~= "table" then
      return value
    end
    local copy = {}
    for key, item in pairs(value) do
      copy[key] = deepcopy(item)
    end
    return copy
  end

  vim = {
    deepcopy = deepcopy,
    env = {},
    tbl_isempty = function(value)
      return type(value) ~= "table" or next(value) == nil
    end,
    split = function(value, separator)
      value = tostring(value or "")
      separator = tostring(separator or "")
      if separator == "" then
        return { value }
      end
      local parts = {}
      local start = 1
      while true do
        local found = value:find(separator, start, true)
        if not found then
          table.insert(parts, value:sub(start))
          break
        end
        table.insert(parts, value:sub(start, found - 1))
        start = found + #separator
      end
      return parts
    end,
    o = {
      columns = 120,
      lines = 40,
      cmdheight = 1,
    },
    fn = {
      confirm = function()
        return 1
      end,
      expand = function(value)
        return tostring(value or "")
      end,
      fnamemodify = function(value, modifier)
        if modifier == ":t" then
          return tostring(value or ""):match("[^/]+$") or tostring(value or "")
        end
        if modifier == ":h" then
          return tostring(value or ""):match("(.+)/[^/]*$") or "."
        end
        return tostring(value or "")
      end,
      readfile = function()
        return {}
      end,
      mkdir = function()
        return 1
      end,
      strcharpart = function(value, start, length)
        value = tostring(value or "")
        start = tonumber(start) or 0
        if length == nil then
          return value:sub(start + 1)
        end
        return value:sub(start + 1, start + length)
      end,
      strchars = function(value)
        return #tostring(value or "")
      end,
      strdisplaywidth = function(value)
        return #tostring(value or "")
      end,
      writefile = function()
        return 0
      end,
    },
    log = {
      levels = {
        ERROR = 4,
        WARN = 3,
      },
    },
    loop = {
      cwd = function()
        return "/repo"
      end,
    },
  }
end

local runtime_mod = require("codux.workspace_runtime")
local mission_mod = require("codux.mission")
local mission_control_mod = require("codux.mission_control")
local prompt_actions_mod = require("codux.prompt_actions")
local workspace_store_mod = require("codux.workspace_store")
local workspace_ui = require("codux.workspace_ui")
local manager_mod = require("codux.workspace_manager")
local terminal_mod = require("codux.terminal")
local which_key_mod = require("codux.which_key")

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function assert_nil(actual, message)
  if actual ~= nil then
    error((message or "assertion failed") .. ": expected nil, got " .. tostring(actual), 2)
  end
end

local function assert_true(actual, message)
  if actual ~= true then
    error((message or "assertion failed") .. ": expected true, got " .. tostring(actual), 2)
  end
end

local function assert_false(actual, message)
  if actual ~= false then
    error((message or "assertion failed") .. ": expected false, got " .. tostring(actual), 2)
  end
end

local function assert_contains(value, expected, message)
  if not tostring(value or ""):find(expected, 1, true) then
    error((message or "assertion failed") .. ": expected " .. tostring(value) .. " to contain " .. tostring(expected), 2)
  end
end

do
  local mission, error_message = mission_mod.plan("Blow Socks Off", "Build a standout agentic engineering feature.")
  assert_nil(error_message)
  assert_equal(mission.name, "Blow Socks Off")
  assert_equal(mission.safe_name, "blow-socks-off")
  assert_equal(mission.mission_id, "mission:blow-socks-off")
  assert_equal(#mission.roles, 3)
  assert_equal(mission.roles[1].workspace_name, "blow-socks-off-architect")
  assert_equal(mission.roles[3].workspace_name, "blow-socks-off-reviewer")
  assert_contains(mission.roles[1].instruction, "Mission: Blow Socks Off")
  assert_contains(mission.roles[1].initial_prompt, "Start your Mission Control role now.")
  assert_contains(mission.roles[1].initial_prompt, "stay in plan mode")
end

do
  local mission, error_message = mission_mod.plan("Crew", "Ship it", {
    roles = {
      { name = "One", safe_name = "same" },
      { name = "Two", safe_name = "same" },
    },
  })
  assert_nil(mission)
  assert_equal(error_message, "Duplicate mission role: same")
end

do
  local mission, error_message = mission_mod.plan("Crew", "Ship it", {
    roles = {
      { name = "Build Lead", safe_name = "Build Lead", focus = "Build the feature." },
      { safe_name = "QA Lead", focus = "Verify the feature." },
    },
  })
  assert_nil(error_message)
  assert_equal(mission.roles[1].name, "Build Lead")
  assert_equal(mission.roles[1].safe_name, "build-lead")
  assert_equal(mission.roles[1].workspace_name, "crew-build-lead")
  assert_contains(mission.roles[1].instruction, "You are the Build Lead")
  assert_equal(mission.roles[2].name, "QA Lead")
  assert_equal(mission.roles[2].safe_name, "qa-lead")
  assert_equal(mission.roles[2].workspace_name, "crew-qa-lead")
end

do
  local mission, error_message = mission_mod.plan("Crew", "Ship it", {
    roles = {
      { name = "Builder One", safe_name = "Builder One" },
      { name = "Builder-One", safe_name = "builder-one" },
    },
  })
  assert_nil(mission)
  assert_equal(error_message, "Duplicate mission role: builder-one")
end

do
  local grouped = mission_mod.group_entries({
    { name = "alpha-builder", mission_id = "mission:alpha", mission_name = "Alpha", mission_role = "Builder" },
    { name = "plain" },
    { name = "alpha-architect", mission_id = "mission:alpha", mission_name = "Alpha", mission_role = "Architect" },
  })
  assert_equal(#grouped, 1)
  assert_equal(grouped[1].name, "Alpha")
  assert_equal(#grouped[1].roles, 2)
  assert_equal(grouped[1].roles[1].mission_role, "Architect")
  assert_equal(mission_mod.status_label(grouped[1]), "inactive")
  local found = assert(mission_mod.find_mission(grouped, "alpha"))
  assert_equal(found.name, "Alpha")
  assert_equal(mission_mod.names(grouped)[1], "Alpha")
end

do
  local role = mission_mod.role_from_entry({
    mission_role = "Research Lead",
    resolved_instruction = "Role focus:\nTrack architecture risks.\n\nStay inside this workspace",
  })
  assert_equal(role.name, "Research Lead")
  assert_equal(role.safe_name, "research-lead")
  assert_equal(role.focus, "Track architecture risks.")
end

do
  assert_equal(mission_mod.objective_preview("Ship a polished mission dashboard\nwith controls", 80), "Ship a polished mission dashboard")
  assert_equal(mission_mod.objective_preview("123456789", 6), "123...")
  local instruction = mission_mod.role_instruction("Alpha", "Old objective", {
    name = "Builder",
    safe_name = "builder",
    focus = "Build it.",
  })
  local updated = mission_mod.update_instruction_objective(instruction, "New objective")
  assert_contains(updated, "Objective:\nNew objective\n\nRole focus:")
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
          codex_mode = "execute",
          permission_profile = "auto",
          target_path = "/repo/lua/codux/init.lua",
        },
        {
          name = "alpha-reviewer",
          safe_name = "alpha-reviewer",
          mission_id = "mission:alpha",
          mission_name = "Alpha",
          mission_role = "Reviewer",
          mission_objective = "Build the dashboard\nKeep it sharp",
          status = "question",
        },
      }, nil
    end,
    workspace_terminal_snapshot = function(entry, opts)
      assert_equal(opts.max_lines, 8)
      if entry.safe_name == "alpha-builder" then
        return "builder output", nil
      end
      if entry.safe_name == "alpha-reviewer" then
        return "reviewer output", nil
      end
      return "", "missing output"
    end,
  })
  local lines, items = controller:dashboard_lines("/repo")
  assert_equal(lines[1], "Mission Control")
  assert_contains(table.concat(lines, "\n"), "2 roles")
  assert_contains(table.concat(lines, "\n"), "Alpha")
  assert_contains(table.concat(lines, "\n"), "Output: Builder")
  assert_contains(table.concat(lines, "\n"), "builder output")
  assert_contains(table.concat(lines, "\n"), "objective  Build the dashboard")
  assert_contains(table.concat(lines, "\n"), "profile")
  assert_contains(table.concat(lines, "\n"), "target")
  assert_contains(table.concat(lines, "\n"), "auto")
  assert_contains(table.concat(lines, "\n"), "init.lua")
  assert_equal(items[7].kind, "mission")
  assert_equal(items[10].kind, "role")
  assert_equal(items[10].entry.safe_name, "alpha-builder")

  local filtered_lines, filtered_items, filtered_rows, best_match_row =
    controller:dashboard_lines("/repo", { query = "rev" })
  assert_contains(table.concat(filtered_lines, "\n"), "Alpha")
  assert_equal(filtered_items[11].kind, "role")
  assert_equal(filtered_items[11].entry.safe_name, "alpha-reviewer")
  assert_equal(best_match_row, 11)
  assert_equal(table.concat(filtered_rows, ","), "7,10,11")

  local mission_lines, mission_items, _, mission_best_row = controller:dashboard_lines("/repo", { query = "alp" })
  assert_contains(table.concat(mission_lines, "\n"), "Alpha")
  assert_equal(mission_items[7].kind, "mission")
  assert_equal(mission_best_row, 7)

  local reviewer_lines = controller:dashboard_lines("/repo", {
    selected_item = {
      kind = "role",
      entry = {
        safe_name = "alpha-reviewer",
        mission_role = "Reviewer",
        status = "question",
      },
    },
  })
  assert_contains(table.concat(reviewer_lines, "\n"), "Output: Reviewer")
  assert_contains(table.concat(reviewer_lines, "\n"), "reviewer output")

  local no_match_lines, no_match_items, no_match_rows = controller:dashboard_lines("/repo", { query = "zzz" })
  assert_contains(table.concat(no_match_lines, "\n"), "No matching Codux missions")
  assert_equal(#no_match_items, 0)
  assert_equal(#no_match_rows, 0)
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

  assert_true(controller:move_action_cursor(1))
  assert_equal(cursor_set[1], 2)
  assert_true(controller:move_action_cursor(-1))
  assert_equal(cursor_set[1], 1)

  assert_true(controller:run_highlighted_action())
  assert_equal(ran_action, "edit:Alpha")
  assert_true(closed)
  assert_nil(controller.state.mission_dashboard_action_win)
end

do
  local calls = {}
  local entry = { name = "alpha-builder", safe_name = "alpha-builder" }
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function(message, choices, default)
    table.insert(calls, "confirm:" .. tostring(message) .. ":" .. tostring(choices) .. ":" .. tostring(default))
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
  assert_contains(dashboard_config.footer, "Tab search")
  assert_contains(dashboard_config.footer, "m menu")
  assert_equal(dashboard_config.footer:find("Enter open", 1, true), nil)
  assert_equal(dashboard_config.footer:find("j/k role", 1, true), nil)
  assert_contains(dashboard_config.footer, "p prompt")
  assert_contains(dashboard_config.footer, "n mission")
  assert_contains(dashboard_config.footer, "w workspace")
  assert_equal(dashboard_config.footer:find("output above", 1, true), nil)
  assert_equal(dashboard_config.footer:find("e/x/d mission", 1, true), nil)
  assert_equal(dashboard_config.footer:find("r refresh", 1, true), nil)
  assert_equal(dashboard_config.footer:find("q close", 1, true), nil)
  assert_true(objective_config.width <= 38)
  assert_true(preview_config.width <= 38)
  assert_true(dashboard_config.width <= 38)
  assert_true(objective_config.height <= 7)
  assert_true(preview_config.height <= 7)
  assert_true(dashboard_config.height <= 7)

  local codux = require("codux")
  codux.setup({ token_monitor = false })
  local mission_map = vim.fn.maparg("<leader>zm", "n", false, true)
  assert_true(vim.tbl_isempty(mission_map))
  local workspace_create_map = vim.fn.maparg("<leader>zw", "n", false, true)
  assert_true(vim.tbl_isempty(workspace_create_map))
  local workspaces_map = vim.fn.maparg("<leader>zW", "n", false, true)
  assert_true(vim.tbl_isempty(workspaces_map))
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
  assert_equal(dashboard_config.width, 106)
  vim.o.columns = old_columns
  vim.o.lines = old_lines
  vim.o.cmdheight = old_cmdheight

  assert_true(controller:open_objective_editor("Save Test"))
  local bufnr = vim.api.nvim_get_current_buf()
  assert_contains(vim.api.nvim_buf_get_name(bufnr), "codux://mission-objective/")
  assert_equal(vim.b[bufnr].codux_disable_completion, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "mission objective" })
  vim.cmd("write")
  assert_equal(captured_mission.name, "Save Test")
  assert_equal(captured_mission.objective, "mission objective")
end

do
  local selected = prompt_actions_mod.selection_from_lines({ "abcdef", "ghijkl" }, 2, 4, "V")
  assert_equal(selected, "abcdef\nghijkl")
end

do
  local selected = prompt_actions_mod.selection_from_lines({ "abcdef", "ghijkl" }, 2, 4, "v")
  assert_equal(selected, "bcdef\nghij")
end

do
  local selected = prompt_actions_mod.selection_from_lines({ "abcdef", "ghijkl" }, 2, 4, "\22")
  assert_equal(selected, "bcd\nhij")
end

do
  local selected = prompt_actions_mod.selection_from_lines({ "abcdef", "ghijkl" }, 2, 4, "\19")
  assert_equal(selected, "bcd\nhij")
end

do
  local actions = prompt_actions_mod.new({
    current_buffer = function()
      return 1
    end,
    buffer_lines = function(_, start_line, end_line)
      assert_equal(start_line, 0)
      assert_equal(end_line, 2)
      return { "abcdef", "ghijkl" }
    end,
  })
  local selected, start_line, end_line = actions:selection_from_positions({ 0, 2, 2, 0 }, { 0, 1, 4, 0 }, "\22")
  assert_equal(selected, "bcd\nhij")
  assert_equal(start_line, 1)
  assert_equal(end_line, 2)
end

do
  local actions = prompt_actions_mod.new({
    current_buffer = function()
      return 1
    end,
    buffer_lines = function(_, start_line, end_line)
      assert_equal(start_line, 0)
      assert_equal(end_line, 1)
      return { "abcdef" }
    end,
  })
  local selected, start_line, end_line = actions:selection_from_positions({ 0, 1, 4, 0 }, { 0, 1, 2, 0 }, "\22")
  assert_equal(selected, "bcd")
  assert_equal(start_line, 1)
  assert_equal(end_line, 1)
end

do
  local actions = prompt_actions_mod.new({
    current_buffer = function()
      return 1
    end,
    buffer_lines = function(_, start_line, end_line)
      assert_equal(start_line, 0)
      assert_equal(end_line, 2)
      return { "abcdef", "ghijkl" }
    end,
  })
  local selected, start_line, end_line = actions:selection_from_positions({ 0, 2, 2, 0 }, { 0, 1, 4, 0 }, "\19")
  assert_equal(selected, "bcd\nhij")
  assert_equal(start_line, 1)
  assert_equal(end_line, 2)
end

local function runtime_with_tmux(responses, state)
  return runtime_mod.new({
    state = state or {},
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      local response = responses[command]
      if response == nil then
        return "", 1
      end
      return response[1], response[2]
    end,
  })
end

local function review_workspace_record(fields)
  local record = {
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    tmux_window = "review",
    status = "inactive",
    codex_status = "idle",
  }
  for key, value in pairs(fields or {}) do
    record[key] = value
  end
  return record
end

local function workspace_state(workspaces, fields)
  local project = {
    workspaces = workspaces or {},
  }
  for key, value in pairs(fields or {}) do
    project[key] = value
  end
  return {
    projects = {
      ["/repo"] = project,
    },
  }
end

local function default_workspace_config()
  return {
    codex_cmd = "codex",
    workspace_auto_cmd = "codex-auto",
    danger_full_access_cmd = "codex-danger",
    workspaces = {
      tmux_cmd = "tmux",
      nvim_cmd = "nvim",
    },
  }
end

local function default_workspace_from_state(record, fallback)
  local workspace = vim.deepcopy(fallback)
  if type(record) == "table" then
    for key, value in pairs(record) do
      workspace[key] = value
    end
  end
  return workspace
end

local function default_state_record(_, workspace)
  return {
    name = workspace.name,
    safe_name = workspace.safe_name,
    project_root = workspace.project_root,
    resolved_instruction = workspace.resolved_instruction,
    target_path = workspace.target_path,
    target_type = workspace.target_type,
    permission_profile = workspace.permission_profile,
    tmux_window = workspace.window_name,
    status = workspace.status,
    codex_status = workspace.codex_status,
    git_branch = workspace.git_branch,
    workspace_kind = workspace.workspace_kind,
    git_common_dir = workspace.git_common_dir,
    worktree_path = workspace.worktree_path,
    worktree_branch = workspace.worktree_branch,
    worktree_base = workspace.worktree_base,
    worktree_base_commit = workspace.worktree_base_commit,
    mission_id = workspace.mission_id,
    mission_name = workspace.mission_name,
    mission_role = workspace.mission_role,
    mission_objective = workspace.mission_objective,
    nvim_server = workspace.nvim_server,
    initial_mode = workspace.initial_mode,
    codex_mode = workspace.codex_mode,
  }
end

local function project_state(_, state, root)
  state.projects[root] = state.projects[root] or { workspaces = {} }
  return state.projects[root]
end

local function with_filereadable(value, callback)
  local old_filereadable = vim.fn.filereadable
  vim.fn.filereadable = function()
    return value
  end
  local ok, err = pcall(callback)
  vim.fn.filereadable = old_filereadable
  if not ok then
    error(err, 0)
  end
end

local function with_workspace_prepare_env(callback)
  local old_tmux = vim.env.TMUX
  local old_executable = vim.fn.executable
  local old_isdirectory = vim.fn.isdirectory
  local old_filereadable = vim.fn.filereadable
  local old_getcwd = vim.fn.getcwd
  local old_shellescape = vim.fn.shellescape

  vim.env.TMUX = "/tmp/tmux,1,0"
  vim.fn.executable = function()
    return 1
  end
  vim.fn.isdirectory = function(path)
    return path == "/repo" and 1 or 0
  end
  vim.fn.filereadable = function(path)
    return (path == "/repo/file.lua" or path == "/codux-worktrees/review/file.lua") and 1 or 0
  end
  vim.fn.getcwd = function()
    return "/repo"
  end
  vim.fn.shellescape = function(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
  end

  local ok, err = pcall(callback)
  vim.env.TMUX = old_tmux
  vim.fn.executable = old_executable
  vim.fn.isdirectory = old_isdirectory
  vim.fn.filereadable = old_filereadable
  vim.fn.getcwd = old_getcwd
  vim.fn.shellescape = old_shellescape
  if not ok then
    error(err, 0)
  end
end

local function workspace_prepare_runtime(opts)
  opts = opts or {}
  local custom_system = opts.system
  return runtime_mod.new({
    state = opts.state or {},
    notify = opts.notify,
    get_config = opts.get_config or default_workspace_config,
    current_target = opts.current_target or function()
      return { path = "/repo/file.lua", type = "file" }
    end,
    current_buffer_name = opts.current_buffer_name or function()
      return "/repo/file.lua"
    end,
    current_buffer = opts.current_buffer or function()
      return 1
    end,
    alternate_buffer = opts.alternate_buffer or function()
      return 1
    end,
    list_buffers = opts.list_buffers or function()
      return {}
    end,
    is_loaded_buf = opts.is_loaded_buf or function()
      return false
    end,
    git_root_for = opts.git_root_for or function()
      return "/repo"
    end,
    git_branch_for = opts.git_branch_for or function()
      return "main"
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if custom_system then
        local output, code = custom_system(args)
        if code == 0 or output ~= "" or command:find("^tmux") then
          return output, code
        end
      end
      if command == "git -C /repo status --porcelain" then
        return "", 0
      end
      if command == "git -C /repo branch --show-current" then
        return "main\n", 0
      end
      if command == "git -C /repo rev-parse main" then
        return "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 0
      end
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
        return "", 1
      end
      if command == "git -C /repo worktree add -b dev/review /codux-worktrees/review main" then
        return "", 0
      end
      if command == "git -C /repo worktree remove --force /codux-worktrees/review" then
        return "", 0
      end
      if command == "git -C /repo branch -D dev/review" then
        return "", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 1
      end
      return "", 1
    end,
    store = opts.store or {},
  })
end

local function workspace_store(opts)
  opts = opts or {}
  local state_data = opts.state_data or { projects = {} }
  return {
    state_data = function()
      return state_data
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = opts.write_state or function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = opts.project_state or project_state,
      workspace_from_state = opts.workspace_from_state or default_workspace_from_state,
      state_record = opts.state_record or default_state_record,
      instruction_file_path = opts.instruction_file_path or function()
        return "/repo/.agents/codux/review.md"
      end,
      read_instruction_file = opts.read_instruction_file or function()
        return nil
      end,
      write_instruction_file = opts.write_instruction_file or function()
        return true, nil
      end,
      delete_instruction_file = opts.delete_instruction_file or function()
        return true, nil
      end,
      instruction_file_records = opts.instruction_file_records or function()
        return {}
      end,
      resolve_workspace_resume_session = opts.resolve_workspace_resume_session or function() end,
    },
  }
end

local function workspace_delete_runtime(store, opts)
  opts = opts or {}
  return runtime_mod.new({
    state = opts.state or {
      workspace_manager_project_root = "/repo",
    },
    notify = opts.notify or function() end,
    render_workspace_manager = opts.render_workspace_manager or function() end,
    close_workspace_manager = opts.close_workspace_manager or function() end,
    system = opts.system,
    store = store,
  })
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      table.insert(calls, table.concat(args, " "))
      return "", 0
    end,
  })

  local status = runtime:workspace_instruction_ignore_status("/repo")
  assert_equal(status.status, "ignored")
  assert_equal(status.relative_dir, ".agents/codux")
  assert_equal(status.rule, ".agents/")
  assert_equal(calls[1], "git -C /repo check-ignore --quiet -- .agents/codux/.codux-ignore-check")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })

  local status = runtime:workspace_instruction_ignore_status("/repo")
  assert_equal(status.status, "not_ignored")
  assert_contains(runtime:workspace_instruction_ignore_warning("/repo"), "run :CoduxWorkspaceIgnore")
end

do
  local calls = 0
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            enabled = false,
          },
        },
      }
    end,
    system = function()
      calls = calls + 1
      return "", 1
    end,
  })

  assert_equal(runtime:workspace_instruction_ignore_status("/repo").status, "skipped")
  assert_equal(calls, 0)
end

do
  local checked
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            directory = "codux-workspaces",
          },
        },
      }
    end,
    system = function(args)
      checked = table.concat(args, " ")
      return "", 1
    end,
  })

  local status = runtime:workspace_instruction_ignore_status("/repo")
  assert_equal(status.status, "not_ignored")
  assert_equal(status.rule, "codux-workspaces/")
  assert_equal(checked, "git -C /repo check-ignore --quiet -- codux-workspaces/.codux-ignore-check")
end

do
  local calls = 0
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            directory = "/tmp/codux-workspaces",
          },
        },
      }
    end,
    system = function()
      calls = calls + 1
      return "", 1
    end,
  })

  assert_equal(runtime:workspace_instruction_ignore_status("/repo").status, "skipped")
  assert_equal(calls, 0)
end

do
  local calls = 0
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            directory = "../codux-workspaces",
          },
        },
      }
    end,
    system = function()
      calls = calls + 1
      return "", 1
    end,
  })

  assert_equal(runtime:workspace_instruction_ignore_status("/repo").status, "skipped")
  assert_equal(calls, 0)
end

do
  local messages = {}
  local runtime = runtime_mod.new({
    state = {},
    get_config = default_workspace_config,
    notify = function(message)
      table.insert(messages, message)
    end,
    system = function()
      return "", 1
    end,
  })

  assert_true(runtime:warn_workspace_instruction_ignore("/repo"))
  assert_false(runtime:warn_workspace_instruction_ignore("/repo"))
  assert_equal(#messages, 1)
  assert_contains(messages[1], "Add .agents/ to .gitignore")
end

do
  local old_filereadable = vim.fn.filereadable
  local old_writefile = vim.fn.writefile
  local written_path
  local written_lines
  vim.fn.filereadable = function()
    return 0
  end
  vim.fn.writefile = function(lines, path)
    written_lines = lines
    written_path = path
    return 0
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.writefile = old_writefile

  assert_true(ok)
  assert_equal(message, "Added .agents/ to .gitignore")
  assert_equal(written_path, "/repo/.gitignore")
  assert_equal(written_lines[#written_lines], ".agents/")
end

do
  local old_filereadable = vim.fn.filereadable
  local old_readfile = vim.fn.readfile
  local old_writefile = vim.fn.writefile
  local written_lines
  vim.fn.filereadable = function()
    return 1
  end
  vim.fn.readfile = function()
    return { "*.log" }
  end
  vim.fn.writefile = function(lines)
    written_lines = lines
    return 0
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 0
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.readfile = old_readfile
  vim.fn.writefile = old_writefile

  assert_true(ok)
  assert_equal(message, "Added .agents/ to .gitignore")
  assert_equal(written_lines[#written_lines], ".agents/")
end

do
  local old_filereadable = vim.fn.filereadable
  local old_readfile = vim.fn.readfile
  local old_writefile = vim.fn.writefile
  local wrote = false
  vim.fn.filereadable = function()
    return 1
  end
  vim.fn.readfile = function()
    return { ".agents/" }
  end
  vim.fn.writefile = function()
    wrote = true
    return 0
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.readfile = old_readfile
  vim.fn.writefile = old_writefile

  assert_true(ok)
  assert_equal(message, "Codux workspace instructions are already ignored by Git")
  assert_false(wrote)
end

do
  local old_filereadable = vim.fn.filereadable
  local old_writefile = vim.fn.writefile
  vim.fn.filereadable = function()
    return 0
  end
  vim.fn.writefile = function()
    return -1
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to update .gitignore")
end

do
  local old_mkdir = vim.fn.mkdir
  local old_writefile = vim.fn.writefile
  local wrote = false
  vim.fn.mkdir = function()
    return 0
  end
  vim.fn.writefile = function()
    wrote = true
    return 0
  end

  local store = workspace_store_mod.new({
    get_workspace_config = function()
      return default_workspace_config().workspaces
    end,
  })
  local ok, message = store:write_instruction_file("/repo", "review", "review the backend")
  vim.fn.mkdir = old_mkdir
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to create Codux workspace instruction directory")
  assert_false(wrote)
end

do
  local old_mkdir = vim.fn.mkdir
  local old_writefile = vim.fn.writefile
  vim.fn.mkdir = function()
    return 1
  end
  vim.fn.writefile = function()
    return -1
  end

  local store = workspace_store_mod.new({
    get_workspace_config = function()
      return default_workspace_config().workspaces
    end,
  })
  local ok, message = store:write_instruction_file("/repo", "review", "review the backend")
  vim.fn.mkdir = old_mkdir
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to write Codux workspace instruction file")
end

do
  local old_mkdir = vim.fn.mkdir
  local old_writefile = vim.fn.writefile
  local wrote = false
  vim.fn.mkdir = function()
    return 0
  end
  vim.fn.writefile = function()
    wrote = true
    return 0
  end

  local store = workspace_store_mod.new({
    get_workspace_config = function()
      return {
        state_file = "/tmp/codux-workspaces.json",
      }
    end,
    json_encode = function()
      return "{}"
    end,
  })
  local ok, message = store:write_state({ projects = {} })
  vim.fn.mkdir = old_mkdir
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to create Codux workspace state directory")
  assert_false(wrote)
end

do
  local old_mkdir = vim.fn.mkdir
  local old_writefile = vim.fn.writefile
  vim.fn.mkdir = function()
    return 1
  end
  vim.fn.writefile = function()
    return -1
  end

  local store = workspace_store_mod.new({
    get_workspace_config = function()
      return {
        state_file = "/tmp/codux-workspaces.json",
      }
    end,
    json_encode = function()
      return "{}"
    end,
  })
  local ok, message = store:write_state({ projects = {} })
  vim.fn.mkdir = old_mkdir
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to write Codux workspace state")
end

do
  local runtime = runtime_with_tmux({
    ["tmux list-panes -t @1 -F #{pane_current_command}"] = { "bash\nnvim\n", 0 },
  })

  assert_equal(runtime:status_for_window("@1"), "active", "nvim in any pane should mark window active")
end

do
  local runtime = runtime_with_tmux({
    ["tmux list-panes -t @1 -F #{pane_current_command}"] = { "bash\nzsh\n", 0 },
  })

  assert_equal(runtime:status_for_window("@1"), "inactive", "non-nvim panes should mark window inactive")
end

do
  local runtime = runtime_with_tmux({})

  assert_equal(runtime:status_for_window(nil), "inactive")
  assert_equal(runtime:dashboard_workspace_status({ status = "idle", codex_status = "idle" }, nil), "inactive")
  assert_equal(runtime:dashboard_workspace_status({ status = "inactive", codex_status = "idle" }, nil), "inactive")
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("^nvim %-%-server /tmp/review%.sock %-%-remote%-expr", 1, false) then
          return "ok\n", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:send_prompt_to_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/review.sock",
    }, "  /plan  ", { attempts = 1 })
    assert_nil(error_message)
    assert_true(ok)
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "remote_send_to_codex")
    assert_contains(command_text, "  /plan  ")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:send_prompt_to_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/review.sock",
    }, "/plan", { attempts = 1 })
    assert_false(ok)
    assert_equal(error_message, "workspace is inactive")
    assert_equal(table.concat(commands, "\n"):find("remote_send_to_codex", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "bash\n", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:send_prompt_to_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/review.sock",
    }, "/plan", { attempts = 1 })
    assert_false(ok)
    assert_equal(error_message, "workspace is inactive")
    assert_equal(table.concat(commands, "\n"):find("remote_send_to_codex", 1, true), nil)
  end)
end

do
  assert_equal(workspace_ui.manager_mode_label({ status = "inactive", codex_mode = "plan" }), "--")
  assert_equal(workspace_ui.manager_mode_label({ status = "idle", codex_mode = "plan" }), "plan")
end

do
  local actions = workspace_ui.manager_action_items()
  local by_key = {}
  local labels_by_key = {}
  for _, action in ipairs(actions) do
    by_key[action.key] = action.action
    labels_by_key[action.key] = action.label
  end

  assert_nil(by_key.o)
  assert_equal(by_key.r, "rename")
  assert_equal(by_key.e, "edit_instructions")
  assert_equal(by_key.x, "close_window")
  assert_equal(by_key.X, "close_all_windows")
  assert_equal(by_key.d, "delete")
  assert_nil(by_key.h)
  assert_contains(workspace_ui.manager_action_line(actions[1], 40), "Rename Workspace")
  assert_equal(labels_by_key.X, "Close All Workspaces")
end

do
  local controller = which_key_mod.new({
    get_mode = function()
      return "not running"
    end,
  })
  local entries = controller:normal_entries({
    open = "<leader>zc",
    workspace = "<leader>zw",
    workspaces = "<leader>zW",
    missions = "<leader>zM",
  })
  local by_lhs = {}
  local by_desc = {}
  for _, entry in ipairs(entries) do
    by_lhs[entry.lhs] = entry.desc
    by_desc[entry.desc] = entry.lhs
  end

  assert_nil(by_desc["create codux mission"])
  assert_nil(by_desc["create codux workspace"])
  assert_nil(by_desc["current codux workspaces"])
  assert_nil(by_lhs["<leader>zm"])
  assert_nil(by_lhs["<leader>zw"])
  assert_nil(by_lhs["<leader>zW"])
  assert_equal(by_lhs["<leader>zM"], "mission control")
end

do
  local actions = workspace_ui.mission_action_items()
  local by_key = {}
  local labels_by_key = {}
  for _, action in ipairs(actions) do
    by_key[action.key] = action.action
    labels_by_key[action.key] = action.label
  end

  assert_equal(by_key.e, "edit_objective")
  assert_equal(by_key.x, "close_mission")
  assert_equal(by_key.d, "delete_mission")
  assert_nil(by_key.n)
  assert_nil(by_key.r)
  assert_contains(workspace_ui.mission_action_line(actions[1], 40), "Edit Objective")
  assert_equal(labels_by_key.x, "Close Mission")
end

do
  local actions = workspace_ui.role_workspace_action_items()
  local by_key = {}
  local labels_by_key = {}
  for _, action in ipairs(actions) do
    by_key[action.key] = action.action
    labels_by_key[action.key] = action.label
  end

  assert_equal(by_key.o, "open_workspace")
  assert_equal(by_key.e, "edit_instructions")
  assert_equal(by_key.x, "close_workspace")
  assert_equal(by_key.d, "delete_workspace")
  assert_nil(by_key.p)
  assert_nil(by_key.r)
  assert_nil(by_key.X)
  assert_contains(workspace_ui.role_workspace_action_line(actions[1], 40), "Open Workspace")
  assert_nil(labels_by_key.p)
  assert_equal(labels_by_key.d, "Delete Workspace")
end

do
  local controller = mission_control_mod.new({
    workspace_terminal_snapshot = function(entry, opts)
      assert_equal(entry.safe_name, "alpha-builder")
      assert_equal(opts.max_lines, 8)
      return "first line\nlatest line", nil
    end,
  })
  local lines = controller:output_lines({
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
  })
  assert_contains(table.concat(lines, "\n"), "Output: Builder")
  assert_contains(table.concat(lines, "\n"), "latest line")

  local inactive = controller:output_lines({
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "inactive",
  })
  assert_contains(table.concat(inactive, "\n"), "workspace is not active")
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
  local footer = workspace_ui.footer_line(workspace_ui.manager_footer_segments({}, 200))
  assert_contains(footer, "tab search/list")
  assert_contains(footer, "j/k move")
  assert_contains(footer, "m menu")
  assert_contains(footer, "h doctor")
  assert_contains(footer, "enter open")
  assert_equal(footer:find("s search", 1, true), nil)
  assert_equal(footer:find("r rename", 1, true), nil)
  assert_equal(footer:find("x close", 1, true), nil)
  assert_equal(footer:find("d delete", 1, true), nil)
end

do
  local header = workspace_ui.manager_header_line(120)
  assert_contains(header, "workspace")
  assert_contains(header, "status")
  assert_contains(header, "profile")
  assert_contains(header, "age")
  assert_equal(header:find("branch", 1, true), nil)
end

do
  local entries = workspace_ui.sort_entries({
    { name = "Backend Debug", status = "active", last_activity_at = "2026-06-30T12:00:00Z" },
    { name = "Code Review", status = "question", last_activity_at = "2026-06-29T12:00:00Z" },
    { name = "Architecture", status = "inactive", last_activity_at = "2026-06-30T13:00:00Z" },
  }, "status_recent")

  assert_equal(entries[1].name, "Code Review")
  assert_equal(entries[2].name, "Backend Debug")
  assert_equal(entries[3].name, "Architecture")

  local matches = workspace_ui.fuzzy_workspace_filter(entries, "cod")
  assert_equal(#matches, 1)
  assert_equal(matches[1].name, "Code Review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
        return "", 1
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(error_message)
  assert_equal(branch, "dev/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1/review" then
        return "", 1
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(error_message)
  assert_equal(branch, "dev1/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1" then
        return "", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev2" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev2/review" then
        return "", 1
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(error_message)
  assert_equal(branch, "dev2/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
        return "", 0
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(branch)
  assert_equal(error_message, "branch already exists: dev/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
  })

  assert_equal(runtime:renamed_worktree_branch({ worktree_branch = "dev1/review" }, "search"), "dev1/search")
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          docs = {
            name = "docs",
            safe_name = "docs",
            project_root = "/repo",
            tmux_window = "docs",
          },
        },
      },
      ["/codux-worktrees/review"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/codux-worktrees/review",
            tmux_window = "review",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_path = "/codux-worktrees/review",
            worktree_branch = "dev/review",
            worktree_base = "main",
          },
        },
      },
    },
  }
  local runtime = runtime_mod.new({
    store = {
      read_state = function()
        return state_data, nil
      end,
      instruction_file_records = function()
        return {}
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      return "", 1
    end,
  })

  local entries = runtime:entries_for_project("/repo")
  local by_name = {}
  for _, entry in ipairs(entries) do
    by_name[entry.name] = entry
  end
  assert_equal(by_name.docs.project_root, "/repo")
  assert_equal(by_name.review.project_root, "/codux-worktrees/review")
  assert_equal(by_name.review.worktree_branch, "dev/review")
end

do
  local builder_instruction = mission_mod.role_instruction("Alpha", "Old objective", {
    name = "Builder",
    safe_name = "builder",
    focus = "Build it.",
  })
  local reviewer_instruction = mission_mod.role_instruction("Alpha", "Old objective", {
    name = "Reviewer",
    safe_name = "reviewer",
    focus = "Review it.",
  })
  local state_data = {
    projects = {
      ["/codux-worktrees/alpha-builder"] = {
        workspaces = {
          ["alpha-builder"] = review_workspace_record({
            name = "alpha-builder",
            safe_name = "alpha-builder",
            project_root = "/codux-worktrees/alpha-builder",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
            mission_id = "mission:alpha",
            mission_name = "Alpha",
            mission_role = "Builder",
            mission_objective = "Old objective",
            resolved_instruction = builder_instruction,
          }),
        },
      },
      ["/codux-worktrees/alpha-reviewer"] = {
        workspaces = {
          ["alpha-reviewer"] = review_workspace_record({
            name = "alpha-reviewer",
            safe_name = "alpha-reviewer",
            project_root = "/codux-worktrees/alpha-reviewer",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
            mission_id = "mission:alpha",
            mission_name = "Alpha",
            mission_role = "Reviewer",
            mission_objective = "Old objective",
            resolved_instruction = reviewer_instruction,
          }),
        },
      },
    },
  }
  local written_instructions = {}
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        mission_id = "mission:alpha",
        mission_objective = "Old objective",
        resolved_instruction = builder_instruction,
        project_root = "/codux-worktrees/alpha-builder",
        safe_name = "alpha-builder",
      },
    },
    notify = function() end,
    render_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-07-02T00:00:00Z"
      end,
      project_state = project_state,
      instruction_file_records = function()
        return {}
      end,
      write_instruction_file = function(_, root, safe_name, instruction)
        table.insert(written_instructions, root .. ":" .. safe_name .. ":" .. instruction)
        return true, nil
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/alpha-builder status --porcelain" then
        return " M lua/codux/init.lua\n", 0
      end
      if command == "git -C /codux-worktrees/alpha-reviewer status --porcelain" then
        return "", 0
      end
      return "", 1
    end,
  })

  assert_equal(runtime:mission_names_for_project("/repo")[1], "Alpha")
  local ok, error_message = runtime:update_mission_objective("Alpha", "New objective", { project_root = "/repo" })
  assert_true(ok)
  assert_nil(error_message)
  assert_equal(
    state_data.projects["/codux-worktrees/alpha-builder"].workspaces["alpha-builder"].mission_objective,
    "New objective"
  )
  assert_contains(
    state_data.projects["/codux-worktrees/alpha-reviewer"].workspaces["alpha-reviewer"].resolved_instruction,
    "Objective:\nNew objective\n\nRole focus:"
  )
  assert_equal(runtime.state.workspace.mission_objective, "New objective")
  assert_equal(#written_instructions, 2)

  local dirty_roles, dirty_error = runtime:mission_dirty_roles("Alpha", { project_root = "/repo" })
  assert_nil(dirty_error)
  assert_equal(#dirty_roles, 1)
  assert_equal(dirty_roles[1].name, "alpha-builder")
  assert_equal(dirty_roles[1].reason, "dirty")

  assert_true(runtime:close_mission("Alpha", { project_root = "/repo" }))
  assert_equal(state_data.projects["/codux-worktrees/alpha-builder"].workspaces["alpha-builder"].status, "inactive")
  assert_equal(state_data.projects["/codux-worktrees/alpha-builder"].workspaces["alpha-builder"].codex_status, "idle")
  assert_nil(state_data.projects["/codux-worktrees/alpha-builder"].workspaces["alpha-builder"].codex_mode)
  assert_equal(state_data.projects["/codux-worktrees/alpha-reviewer"].workspaces["alpha-reviewer"].status, "inactive")
  assert_equal(state_data.projects["/codux-worktrees/alpha-reviewer"].workspaces["alpha-reviewer"].mission_id, "mission:alpha")

  local deleted = {}
  runtime.delete_saved_workspace = function(_, entry)
    table.insert(deleted, entry.safe_name)
    return true
  end
  assert_true(runtime:delete_mission("Alpha", { project_root = "/repo" }))
  table.sort(deleted)
  assert_equal(table.concat(deleted, ","), "alpha-builder,alpha-reviewer")
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
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function()
    error("fresh workspace should not prompt for deletion")
  end
  local state_data = workspace_state({}, {})
  state_data.projects = {
    ["/codux-worktrees/review"] = {
      workspaces = {
        review = review_workspace_record({
          project_root = "/codux-worktrees/review",
          workspace_kind = "worktree",
          git_common_dir = "/repo/.git",
          worktree_path = "/codux-worktrees/review",
          worktree_branch = "dev/review",
          worktree_base = "main",
          worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }),
      },
    },
  }
  local runtime = runtime_mod.new({
    state = {},
    store = {
      read_state = function()
        return state_data, nil
      end,
      instruction_file_records = function()
        return {}
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/review rev-list --count aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..dev/review" then
        return "0\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 0
      end
      return "", 1
    end,
  })

  local ok, err = pcall(function()
    assert_true(runtime:prompt_merged_workspaces("/repo"))
  end)
  vim.fn.confirm = old_confirm
  if not ok then
    error(err, 0)
  end
end

do
  local old_filereadable = vim.fn.filereadable
  local old_confirm = vim.fn.confirm
  vim.fn.filereadable = function()
    return 1
  end
  vim.fn.confirm = function()
    return 1
  end
  local state_data = workspace_state({}, {})
  state_data.projects = {
    ["/codux-worktrees/review"] = {
      workspaces = {
        review = review_workspace_record({
          project_root = "/codux-worktrees/review",
          workspace_kind = "worktree",
          git_common_dir = "/repo/.git",
          worktree_path = "/codux-worktrees/review",
          worktree_branch = "dev/review",
          worktree_base = "main",
          worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }),
      },
    },
  }
  local removed_worktree = false
  local deleted_branch = false
  local runtime = runtime_mod.new({
    state = {},
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = project_state,
      instruction_file_records = function()
        return {}
      end,
      instruction_file_path = function()
        return "/codux-worktrees/review/.agents/codux/review.md"
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    },
    notify = function() end,
    render_workspace_manager = function() end,
    close_workspace_manager = function() end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/review rev-list --count aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..dev/review" then
        return "1\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 0
      end
      if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
        removed_worktree = true
        return "", 0
      end
      if command == "git --git-dir=/repo/.git branch -D dev/review" then
        deleted_branch = true
        return "", 0
      end
      return "", 1
    end,
  })

  local ok, err = pcall(function()
    assert_true(runtime:prompt_merged_workspaces("/repo"))
    assert_true(removed_worktree)
    assert_true(deleted_branch)
    assert_nil(state_data.projects["/codux-worktrees/review"].workspaces.review)
  end)
  vim.fn.filereadable = old_filereadable
  vim.fn.confirm = old_confirm
  if not ok then
    error(err, 0)
  end
end

do
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function()
    error("backfilled workspace should not prompt during the same dashboard refresh")
  end
  local state_data = workspace_state({}, {})
  state_data.projects = {
    ["/codux-worktrees/review"] = {
      workspaces = {
        review = review_workspace_record({
          project_root = "/codux-worktrees/review",
          workspace_kind = "worktree",
          git_common_dir = "/repo/.git",
          worktree_path = "/codux-worktrees/review",
          worktree_branch = "dev/review",
          worktree_base = "main",
        }),
      },
    },
  }
  local runtime = runtime_mod.new({
    state = {},
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = project_state,
      instruction_file_records = function()
        return {}
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base dev/review main" then
        return "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", 0
      end
      return "", 1
    end,
  })

  local ok, err = pcall(function()
    assert_true(runtime:prompt_merged_workspaces("/repo"))
    assert_equal(
      state_data.projects["/codux-worktrees/review"].workspaces.review.worktree_base_commit,
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    )
  end)
  vim.fn.confirm = old_confirm
  if not ok then
    error(err, 0)
  end
end

do
  local bound = {}
  local controller = manager_mod.new({
    state = {},
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, mode, lhs, _rhs, desc)
      if mode == "n" then
        bound[lhs] = desc
      end
    end,
  })

  controller:bind_commands(12)

  assert_equal(bound.m, "Open Codux Workspace Menu")
  assert_equal(bound.h, "Run Codux Doctor")
  assert_equal(bound.j, "Next Codux Workspace")
  assert_equal(bound.k, "Previous Codux Workspace")
  assert_equal(bound["<CR>"], "Open Codux Workspace")
  assert_equal(bound["<Tab>"], "Search/List Codux Workspaces")
  assert_nil(bound.s)
  assert_nil(bound.r)
  assert_nil(bound.x)
  assert_nil(bound.d)
end

do
  local current_win = 20
  local cursors = {}
  local render_count = 0
  local controller = manager_mod.new({
    state = {
      workspace_manager_win = 10,
      workspace_manager_search_win = 20,
      workspace_manager_items = {
        { name = "Backend Debug" },
        { name = "Code Review" },
        { name = "Architecture" },
      },
      workspace_manager_best_match_index = 2,
      workspace_manager_search_confirmed = true,
      workspace_manager_selected_index = 2,
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
  function controller:render()
    render_count = render_count + 1
    return true
  end

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 10)
  assert_equal(cursors[10][1], 3)

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 20)

  assert_true(controller:move_workspace_selection(1))
  assert_equal(controller.state.workspace_manager_selected_index, 3)
  assert_equal(cursors[10][1], 4)
  assert_equal(controller:selected_item().name, "Architecture")

  assert_true(controller:move_workspace_selection(1))
  assert_equal(controller.state.workspace_manager_selected_index, 3)
  assert_equal(cursors[10][1], 4)

  assert_true(controller:move_workspace_selection(-1))
  assert_equal(controller.state.workspace_manager_selected_index, 2)
  assert_equal(cursors[10][1], 3)
  assert_equal(controller:selected_item().name, "Code Review")
  assert_equal(render_count, 3)
end

do
  local controller = manager_mod.new({
    state = {},
    workspace_manager_max_height = function()
      return 12
    end,
  })

  assert_equal(controller:dashboard_height(1), 5)
  assert_equal(controller:dashboard_height(9), 9)
  assert_equal(controller:dashboard_height(40), 12)
end

do
  local current_height = 5
  local configs = {}
  local controller = manager_mod.new({
    state = {
      workspace_manager_win = 10,
      workspace_manager_footer_win = 11,
    },
    is_valid_win = function(win)
      return win == 10 or win == 11
    end,
    get_window_config = function()
      return {
        relative = "editor",
        row = 4,
        col = 6,
        width = 84,
        height = current_height,
      }
    end,
    get_window_height = function(win)
      if win == 10 then
        return current_height
      end
      return 1
    end,
    get_window_width = function()
      return 84
    end,
    set_window_config = function(win, config)
      configs[win] = config
      if win == 10 then
        current_height = config.height
      end
      return true
    end,
    workspace_manager_max_height = function()
      return 9
    end,
  })

  assert_true(controller:resize_dashboard(20))
  assert_equal(configs[10].height, 9)
  assert_equal(configs[10].width, 84)
  assert_equal(configs[10].row, 4)
  assert_equal(configs[10].col, 6)
  assert_equal(configs[11].relative, "win")
  assert_equal(configs[11].win, 10)
  assert_equal(configs[11].row, 8)
  assert_equal(configs[11].width, 84)
end

do
  local calls = {}
  local controller = terminal_mod.new({})
  function controller:exit()
    table.insert(calls, { name = "exit" })
  end
  function controller:start_terminal(focus, initial_prompt, command, workspace, permission_profile, opts)
    table.insert(calls, {
      name = "start_terminal",
      focus = focus,
      initial_prompt = initial_prompt,
      command = command,
      workspace = workspace,
      permission_profile = permission_profile,
      hidden = type(opts) == "table" and opts.hidden,
    })
    return "started"
  end

  assert_equal(controller:restart_hidden_with_command("codex-auto", "auto", "hello"), "started")
  assert_equal(calls[1].name, "exit")
  assert_equal(calls[2].name, "start_terminal")
  assert_equal(calls[2].focus, false)
  assert_equal(calls[2].initial_prompt, "hello")
  assert_equal(calls[2].command, "codex-auto")
  assert_nil(calls[2].workspace)
  assert_equal(calls[2].permission_profile, "auto")
  assert_equal(calls[2].hidden, true)
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          stale = {
            name = "stale",
            safe_name = "stale",
            project_root = "/repo",
            tmux_window = "stale",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
          },
        },
      },
    },
  }
  local writes = 0
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        project_root = "/repo",
        safe_name = "stale",
        window_name = "stale",
      },
    },
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        return "@2\tother\n", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        writes = writes + 1
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
    },
  })

  assert_equal(runtime:sync_activity("working"), true)
  local record = state_data.projects["/repo"].workspaces.stale
  assert_equal(record.status, "inactive", "activity sync should not revive inactive window")
  assert_equal(record.codex_status, "idle")
  assert_equal(record.codex_mode, nil)
  assert_equal(writes, 1)
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
          },
          debug = {
            name = "debug",
            safe_name = "debug",
            project_root = "/repo",
            tmux_window = "debug",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
          },
        },
      },
    },
  }
  local messages = {}
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(messages, message)
    end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        return "@1\treview\n@2\tdebug\n", 0
      end
      if command == "tmux kill-window -t @1" or command == "tmux kill-window -t @2" then
        return "", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
    },
  })

  assert_true(runtime:close_all_saved_workspace_windows("/repo"))
  assert_equal(state_data.projects["/repo"].workspaces.review.status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "inactive")
  assert_nil(state_data.projects["/repo"].workspaces.debug.codex_mode)
  assert_contains(messages[#messages], "Closed 2 Codux workspaces")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
          },
          debug = {
            name = "debug",
            safe_name = "debug",
            project_root = "/repo",
            tmux_window = "debug",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        project_root = "/repo",
        safe_name = "debug",
        status = "active",
        codex_status = "working",
        codex_mode = "execute",
        tmux_target = "session:debug",
      },
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        return "@1\treview\n@2\tdebug\n", 0
      end
      if command == "tmux kill-window -t @1" then
        return "", 0
      end
      if command == "tmux kill-window -t @2" then
        return "", 1
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
    },
  })

  assert_false(runtime:close_all_saved_workspace_windows("/repo"))
  assert_equal(state_data.projects["/repo"].workspaces.review.status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "active")
  assert_equal(state_data.projects["/repo"].workspaces.debug.codex_status, "working")
  assert_equal(state_data.projects["/repo"].workspaces.debug.codex_mode, "execute")
  assert_equal(runtime.state.workspace.status, "active")
  assert_equal(runtime.state.workspace.codex_status, "working")
  assert_equal(runtime.state.workspace.codex_mode, "execute")
  assert_equal(runtime.state.workspace.tmux_target, "session:debug")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
          },
          debug = {
            name = "debug",
            safe_name = "debug",
            project_root = "/repo",
            tmux_window = "debug",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        project_root = "/repo",
        safe_name = "review",
        status = "idle",
        codex_status = "idle",
        codex_mode = "plan",
        tmux_target = "session:review",
      },
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        return "@1\treview\n@2\tdebug\n", 0
      end
      if command == "tmux kill-window -t @1" then
        return "", 0
      end
      if command == "tmux kill-window -t @2" then
        return "", 1
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
    },
  })

  assert_false(runtime:close_all_saved_workspace_windows("/repo"))
  assert_equal(state_data.projects["/repo"].workspaces.review.status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "active")
  assert_equal(runtime.state.workspace.status, "inactive")
  assert_equal(runtime.state.workspace.codex_status, "idle")
  assert_nil(runtime.state.workspace.codex_mode)
  assert_nil(runtime.state.workspace.tmux_target)
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            tmux_target = "session:review",
            status = "idle",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local messages = {}
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = nil
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(messages, message)
    end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      return "", 1
    end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_true(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_nil(state_data.projects["/repo"].workspaces.debug.tmux_target)
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_window, "debug")
  assert_contains(messages[#messages], "Renamed Codux workspace to debug")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            tmux_target = "session:review",
            status = "inactive",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function()
      return "", 1
    end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_true(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_name = "review",
  }, "debug"))
  assert_nil(state_data.projects["/repo"].workspaces.debug.tmux_target)
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_window, "debug")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "inactive")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            tmux_target = "session:review",
            status = "idle",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      return "", 1
    end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_true(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_target, "session:debug")
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_window, "debug")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "idle")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          old = {
            name = "old",
            safe_name = "old",
            project_root = "/repo",
            tmux_window = "old",
            status = "inactive",
            codex_status = "idle",
            codex_session_captured_at = "2026-06-30T12:00:00Z",
          },
          other = {
            name = "other",
            safe_name = "other",
            project_root = "/repo",
            tmux_window = "other",
            status = "inactive",
            codex_status = "idle",
            created_at = "2026-06-01T12:00:00Z",
          },
        },
      },
    },
  }
  local runtime = runtime_mod.new({
    state = {},
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      instruction_file_records = function()
        return {}
      end,
    },
  })

  local entries = runtime:entries_for_project("/repo")
  local by_name = {}
  for _, entry in ipairs(entries) do
    by_name[entry.name] = entry
  end

  assert_equal(by_name.old.codex_session_captured_at, "2026-06-30T12:00:00Z")
  assert_equal(workspace_ui.activity_timestamp(by_name.old), "2026-06-30T12:00:00Z")
  assert_equal(workspace_ui.sort_entries(entries, "status_recent")[1].name, "old")
end

do
  with_filereadable(1, function()
    local delete_calls = 0
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record(),
      }),
      write_state = function()
        return false, "write failed"
      end,
      delete_instruction_file = function()
        delete_calls = delete_calls + 1
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store)

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }))
    assert_equal(delete_calls, 0, "instruction file should not be deleted when state write fails")
  end)
end

do
  with_filereadable(1, function()
    local state_data = workspace_state({
      review = review_workspace_record(),
    }, {
      updated_at = "before",
    })
    local write_count = 0
    local killed = false
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        write_count = write_count + 1
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return false, "delete instruction failed"
      end,
    })
    local runtime = workspace_delete_runtime(store.store)
    runtime.kill_tmux_window_deferred = function()
      killed = true
    end

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      window_id = "@1",
    }))
    assert_equal(write_count, 2, "failed instruction delete should restore prior state")
    assert_equal(state_data.projects["/repo"].workspaces.review.name, "review")
    assert_false(killed, "tmux window should not be killed when delete is rolled back")
  end)
end

do
  with_filereadable(1, function()
    local delete_calls = 0
    local killed = false
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record(),
      }),
      delete_instruction_file = function(_, root, safe_name)
        delete_calls = delete_calls + 1
        assert_equal(root, "/repo")
        assert_equal(safe_name, "review")
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store)
    runtime.kill_tmux_window_deferred = function(_, window_id)
      killed = window_id == "@1"
    end

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      window_id = "@1",
    }))
    assert_nil(store.state_data().projects["/repo"].workspaces.review)
    assert_equal(delete_calls, 1)
    assert_true(killed)
  end)
end

do
  with_filereadable(1, function()
    local deleted_instruction = false
    local removed_worktree = false
    local deleted_branch = false
    local closed = false
    local state_data = {
      projects = {
        ["/codux-worktrees/review"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/codux-worktrees/review",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function(_, root, safe_name)
        deleted_instruction = root == "/codux-worktrees/review" and safe_name == "review"
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      close_workspace_manager = function()
        closed = true
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/codux-worktrees/review",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_true(deleted_instruction)
    assert_true(removed_worktree)
    assert_true(deleted_branch)
    assert_true(closed)
    assert_nil(state_data.projects["/codux-worktrees/review"].workspaces.review)
  end)
end

do
  with_filereadable(1, function()
    local notification
    local rendered = false
    local closed = false
    local attempted_branch_delete = false
    local state_data = {
      projects = {
        ["/codux-worktrees/review"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/codux-worktrees/review",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      notify = function(message)
        notification = message
      end,
      render_workspace_manager = function()
        rendered = true
      end,
      close_workspace_manager = function()
        closed = true
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          return "fatal: worktree is locked\n", 1
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          attempted_branch_delete = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/codux-worktrees/review",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_contains(notification, "Failed to remove Git worktree /codux-worktrees/review")
    assert_contains(notification, "fatal: worktree is locked")
    assert_true(rendered)
    assert_false(closed)
    assert_false(attempted_branch_delete)
    assert_equal(state_data.projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
  end)
end

do
  with_filereadable(1, function()
    local notification
    local rendered = false
    local closed = false
    local removed_worktree = false
    local state_data = {
      projects = {
        ["/codux-worktrees/review"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/codux-worktrees/review",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      notify = function(message)
        notification = message
      end,
      render_workspace_manager = function()
        rendered = true
      end,
      close_workspace_manager = function()
        closed = true
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          return "fatal: branch delete failed\n", 1
        end
        return "", 1
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/codux-worktrees/review",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_true(removed_worktree)
    assert_contains(notification, "Failed to delete Git branch dev/review")
    assert_contains(notification, "fatal: branch delete failed")
    assert_true(rendered)
    assert_false(closed)
    assert_equal(state_data.projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
  end)
end

do
  with_filereadable(1, function()
    local deleted_branch = false
    local state_data = {
      projects = {
        ["/codux-worktrees/review"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/codux-worktrees/review",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/codux-worktrees/review",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_true(deleted_branch)
    assert_nil(state_data.projects["/codux-worktrees/review"].workspaces.review)
  end)
end

do
  with_filereadable(1, function()
    local delete_calls = 0
    local store = workspace_store({
      state_data = workspace_state({}),
      delete_instruction_file = function(_, root, safe_name)
        delete_calls = delete_calls + 1
        assert_equal(root, "/repo")
        assert_equal(safe_name, "review")
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store)

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }))
    assert_equal(delete_calls, 1)
  end)
end

do
  with_filereadable(1, function()
    local closed = false
    local store = workspace_store({
      state_data = workspace_state({}),
      delete_instruction_file = function()
        return false, "delete instruction failed"
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      close_workspace_manager = function()
        closed = true
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }))
    assert_false(closed, "instruction-only delete should fail when instruction file remains")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local created = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(error_message)
    assert_equal(workspace.project_root, "/codux-worktrees/review")
    assert_equal(workspace.workspace_kind, "worktree")
    assert_equal(workspace.worktree_branch, "dev/review")
    assert_equal(workspace.worktree_base, "main")
    assert_equal(workspace.worktree_base_commit, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    assert_equal(workspace.git_common_dir, "/repo/.git")
    assert_equal(workspace.target_path, "/codux-worktrees/review/file.lua")
    assert_contains(table.concat(commands, "\n"), "git -C /repo status --porcelain")
    assert_contains(table.concat(commands, "\n"), "git -C /repo worktree add -b dev/review /codux-worktrees/review main")
    assert_equal(store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
    assert_equal(
      store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_base_commit,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    )
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local created = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/mission-builder main" then
          return "", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\tmission-builder\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("mission-builder", {
      resolved_instruction = "builder instructions",
      initial_prompt = "start building",
      permission_profile = "auto",
      mission_id = "mission:mission",
      mission_name = "Mission",
      mission_role = "Builder",
      mission_objective = "Build it",
    })
    assert_nil(error_message)
    assert_equal(workspace.permission_profile, "auto")
    assert_equal(workspace.status, "active")
    assert_equal(workspace.codex_status, "working")
    assert_contains(table.concat(commands, "\n"), "start building")
    local record = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(record.permission_profile, "auto")
    assert_equal(record.mission_id, "mission:mission")
    assert_equal(record.mission_role, "Builder")
    assert_equal(record.mission_objective, "Build it")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local state_data = {
      projects = {
        ["/codux-worktrees/mission-builder"] = {
          workspaces = {
            ["mission-builder"] = review_workspace_record({
              name = "mission-builder",
              safe_name = "mission-builder",
              project_root = "/codux-worktrees/mission-builder",
              workspace_kind = "worktree",
            }),
          },
        },
      },
    }
    local runtime = workspace_prepare_runtime({
      store = workspace_store({
        state_data = state_data,
      }).store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        return "", 1
      end,
    })
    local mission = assert(mission_mod.plan("Mission", "Build it", {
      roles = {
        { name = "Builder" },
      },
    }))

    local ok, error_message = runtime:preflight_mission(mission)
    assert_false(ok)
    assert_equal(error_message, "workspace already exists: mission-builder")
    assert_equal(table.concat(commands, "\n"):find("worktree add", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local windows = {}
    local next_window_id = 1
    local store = workspace_store({
      instruction_file_path = function(_, root, safe_name)
        return root .. "/.agents/codux/" .. safe_name .. ".md"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          local lines = {}
          for name, id in pairs(windows) do
            table.insert(lines, id .. "\t" .. name)
          end
          table.sort(lines)
          return table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""), 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-architect" then
          return "", 1
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/mission-architect /codux-worktrees/mission-architect main" then
          return "", 0
        end
        if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/mission-builder main" then
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          local name = command:find("mission%-architect") and "mission-architect" or "mission-builder"
          windows[name] = "@" .. tostring(next_window_id)
          next_window_id = next_window_id + 1
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command == "tmux list-panes -t @2 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local mission, error_message = mission_mod.plan("Mission", "Build it", {
      roles = {
        { name = "Architect", safe_name = "architect", focus = "Design it" },
        { name = "Builder", safe_name = "builder", focus = "Build it" },
      },
    })
    assert_nil(error_message)
    assert_true(runtime:create_mission(mission))

    local architect =
      store.state_data().projects["/codux-worktrees/mission-architect"].workspaces["mission-architect"]
    local builder = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(architect.permission_profile, "auto")
    assert_equal(builder.permission_profile, "auto")
    assert_equal(architect.mission_id, "mission:mission")
    assert_equal(builder.mission_id, "mission:mission")
    assert_equal(architect.mission_role, "Architect")
    assert_equal(builder.mission_role, "Builder")
    assert_equal(architect.mission_objective, "Build it")
    assert_equal(builder.mission_objective, "Build it")
    assert_equal(architect.initial_mode, "plan")
    assert_equal(builder.initial_mode, "plan")
    assert_equal(architect.codex_mode, "plan")
    assert_equal(builder.codex_mode, "plan")
    assert_contains(table.concat(commands, "\n"), "git -C /repo status --porcelain")
    assert_contains(table.concat(commands, "\n"), "--listen")
    assert_contains(table.concat(commands, "\n"), "Start your Mission Control role now.")
  end)
end

do
  with_workspace_prepare_env(function()
    local runtime = workspace_prepare_runtime({})
    local lua = runtime:bootstrap_lua({
      name = "mission-builder",
      safe_name = "mission-builder",
      project_root = "/codux-worktrees/mission-builder",
      mission_id = "mission:mission",
      mission_name = "Mission",
      mission_role = "Builder",
      mission_objective = "Build it",
      nvim_server = "/tmp/codux/mission-builder.sock",
      initial_mode = "plan",
    })

    assert_contains(lua, 'mission_id="mission:mission"')
    assert_contains(lua, 'mission_name="Mission"')
    assert_contains(lua, 'mission_role="Builder"')
    assert_contains(lua, 'mission_objective="Build it"')
    assert_contains(lua, 'nvim_server="/tmp/codux/mission-builder.sock"')
    assert_contains(lua, 'initial_mode="plan"')
  end)
end

do
  with_workspace_prepare_env(function()
    local written = {}
    local notifications = {}
    local state_data = workspace_state({
      ["mission-architect"] = review_workspace_record({
        name = "mission-architect",
        safe_name = "mission-architect",
        mission_id = "mission:mission",
        mission_name = "Mission",
        mission_role = "Architect",
        mission_objective = "Build it",
        resolved_instruction = mission_mod.role_instruction("Mission", "Build it", {
          name = "Architect",
          safe_name = "architect",
          focus = "Design it",
        }),
      }),
      ["mission-builder"] = review_workspace_record({
        name = "mission-builder",
        safe_name = "mission-builder",
        mission_id = "mission:mission",
        mission_name = "Mission",
        mission_role = "Builder",
        mission_objective = "Build it",
        resolved_instruction = mission_mod.role_instruction("Mission", "Build it", {
          name = "Builder",
          safe_name = "builder",
          focus = "Build it",
        }),
      }),
    })
    local store = workspace_store({
      state_data = state_data,
      write_instruction_file = function(_, root, safe_name, instruction)
        written[root .. "/" .. safe_name] = instruction
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      notify = function(message)
        table.insert(notifications, message)
      end,
    })

    local ok, error_message = runtime:update_mission_objective("Mission", "Ship the dashboard")
    assert_nil(error_message)
    assert_true(ok)
    local architect = store.state_data().projects["/repo"].workspaces["mission-architect"]
    local builder = store.state_data().projects["/repo"].workspaces["mission-builder"]
    assert_equal(architect.mission_objective, "Ship the dashboard")
    assert_equal(builder.mission_objective, "Ship the dashboard")
    assert_contains(architect.resolved_instruction, "Ship the dashboard")
    assert_contains(builder.resolved_instruction, "Ship the dashboard")
    assert_contains(written["/repo/mission-architect"], "Mission: Mission")
    assert_contains(written["/repo/mission-builder"], "Role focus:")
    assert_contains(notifications[#notifications], "Updated Codux mission Mission objective for 2 roles")
  end)
end

do
  with_workspace_prepare_env(function()
    local runtime = workspace_prepare_runtime({
      store = workspace_store().store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:preflight_mission({
      roles = {
        { workspace_name = "mission-role!" },
        { workspace_name = "mission-role@" },
      },
    })
    assert_false(ok)
    assert_equal(error_message, "Duplicate mission workspace: mission-role")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local created = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
          return "", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1" then
          return "", 1
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1/review" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev1/review /codux-worktrees/review main" then
          return "", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(error_message)
    assert_equal(workspace.worktree_branch, "dev1/review")
    assert_contains(table.concat(commands, "\n"), "git -C /repo worktree add -b dev1/review /codux-worktrees/review main")
    assert_equal(store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev1/review")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      store = workspace_store().store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo status --porcelain" then
          return " M file.lua\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_equal(error_message, "current branch must be clean before creating a Codux workspace")
    assert_equal(table.concat(commands, "\n"):find("worktree add", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local wrote_instruction = false
    local store = workspace_store({
      read_instruction_file = function()
        return nil
      end,
      write_instruction_file = function()
        wrote_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          return "", 1
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_contains(error_message, "Failed to create tmux window")
    assert_false(wrote_instruction, "instruction file should not be written when tmux creation fails")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local killed = false
    local deleted_instruction = false
    local removed_worktree = false
    local deleted_branch = false
    local store = workspace_store({
      write_state = function()
        return false, "state write failed"
      end,
      read_instruction_file = function()
        return nil
      end,
      delete_instruction_file = function()
        deleted_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command == "tmux kill-window -t @1" then
          killed = true
          return "", 0
        end
        if command == "git -C /repo worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git -C /repo branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_equal(error_message, "state write failed")
    assert_true(killed, "new tmux window should be cleaned up when state write fails")
    assert_true(deleted_instruction, "new instruction file should be cleaned up when state write fails")
    assert_true(removed_worktree, "new git worktree should be cleaned up when state write fails")
    assert_true(deleted_branch, "new git branch should be cleaned up when state write fails")
  end)
end

do
  with_workspace_prepare_env(function()
    local created_window = false
    local wrote_instruction = false
    local wrote_state = false
    local store = workspace_store({
      write_state = function()
        wrote_state = true
        return true, nil
      end,
      read_instruction_file = function()
        return "existing instructions"
      end,
      write_instruction_file = function()
        wrote_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created_window = true
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "new instructions",
    })
    assert_nil(workspace)
    assert_equal(error_message, "workspace already exists")
    assert_false(created_window, "duplicate instruction-only workspace should not create tmux window")
    assert_false(wrote_instruction, "duplicate instruction-only workspace should not write instruction file")
    assert_false(wrote_state, "duplicate instruction-only workspace should not write state")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local store = workspace_store({
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
    })
    assert_nil(error_message)
    assert_equal(workspace.safe_name, "review")
    assert_equal(workspace.resolved_instruction, "existing instructions")
    assert_false(workspace.open_visible)
    assert_equal(store.state_data().projects["/repo"].workspaces.review.resolved_instruction, "existing instructions")
  end)
end

do
  with_workspace_prepare_env(function()
    local target_path, target_type = runtime_mod.normalize_workspace_target("/repo", "directory", "/fallback")
    assert_equal(target_path, "/repo")
    assert_equal(target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    assert_false(runtime_mod.target_path_exists("health://"))
    assert_false(runtime_mod.target_path_exists("codux://codex"))
    assert_false(runtime_mod.target_path_exists("term://terminal"))

    local target_path, target_type = runtime_mod.normalize_workspace_target("health://", "file", "/repo")
    assert_equal(target_path, "/repo")
    assert_equal(target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local runtime = workspace_prepare_runtime({
      current_target = function()
        return { path = "health://", type = "file" }
      end,
      current_buffer_name = function()
        return "health://"
      end,
      git_root_for = function(path)
        assert_equal(path, "/repo")
        return "/repo"
      end,
      git_branch_for = function(path)
        assert_equal(path, "/repo")
        return "main"
      end,
    })

    local context = runtime:target_context()
    assert_nil(context.path)
    assert_equal(context.directory, "/repo")
    assert_equal(context.root, "/repo")
    assert_equal(context.branch, "main")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local new_window_command
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record({
          resolved_instruction = "existing instructions",
          target_path = "/repo/neo-tree filesystem [1]",
          target_type = "file",
        }),
      }),
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          new_window_command = command
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
    })
    assert_nil(error_message)
    assert_equal(workspace.target_path, "/repo")
    assert_equal(workspace.target_type, "directory")
    assert_contains(new_window_command, "'nvim' --listen")
    assert_contains(new_window_command, "/codux/repo-review.sock' '.'")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_path, "/repo")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record({
          target_path = "/repo/file.lua",
          target_type = "file",
        }),
      }),
    })
    local runtime = workspace_prepare_runtime({
      state = {
        workspace = {
          project_root = "/repo",
          safe_name = "review",
          target_path = "/repo/file.lua",
          target_type = "file",
          git_branch = "main",
        },
      },
      store = store.store,
      current_target = function()
        return nil
      end,
      current_buffer_name = function()
        return "/repo/neo-tree filesystem [1]"
      end,
    })

    assert_true(runtime:sync_target("BufEnter", function()
      return "neo-tree"
    end))
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_path, "/repo")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_type, "directory")
    assert_equal(runtime.state.workspace.target_path, "/repo")
    assert_equal(runtime.state.workspace.target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local new_window_command
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record({
          resolved_instruction = "existing instructions",
          target_path = "/repo/file.lua",
          target_type = "file",
        }),
      }),
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          new_window_command = command
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
    })
    assert_nil(error_message)
    assert_equal(workspace.target_path, "/repo/file.lua")
    assert_equal(workspace.target_type, "file")
    assert_contains(new_window_command, "'nvim' --listen")
    assert_contains(new_window_command, "/codux/repo-review.sock' '/repo/file.lua'")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_path, "/repo/file.lua")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_type, "file")
  end)
end

print("workspace_status_spec.lua: ok")
