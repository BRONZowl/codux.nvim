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
    open_auto = "<leader>za",
    open_danger = "<leader>zA",
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
  assert_nil(by_desc["codex autopilot"])
  assert_nil(by_desc["codex danger zone"])
  assert_nil(by_lhs["<leader>zm"])
  assert_nil(by_lhs["<leader>za"])
  assert_nil(by_lhs["<leader>zA"])
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

  assert_equal(by_key.s, "start_mission")
  assert_equal(by_key.e, "edit_objective")
  assert_equal(by_key.v, "view_objective")
  assert_equal(by_key.x, "close_mission")
  assert_equal(by_key.d, "delete_mission")
  assert_nil(by_key.n)
  assert_nil(by_key.r)
  assert_contains(workspace_ui.mission_action_line(actions[1], 40), "Start Mission")
  assert_contains(workspace_ui.mission_action_line(actions[2], 40), "View Objective")
  assert_contains(workspace_ui.mission_action_line(actions[3], 40), "Edit Objective")
  assert_equal(labels_by_key.s, "Start Mission")
  assert_equal(labels_by_key.v, "View Objective")
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
