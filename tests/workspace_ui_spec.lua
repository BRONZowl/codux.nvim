local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local workspace_ui = require("codux.workspace_ui")
local which_key_mod = require("codux.which_key")

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
  assert_equal(workspace_ui.manager_mode_label({ status = "inactive", agent_mode = "plan" }), "--")
  assert_equal(workspace_ui.manager_mode_label({ status = "idle", agent_mode = "plan" }), "plan")
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
  assert_equal(by_key.s, "start_workspace")
  assert_equal(by_key.p, "switch_profile")
  assert_equal(by_key.r, "rename")
  assert_equal(by_key.e, "edit_instructions")
  assert_equal(by_key.x, "close_window")
  assert_equal(by_key.X, "close_all_windows")
  assert_equal(by_key.d, "delete")
  assert_nil(by_key.h)
  assert_contains(workspace_ui.manager_action_line(actions[1], 40), "Start Workspace")
  assert_equal(labels_by_key.s, "Start Workspace")
  assert_equal(labels_by_key.X, "Close All Workspaces")
end

do
  local controller = which_key_mod.new({
    get_mode = function()
      return "execute"
    end,
    token_usage_label = function()
      return "usage | 5hr 12% | wk 34%"
    end,
  })
  local entries = controller:normal_entries({
    open = "<leader>zc",
    default_provider = "<leader>zP",
    open_auto = "<leader>za",
    open_danger = "<leader>zA",
    workspace = "<leader>zw",
    workspaces = "<leader>zW",
    missions = "<leader>zM",
    mode = "<leader>zp",
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
  assert_nil(by_desc["codex autopilot"])
  assert_nil(by_desc["codex danger zone"])
  assert_nil(by_desc["switch to plan mode"])
  assert_nil(by_desc["switch to execute mode"])
  assert_nil(by_lhs["<leader>zm"])
  assert_nil(by_lhs["<leader>za"])
  assert_nil(by_lhs["<leader>zA"])
  assert_nil(by_lhs["<leader>zw"])
  assert_nil(by_lhs["<leader>zW"])
  assert_nil(by_lhs["<leader>zp"])
  assert_equal(by_lhs["<leader>zM"], "mission control")
  assert_equal(by_lhs["<leader>zP"], "set default provider")

  local title = controller:title()
  assert_equal(title[1][1], " codux ")
  assert_contains(title[2][1], "5hr 12%")
  assert_equal(table.concat({ title[1][1], title[2][1] }):find("exec", 1, true), nil)
  assert_equal(table.concat({ title[1][1], title[2][1] }):find("plan", 1, true), nil)

  local header = controller:mode_status_header_lines()
  assert_equal(header[1], "codux")
  assert_equal(header[2], "usage | 5hr 12% | wk 34%")
end

do
  local actions = workspace_ui.mission_action_items()
  local by_key = {}
  local labels_by_key = {}
  for _, action in ipairs(actions) do
    by_key[action.key] = action.action
    labels_by_key[action.key] = action.label
  end

  assert_equal(by_key.s, "start_mission")
  assert_equal(by_key.p, "process_dispatch")
  assert_equal(by_key.e, "edit_objective")
  assert_equal(by_key.f, "edit_focus")
  assert_equal(by_key.x, "close_mission")
  assert_equal(by_key.d, "delete_mission")
  assert_nil(by_key.g)
  assert_nil(by_key.a)
  assert_nil(by_key.v)
  assert_nil(by_key.n)
  assert_nil(by_key.r)
  assert_contains(workspace_ui.mission_action_line(actions[1], 40), "Start Mission")
  assert_equal(labels_by_key.s, "Start Mission")
  assert_equal(labels_by_key.p, "Process Dispatch")
  assert_equal(labels_by_key.x, "Close Mission")
  assert_nil(labels_by_key.g)
  assert_nil(labels_by_key.n)
end

do
  local function action_signature(actions)
    local parts = {}
    for _, action in ipairs(actions) do
      table.insert(parts, tostring(action.key) .. ":" .. tostring(action.action) .. ":" .. tostring(action.label))
    end
    return table.concat(parts, "|")
  end

  local actions = workspace_ui.role_workspace_action_items({ status = "inactive", mission_role = "Agent" })
  local by_key = {}
  local labels_by_key = {}
  for _, action in ipairs(actions) do
    by_key[action.key] = action.action
    labels_by_key[action.key] = action.label
  end

  assert_nil(by_key.o)
  assert_equal(by_key.s, "start_workspace")
  assert_equal(by_key.r, "rename_role")
  assert_equal(by_key.e, "edit_instructions")
  assert_equal(by_key.x, "close_workspace")
  assert_equal(by_key.d, "delete_workspace")
  assert_equal(by_key.w, "create_workspace")
  assert_equal(by_key.p, "switch_profile")
  assert_nil(by_key.t)
  assert_nil(by_key.i)
  assert_nil(by_key.a)
  assert_nil(by_key.X)
  assert_contains(workspace_ui.role_workspace_action_line(actions[1], 40), "Start Workspace")
  assert_equal(labels_by_key.s, "Start Workspace")
  assert_equal(labels_by_key.p, "Switch Profile")
  assert_nil(labels_by_key.t)
  assert_nil(labels_by_key.i)
  assert_nil(labels_by_key.a)
  assert_nil(labels_by_key.o)
  assert_equal(labels_by_key.r, "Rename Role")
  assert_equal(labels_by_key.d, "Delete Workspace")
  assert_equal(labels_by_key.w, "Create Workspace")
  local inactive_signature = action_signature(actions)
  for _, status in ipairs({ "active", "idle", "question" }) do
    local status_actions = workspace_ui.role_workspace_action_items({ status = status, mission_role = "Agent" })
    local by_key = {}
    local labels_by_key = {}
    for _, action in ipairs(status_actions) do
      by_key[action.key] = action.action
      labels_by_key[action.key] = action.label
    end

    assert_equal(action_signature(status_actions), inactive_signature)
    assert_nil(by_key.a)
    assert_nil(labels_by_key.a)
    assert_equal(by_key.s, "start_workspace")
    assert_equal(by_key.r, "rename_role")
    assert_equal(by_key.e, "edit_instructions")
    assert_contains(workspace_ui.role_workspace_action_line(status_actions[1], 40), "Start Workspace")
  end

  local manager_actions = workspace_ui.role_workspace_action_items({
    status = "inactive",
    mission_role = "Manager",
    safe_name = "manager",
  })
  local manager_by_key = {}
  local manager_labels = {}
  for _, action in ipairs(manager_actions) do
    manager_by_key[action.key] = action.action
    manager_labels[action.key] = action.label
  end
  assert_equal(manager_by_key.s, "start_workspace")
  assert_equal(manager_labels.s, "Start Manager")
  assert_equal(manager_by_key.p, "switch_profile")
  assert_equal(manager_by_key.e, "edit_instructions")
  assert_equal(manager_by_key.x, "close_workspace")
  assert_equal(manager_labels.x, "Close Manager")
  assert_equal(manager_by_key.w, "create_workspace")
  assert_nil(manager_by_key.r)
  assert_nil(manager_by_key.d)
  assert_contains(workspace_ui.role_workspace_action_line(manager_actions[1], 40), "Start Manager")
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

print("workspace_ui_spec.lua: ok")
