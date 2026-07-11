local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local orchestrate = require("codux.mission_orchestrate")
local mission_mod = require("codux.mission")

local function memory_fs()
  local files = {}
  local dirs = {}
  local function dirname(path)
    return path:match("^(.*)/[^/]+$") or ""
  end
  local fs = {}
  function fs.isdirectory(path)
    return dirs[path] == true
  end
  function fs.mkdir(path)
    dirs[path] = true
    local parent = dirname(path)
    if parent ~= "" and not dirs[parent] then
      fs.mkdir(parent)
    end
    return true
  end
  function fs.readdir(path)
    local names = {}
    local prefix = path:gsub("/+$", "") .. "/"
    for full, _ in pairs(files) do
      if full:sub(1, #prefix) == prefix then
        local rest = full:sub(#prefix + 1)
        if not rest:find("/") then
          table.insert(names, rest)
        end
      end
    end
    table.sort(names)
    return names
  end
  function fs.readfile(path)
    return files[path]
  end
  function fs.writefile(path, content)
    local parent = dirname(path)
    if parent ~= "" then
      fs.mkdir(parent)
    end
    files[path] = tostring(content or "")
    return true
  end
  function fs.rename(from_path, to_path)
    if files[from_path] == nil then
      return false
    end
    local parent = dirname(to_path)
    if parent ~= "" then
      fs.mkdir(parent)
    end
    files[to_path] = files[from_path]
    files[from_path] = nil
    return true
  end
  function fs.filereadable(path)
    return files[path] ~= nil
  end
  fs._files = files
  fs._dirs = dirs
  return fs
end

do
  local dirs = orchestrate.dispatch_dirs("/repo", "alpha", ".agents/codux")
  assert_equal(dirs.pending, "/repo/.agents/codux/missions/alpha/dispatch/pending")
  assert_equal(dirs.done, "/repo/.agents/codux/missions/alpha/dispatch/done")
  assert_equal(dirs.failed, "/repo/.agents/codux/missions/alpha/dispatch/failed")
end

do
  local mission = {
    roles = {
      { mission_role = "Manager", safe_name = "alpha-manager", status = "idle" },
      { mission_role = "Agent", safe_name = "alpha-agent", status = "inactive" },
      { mission_role = "Builder", name = "Builder", safe_name = "alpha-builder", status = "inactive" },
    },
  }
  assert_equal(orchestrate.find_role(mission, "Agent").safe_name, "alpha-agent")
  assert_equal(orchestrate.find_role(mission, "builder").safe_name, "alpha-builder")
  assert_equal(orchestrate.find_role(mission, "alpha-manager").mission_role, "Manager")
  assert_nil(orchestrate.find_role(mission, "Reviewer"))
end

do
  local action, err = orchestrate.validate_action({
    op = "start_and_prompt",
    role = "Agent",
    prompt = "Do the thing",
  })
  assert_nil(err)
  assert_equal(action.op, "start_and_prompt")
  assert_equal(action.role, "Agent")
  assert_equal(action.prompt, "Do the thing")

  local bad, bad_err = orchestrate.validate_action({ op = "explode", role = "Agent" })
  assert_nil(bad)
  assert_contains(bad_err, "unsupported op")

  local missing, missing_err = orchestrate.validate_action({ op = "prompt", role = "Agent" })
  assert_nil(missing)
  assert_contains(missing_err, "requires prompt")
end

do
  local doc, err = orchestrate.parse_dispatch_document([[
{
  "version": 1,
  "source": "manager",
  "actions": [
    { "op": "start", "role": "Agent" },
    { "op": "start_and_prompt", "role": "Builder", "prompt": "Ship it" }
  ]
}
]])
  assert_nil(err)
  assert_equal(#doc.actions, 2)
  assert_equal(doc.actions[2].prompt, "Ship it")
end

do
  local started = {}
  local prompted = {}
  local mission = {
    name = "Alpha",
    mission_id = "mission:alpha",
    safe_name = "alpha",
    roles = {
      { mission_role = "Agent", safe_name = "alpha-agent", status = "inactive" },
    },
  }
  local ok, err = orchestrate.apply_action({
    start_workspace = function(entry)
      table.insert(started, entry.safe_name)
      entry.status = "idle"
      return true
    end,
    send_prompt = function(entry, prompt)
      table.insert(prompted, { entry.safe_name, prompt })
      return true
    end,
  }, mission, {
    op = "start_and_prompt",
    role = "Agent",
    prompt = "Implement X",
  })
  assert_true(ok)
  assert_nil(err)
  assert_equal(started[1], "alpha-agent")
  assert_equal(prompted[1][1], "alpha-agent")
  assert_equal(prompted[1][2], "Implement X")
end

do
  local ok, err = orchestrate.apply_action({
    start_workspace = function()
      return true
    end,
    send_prompt = function()
      return true
    end,
  }, { roles = {} }, {
    op = "start_and_prompt",
    role = "Missing",
    prompt = "x",
  })
  assert_false(ok)
  assert_contains(err, "role not found")
end

do
  local created = {}
  local ok = orchestrate.apply_action({
    create_role = function(mission, role_name, opts)
      table.insert(created, { role_name, opts.focus })
      return true
    end,
  }, {
    name = "Alpha",
    roles = { { mission_role = "Manager", safe_name = "alpha-manager" } },
  }, {
    op = "create_role",
    role = "Builder",
    focus = "Build it",
  })
  assert_true(ok)
  assert_equal(created[1][1], "Builder")
  assert_equal(created[1][2], "Build it")
end

do
  local focus_updates = {}
  local ok = orchestrate.apply_action({
    update_focus = function(mission, packet)
      table.insert(focus_updates, packet)
      return true
    end,
  }, { name = "Alpha", roles = {} }, {
    op = "update_focus",
    focus_packet = "# Focus\nNext action",
  })
  assert_true(ok)
  assert_equal(focus_updates[1], "# Focus\nNext action")
end

do
  local fs = memory_fs()
  local mission = {
    name = "Alpha",
    mission_id = "mission:alpha",
    safe_name = "alpha",
    roles = {
      { mission_role = "Agent", safe_name = "alpha-agent", status = "inactive" },
    },
  }
  local pending = "/repo/.agents/codux/missions/alpha/dispatch/pending/task.json"
  fs.writefile(
    pending,
    [[{
  "version": 1,
  "actions": [
    { "op": "start_and_prompt", "role": "Agent", "prompt": "Do work" }
  ]
}]]
  )

  local started = 0
  local prompted = 0
  local summary = orchestrate.process_pending_for_mission({
    start_workspace = function(entry)
      started = started + 1
      entry.status = "idle"
      return true
    end,
    send_prompt = function()
      prompted = prompted + 1
      return true
    end,
  }, "/repo", mission, { fs = fs })

  assert_equal(summary.processed, 1)
  assert_equal(summary.succeeded, 1)
  assert_equal(summary.failed, 0)
  assert_equal(started, 1)
  assert_equal(prompted, 1)
  assert_nil(fs.readfile(pending))
  assert_true(fs.readfile("/repo/.agents/codux/missions/alpha/dispatch/done/task.json") ~= nil)
end

do
  local fs = memory_fs()
  local mission = {
    name = "Alpha",
    mission_id = "mission:alpha",
    safe_name = "alpha",
    roles = {
      { mission_role = "Agent", safe_name = "alpha-agent", status = "inactive" },
    },
  }
  fs.writefile(
    "/repo/.agents/codux/missions/alpha/dispatch/pending/bad.json",
    [[{ "actions": [ { "op": "nope", "role": "Agent" } ] }]]
  )
  local summary = orchestrate.process_pending_for_mission({
    start_workspace = function()
      return true
    end,
  }, "/repo", mission, { fs = fs })
  assert_equal(summary.failed, 1)
  assert_true(fs.readfile("/repo/.agents/codux/missions/alpha/dispatch/failed/bad.json") ~= nil)
end

do
  local planned = assert(mission_mod.plan("Dispatch", "Coordinate workers", {
    project_root = "/repo",
  }))
  local manager = mission_mod.find_manager_role(planned)
  assert_true(manager ~= nil)
  assert_contains(manager.instruction, "dispatch/pending")
  assert_contains(manager.instruction, "start_and_prompt")
  assert_contains(manager.instruction, "Worker dispatch protocol")
end

do
  local help = orchestrate.manager_dispatch_help("/repo", "alpha")
  assert_contains(help, "/repo/.agents/codux/missions/alpha/dispatch/pending")
  assert_contains(help, "create_role")
end

print("mission_orchestrate_spec.lua: ok")
