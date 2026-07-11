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
  local calls = {}
  local controller = mission_control_mod.new({
    ui = {
      create_scratch_buffer = function()
        error("dashboard buffer should not be created without missions")
      end,
    },
  })
  function controller:close_dashboard()
    table.insert(calls, "close_dashboard")
    return true
  end
  function controller:mission_count()
    return 0
  end
  function controller:dashboard_lines()
    error("dashboard lines should not be rendered without missions")
  end
  function controller:open_prompt()
    table.insert(calls, "open_prompt")
    return "prompt"
  end

  assert_equal(controller:open_dashboard("/repo"), "prompt")
  assert_equal(calls[1], "close_dashboard")
  assert_equal(calls[2], "open_prompt")
end

do
  local dashboard_created = false
  local controller = mission_control_mod.new({
    notify = function() end,
    ui = {
      create_scratch_buffer = function()
        dashboard_created = true
        return nil
      end,
    },
  })
  function controller:close_dashboard()
    return true
  end
  function controller:mission_count()
    return 1
  end
  function controller:dashboard_lines()
    return { "No Codux missions" }, {}, {}, nil, 0
  end
  function controller:open_prompt()
    error("mission prompt should not open when missions exist")
  end

  assert_false(controller:open_dashboard("/repo"))
  assert_true(dashboard_created)
end

do
  local dashboard_created = false
  local controller = mission_control_mod.new({
    notify = function() end,
    mission_residue_for_project = function(root)
      assert_equal(root, "/repo")
      return { count = 1, empty_project_buckets = { { path = "/codux-worktrees/debug-builder" } } }, nil
    end,
    ui = {
      create_scratch_buffer = function()
        dashboard_created = true
        return nil
      end,
    },
  })
  function controller:close_dashboard()
    return true
  end
  function controller:mission_count()
    return 0
  end
  function controller:dashboard_lines()
    return { "No Codux missions", "Stale Mission Control residue found" }, {}, {}, nil, 0
  end
  function controller:open_prompt()
    error("mission prompt should not open when cleanup residue exists")
  end

  assert_false(controller:open_dashboard("/repo"))
  assert_true(dashboard_created)
end

do
  local notifications = {}
  local controller = mission_control_mod.new({
    notify = function(message)
      table.insert(notifications, message)
    end,
    ui = {
      create_scratch_buffer = function()
        error("dashboard buffer should not be created when missions cannot be read")
      end,
    },
  })
  function controller:close_dashboard()
    return true
  end
  function controller:mission_count()
    return nil, "state failed"
  end
  function controller:dashboard_lines()
    error("dashboard lines should not be rendered when missions cannot be read")
  end
  function controller:open_prompt()
    error("mission prompt should not open when mission lookup fails")
  end

  assert_false(controller:open_dashboard("/repo"))
  assert_equal(notifications[#notifications], "state failed")
end

do
  local events = {}
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard = {
        buf = 77,
      }},
    is_loaded_buf = function(bufnr)
      table.insert(events, "loaded:" .. tostring(bufnr))
      return false
    end,
  })
  function controller:render_dashboard()
    table.insert(events, "render")
    return "rendered"
  end
  function controller:open_dashboard(root)
    table.insert(events, "open:" .. tostring(root))
    return "opened"
  end

  assert_false(controller:refresh_loaded_dashboard("/repo"))
  assert_equal(events[1], "loaded:77")
  assert_nil(events[2])

  assert_equal(controller:refresh_or_open_dashboard("/repo"), "opened")
  assert_equal(events[2], "loaded:77")
  assert_equal(events[3], "open:/repo")
end

print("mission_dashboard_windows_spec.lua: ok")
