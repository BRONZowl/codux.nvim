local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true
local assert_contains = h.assert_contains

local mission_dashboard = require("codux.mission_dashboard")
local workspace_ui = require("codux.workspace_ui")

local controller = {
  workspace_ui = workspace_ui,
}

do
  local command_lines = mission_dashboard.command_lines(controller, 120)
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
  local columns = mission_dashboard.role_column_widths(120)
  local line = mission_dashboard.role_table_line(workspace_ui, columns, {
    role = "role",
    status = "status",
    mode = "mode",
    profile = "profile",
    age = "age",
    review = "review",
    branch = "branch",
    cleanup = "cleanup",
    target = "target",
  })

  assert_contains(line, "role")
  assert_contains(line, "profile")
  assert_contains(line, "cleanup")
  assert_contains(line, "target")
  assert_true(workspace_ui.display_width(line) <= 120)
end

print("mission_dashboard_spec.lua: ok")
