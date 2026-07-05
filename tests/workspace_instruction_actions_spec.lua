local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true

local workspace_instruction_actions = require("codux.workspace_instruction_actions")

local function project_state(state_data, root)
  state_data.projects = state_data.projects or {}
  state_data.projects[root] = state_data.projects[root] or { workspaces = {} }
  state_data.projects[root].workspaces = state_data.projects[root].workspaces or {}
  return state_data.projects[root]
end

local function runtime(opts)
  opts = type(opts) == "table" and opts or {}
  local state_data = opts.state_data or {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "Review",
            safe_name = "review",
            project_root = "/repo",
            resolved_instruction = "Saved instruction",
          },
        },
      },
    },
  }
  local writes = 0
  local rendered = false
  return {
    state = opts.state or { workspace_manager_project_root = "/repo" },
    read_state = function()
      return state_data, opts.read_error
    end,
    write_state = function(_, next_state)
      writes = writes + 1
      state_data = next_state
      return opts.write_ok ~= false, opts.write_error
    end,
    project_state = function(_, next_state, root)
      return project_state(next_state, root)
    end,
    timestamp = function()
      return "2026-07-05T12:00:00Z"
    end,
    read_instruction_file = function()
      return opts.instruction
    end,
    write_instruction_file = function(_, root, safe_name, instruction)
      opts.written_instruction = { root = root, safe_name = safe_name, instruction = instruction }
      return opts.write_instruction_ok ~= false, opts.write_instruction_error
    end,
    render_workspace_manager = function()
      rendered = true
    end,
    state_data = function()
      return state_data
    end,
    writes = function()
      return writes
    end,
    rendered = function()
      return rendered
    end,
  }
end

do
  local rt = runtime()
  local request, err = workspace_instruction_actions.saved_workspace_instruction_request(rt, {
    project_root = "/repo",
    safe_name = "review",
  })

  assert_equal(err, nil)
  assert_equal(request.name, "review")
  assert_equal(request.resolved_instruction, "Saved instruction")
end

do
  local rt = runtime()
  local ok, err = workspace_instruction_actions.update_saved_workspace_instruction(rt, {
    project_root = "/repo",
    safe_name = "review",
  }, "New instruction")

  assert_true(ok)
  assert_equal(err, nil)
  assert_equal(rt:state_data().projects["/repo"].workspaces.review.resolved_instruction, "New instruction")
  assert_equal(rt:writes(), 1)
  assert_true(rt:rendered())
end

print("workspace_instruction_actions_spec.lua: ok")
