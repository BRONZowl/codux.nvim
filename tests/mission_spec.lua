local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local mission_mod = require("codux.mission")

do
  local mission, error_message = mission_mod.plan("Blow Socks Off", "Build a standout agentic engineering feature.")
  assert_nil(error_message)
  assert_equal(mission.name, "Blow Socks Off")
  assert_equal(mission.safe_name, "blow-socks-off")
  assert_equal(mission.mission_id, "mission:blow-socks-off")
  assert_equal(#mission.roles, 2)
  assert_equal(mission.roles[1].workspace_name, "blow-socks-off-builder")
  assert_equal(mission.roles[2].workspace_name, "blow-socks-off-reviewer")
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

print("mission_spec.lua: ok")
