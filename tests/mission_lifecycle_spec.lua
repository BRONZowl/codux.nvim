local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_true = h.assert_true

local mission_lifecycle = require("codux.mission_lifecycle")

local function runtime(opts)
  opts = type(opts) == "table" and opts or {}
  local notifications = {}
  local deleted = {}
  local mission = opts.mission
    or {
      name = "Alpha",
      roles = {
        { name = "Builder", safe_name = "builder", project_root = "/repo-builder" },
        { name = "Reviewer", safe_name = "reviewer", project_root = "/repo-reviewer" },
      },
    }
  return {
    state = opts.state or {},
    project_root = function()
      return "/repo"
    end,
    mission_for_name = function()
      return mission, nil
    end,
    system = opts.system or function(args)
      local path = args[3]
      if path == "/repo-builder" then
        return " M file.lua\n", 0
      end
      return "", 0
    end,
    delete_saved_workspace = function(_, entry)
      table.insert(deleted, entry.safe_name)
      return opts.delete_ok ~= false, nil
    end,
    notify = function(message)
      table.insert(notifications, message)
    end,
    notifications = function()
      return notifications
    end,
    deleted = function()
      return deleted
    end,
  }
end

do
  local rt = runtime()
  local dirty, err = mission_lifecycle.dirty_roles(rt, "Alpha")
  assert_equal(err, nil)
  assert_equal(#dirty, 1)
  assert_equal(dirty[1].name, "Builder")
  assert_equal(dirty[1].reason, "dirty")
end

do
  local rt = runtime({ delete_ok = true })
  assert_true(mission_lifecycle.delete(rt, "Alpha"))
  assert_equal(rt:deleted()[1], "builder")
  assert_equal(rt:deleted()[2], "reviewer")
  assert_equal(rt:notifications()[1], "Deleted Codux mission Alpha with 2 roles")
end

do
  local rt = runtime({ delete_ok = false })
  assert_false(mission_lifecycle.delete(rt, "Alpha"))
  assert_equal(rt:deleted()[1], "builder")
  assert_equal(rt:notifications()[1], "Stopped deleting Codux mission Alpha after 0 roles")
end

print("mission_lifecycle_spec.lua: ok")
