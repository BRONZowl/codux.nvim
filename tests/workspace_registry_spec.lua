local h = require("tests.helpers")
local fixtures = require("tests.workspace_fixtures")
local assert_equal = h.assert_equal
local assert_true = h.assert_true

local workspace_registry = require("codux.workspace_registry")
local runtime_mod = require("codux.workspace_runtime")

local function runtime(opts)
  opts = type(opts) == "table" and opts or {}
  local state_data = opts.state_data or { projects = {} }
  local written = 0
  return {
    state = opts.state or {},
    sanitize_workspace_name = runtime_mod.sanitize_workspace_name,
    workspace_window_name = runtime_mod.workspace_window_name,
    tmux_target = runtime_mod.tmux_target,
    read_state = function()
      return state_data, opts.read_error
    end,
    write_state = function(_, next_state)
      written = written + 1
      state_data = next_state
      return opts.write_ok ~= false, opts.write_error
    end,
    project_state = function(_, next_state, root)
      return fixtures.simple_project_state(next_state, root)
    end,
    timestamp = function()
      return "2026-07-05T12:00:00Z"
    end,
    git_common_dir = function()
      return opts.git_common_dir
    end,
    current_tmux_session = function()
      return opts.session
    end,
    tmux_window_id = function(_, _, window_name)
      return opts.window_ids and opts.window_ids[window_name] or nil
    end,
    dashboard_workspace_status = function(_, record, window_id)
      if window_id then
        return record.codex_status == "question" and "question" or "idle"
      end
      return "inactive"
    end,
    normalize_codex_mode = function(_, mode)
      return mode == "execute" and "execute" or mode == "plan" and "plan" or nil
    end,
    workspace_server_path = function(_, root, safe_name)
      return "/run/" .. tostring(root):gsub("[/%s]+", "-") .. "-" .. tostring(safe_name) .. ".sock"
    end,
    instruction_file_records = function()
      return opts.instruction_records or {}
    end,
    write_instruction_file = function(_, root, safe_name, instruction)
      opts.written_instructions = opts.written_instructions or {}
      opts.written_instructions[root .. "\0" .. safe_name] = instruction
      return true, nil
    end,
    tmux_cmd = function()
      return "tmux"
    end,
    render_workspace_manager = function()
      opts.rendered = true
    end,
    notify = function(message)
      opts.notification = message
    end,
    written_count = function()
      return written
    end,
    state_data = function()
      return state_data
    end,
    entries_for_project = function(self, root)
      return workspace_registry.entries_for_project(self, root)
    end,
    missions_for_project = function(self, root)
      return workspace_registry.missions_for_project(self, root)
    end,
    mission_for_name = function(self, root, name)
      return workspace_registry.mission_for_name(self, root, name)
    end,
  }
end

do
  local rt = runtime({
    session = "session",
    window_ids = { review = "@1" },
    state_data = {
      projects = {
        ["/repo"] = {
          workspaces = {
            review = {
              name = "Review",
              safe_name = "review",
              project_root = "/repo",
              codex_mode = "plan",
              permission_profile = "auto",
              tmux_window = "review",
            },
          },
        },
      },
    },
    instruction_records = {
      draft = {
        name = "Draft",
        safe_name = "draft",
        instruction_file = "/repo/.agents/codux/draft.md",
      },
    },
  })

  local entries = workspace_registry.entries_for_project(rt, "/repo")
  assert_equal(#entries, 2)
  assert_equal(entries[1].name, "Draft")
  assert_true(entries[1].instruction_file_only)
  assert_equal(entries[2].name, "Review")
  assert_equal(entries[2].status, "idle")
  assert_equal(entries[2].codex_mode, "plan")
  assert_equal(entries[2].tmux_target, "session:review")
end

do
  local rt = runtime({
    git_common_dir = "/repo/.git",
    state_data = {
      projects = {
        ["/repo"] = {
          workspaces = {
            local_role = fixtures.project_owned_worktree_record({
              name = "Local Role",
              safe_name = "local_role",
            }),
          },
        },
        ["/other"] = {
          workspaces = {
            explicit_other = {
              name = "Explicit Other",
              safe_name = "explicit_other",
              project_root = "/other",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
            },
            legacy_shared = {
              name = "Legacy Shared",
              safe_name = "legacy_shared",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
            },
          },
        },
        ["/codux-worktrees/alpha-builder"] = {
          workspaces = {
            ["alpha-builder"] = {
              name = "alpha-builder",
              safe_name = "alpha-builder",
              project_root = "/codux-worktrees/alpha-builder",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              mission_id = "mission:alpha",
              mission_name = "Alpha",
              mission_role = "Builder",
              mission_objective = "Build it",
              mission_focus_packet = "Focus Alpha",
            },
          },
        },
      },
    },
  })

  local entries = workspace_registry.entries_for_project(rt, "/repo")
  assert_equal(#entries, 2)
  assert_equal(entries[1].name, "Legacy Shared")
  assert_equal(entries[2].name, "Local Role")

  local missions = workspace_registry.missions_for_project(rt, "/repo")
  assert_equal(#missions, 1)
  assert_equal(missions[1].name, "Alpha")
  assert_equal(missions[1].focus_packet, "Focus Alpha")
  assert_equal(missions[1].roles[1].project_root, "/codux-worktrees/alpha-builder")
  assert_equal(missions[1].roles[1].mission_role, "Builder")
end

do
  local opts = {
    state = { workspace_manager_project_root = "/repo" },
    state_data = {
      projects = {
        ["/repo"] = {
          workspaces = {
            builder = {
              name = "mission-builder",
              safe_name = "builder",
              project_root = "/repo",
              mission_id = "mission:alpha",
              mission_name = "Alpha",
              mission_role = "Builder",
              mission_objective = "Old",
            },
          },
        },
      },
    },
  }
  local rt = runtime(opts)
  local ok, err = workspace_registry.update_mission_objective(rt, "Alpha", "New", { project_root = "/repo" })
  assert_equal(ok, true)
  assert_equal(err, nil)
  assert_equal(rt:written_count(), 1)
  assert_equal(rt:state_data().projects["/repo"].workspaces.builder.mission_objective, "New")
  assert_true(opts.written_instructions["/repo\0builder"]:find("New", 1, true) ~= nil)
  assert_true(opts.rendered)
  assert_true(opts.notification:find("Updated Codux mission Alpha objective", 1, true) ~= nil)
end

do
  local opts = {
    state = {
      workspace_manager_project_root = "/repo",
      workspace = {
        project_root = "/repo",
        safe_name = "builder",
      },
    },
    state_data = {
      projects = {
        ["/repo"] = {
          workspaces = {
            builder = {
              name = "mission-builder",
              safe_name = "builder",
              project_root = "/repo",
              mission_id = "mission:alpha",
              mission_name = "Alpha",
              mission_role = "Builder",
              mission_objective = "Build it",
              mission_focus_packet = "Old focus",
            },
          },
        },
      },
    },
  }
  local rt = runtime(opts)
  local ok, err = workspace_registry.update_mission_focus_packet(rt, "Alpha", "New focus", { project_root = "/repo" })
  assert_equal(ok, true)
  assert_equal(err, nil)
  assert_equal(rt:written_count(), 1)
  assert_equal(rt:state_data().projects["/repo"].workspaces.builder.mission_focus_packet, "New focus")
  assert_equal(opts.state.workspace.mission_focus_packet, "New focus")
  assert_true(opts.rendered)
  assert_true(opts.notification:find("Updated Codux mission Alpha focus", 1, true) ~= nil)
end

print("workspace_registry_spec.lua: ok")
