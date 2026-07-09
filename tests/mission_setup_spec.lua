local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true
local assert_contains = h.assert_contains

local mission_setup = require("codux.mission_setup")
local ui_mod = require("codux.ui")

do
  local selected
  local notifications = {}
  local rendered = false
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    project_root = "/repo",
  }
  local controller = mission_setup.new({
    codux = {
      _v5 = {
        close_saved_workspace_window = function() end,
      },
    },
    workspace_runtime = {
      rename_mission_role = function() end,
      mission_dirty_roles = function()
        return {}
      end,
      workspace_branch_state = function()
        return {}
      end,
      reconcile_moved_worktrees_for_project = function()
        return true, nil
      end,
      missions_for_project = function()
        return {}
      end,
      mission_residue_for_project = function()
        return {}
      end,
      cleanup_mission_residue = function() end,
      workspace_interactive_preview = function() end,
      reconcile_moved_worktree = function(workspace)
        return workspace, nil, nil
      end,
      close_workspace_interactive_preview = function() end,
      send_prompt_to_workspace = function() end,
      select_workspace_question_option = function() end,
      submit_workspace_question_note = function() end,
      interrupt_workspace = function() end,
      switch_workspace_mode = function() end,
    },
    notify = function(message)
      table.insert(notifications, message)
    end,
    ui = {
      create_scratch_buffer = function() end,
      set_lines = function() end,
      set_window_options = function() end,
      close_window = function() end,
      delete_buffer = function() end,
    },
    switch_workspace_profile = function(workspace, agent_provider, permission_profile, opts)
      selected = {
        workspace = workspace,
        agent_provider = agent_provider,
        permission_profile = permission_profile,
        restart = opts and opts.restart,
      }
      return true, nil, true
    end,
  })
  function controller:render_dashboard()
    rendered = true
    return true
  end

  h.with_stubs({
    {
      target = ui_mod,
      key = "key_choice_menu",
      value = function(opts, callback)
        assert_equal(opts.filetype, "codux-mission-workspace-profile")
        return callback(opts.choices[5])
      end,
    },
  }, function()
    assert_true(controller:switch_selected_workspace_profile(entry))
  end)

  assert_equal(selected.workspace.safe_name, "alpha-builder")
  assert_equal(selected.agent_provider, "grok")
  assert_equal(selected.permission_profile, "auto")
  assert_true(selected.restart)
  assert_true(rendered)
  assert_contains(notifications[#notifications], "Grok Auto")
end

print("mission_setup_spec.lua: ok")
