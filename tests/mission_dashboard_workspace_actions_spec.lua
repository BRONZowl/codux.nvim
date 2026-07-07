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
local notifications_fixture = fixtures.notifications

do
  local sent_prompt
  local notifications, notify = notifications_fixture()
  local entry = { name = "alpha-builder", safe_name = "alpha-builder", mission_role = "Builder", status = "idle" }
  local controller = mission_control_mod.new({
    notify = notify,
    ui = {
      single_line_prompt = function(opts, callback)
        assert_contains(opts.prompt, "Builder")
        callback("  /plan  ")
        return true
      end,
    },
    send_prompt_to_workspace = function(workspace, prompt)
      assert_equal(workspace.safe_name, "alpha-builder")
      sent_prompt = prompt
      return true, nil
    end,
  })

  assert_true(controller:open_workspace_prompt(entry))
  assert_equal(sent_prompt, "  /plan  ")
  assert_contains(notifications[#notifications], "Sent prompt to Builder")
end

do
  local sent_prompt
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    mission_focus_packet = "Focus on dashboard UX",
  }
  local controller = mission_control_mod.new({
    ui = {
      single_line_prompt = function(_, callback)
        callback("make it clearer")
        return true
      end,
    },
    send_prompt_to_workspace = function(_, prompt)
      sent_prompt = prompt
      return true, nil
    end,
  })

  assert_true(controller:open_workspace_prompt(entry))
  assert_contains(sent_prompt, "Mission Focus Packet:\nFocus on dashboard UX")
  assert_contains(sent_prompt, "User Request:\nmake it clearer")
end

do
  local old_key_choice_menu = ui_mod.key_choice_menu
  local selected
  local notifications, notify = notifications_fixture()
  local entry = { name = "alpha-builder", safe_name = "alpha-builder", mission_role = "Builder", status = "question" }
  ui_mod.key_choice_menu = function(opts, callback)
    assert_contains(opts.title, "Builder")
    assert_equal(opts.choices[1].key, "o")
    assert_equal(opts.choices[2].key, "n")
    callback({ action = "option" })
    return true
  end
  local controller = mission_control_mod.new({
    notify = notify,
    ui = {
      single_line_prompt = function(opts, callback)
        assert_contains(opts.prompt, "Plan option Builder")
        callback(" 2 ")
        return true
      end,
    },
    select_workspace_question_option = function(workspace, option, opts)
      selected = { workspace = workspace, option = option, with_note = type(opts) == "table" and opts.with_note }
      return true, nil
    end,
  })
  function controller:render_dashboard()
    return true
  end

  assert_true(controller:open_workspace_question_answer(entry))
  assert_equal(selected.workspace.safe_name, "alpha-builder")
  assert_equal(selected.option, "2")
  assert_false(selected.with_note)
  assert_contains(notifications[#notifications], "Answered question for Builder")
  ui_mod.key_choice_menu = old_key_choice_menu
end

do
  local old_key_choice_menu = ui_mod.key_choice_menu
  local prompt_opts = {}
  local calls = {}
  local entry = { name = "alpha-builder", safe_name = "alpha-builder", mission_role = "Builder", codex_status = "question" }
  ui_mod.key_choice_menu = function(_, callback)
    callback({ action = "option_note" })
    return true
  end
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_command_win = 30,
    },
    notify = function(message)
      table.insert(calls, "notify:" .. tostring(message))
    end,
    is_valid_win = function(win)
      return win == 10 or win == 30
    end,
    set_current_win = function(win)
      table.insert(calls, "focus:" .. tostring(win))
      return true
    end,
    ui = {
      single_line_prompt = function(opts, callback)
        table.insert(prompt_opts, opts)
        if #prompt_opts == 1 then
          callback("3")
        else
          callback("ship this plan")
        end
        return true
      end,
    },
    select_workspace_question_option = function(workspace, option, opts)
      table.insert(calls, "select:" .. tostring(workspace.safe_name) .. ":" .. option .. ":" .. tostring(opts.with_note))
      return true, nil
    end,
    submit_workspace_question_note = function(workspace, note)
      table.insert(calls, "note:" .. tostring(workspace.safe_name) .. ":" .. note)
      return true, nil
    end,
  })
  function controller:render_dashboard()
    table.insert(calls, "render")
    return true
  end

  assert_true(controller:open_workspace_question_answer(entry))
  assert_contains(prompt_opts[1].prompt, "Plan option Builder")
  assert_nil(prompt_opts[1].insert_input)
  assert_contains(prompt_opts[2].prompt, "Note Builder")
  assert_true(prompt_opts[2].insert_input)
  assert_equal(calls[1], "select:alpha-builder:3:true")
  assert_equal(calls[2], "note:alpha-builder:ship this plan")
  assert_equal(calls[3], "notify:Sent note to Builder")
  assert_equal(calls[4], "render")
  assert_equal(calls[5], "focus:30")
  ui_mod.key_choice_menu = old_key_choice_menu
end

do
  local old_key_choice_menu = ui_mod.key_choice_menu
  local opened_picker = false
  local entry = { name = "alpha-builder", safe_name = "alpha-builder", mission_role = "Builder", status = "idle" }
  ui_mod.key_choice_menu = function(_, callback)
    opened_picker = true
    callback(nil)
    return true
  end
  local controller = mission_control_mod.new({})

  assert_true(controller:open_workspace_question_answer(entry))
  assert_true(opened_picker)
  ui_mod.key_choice_menu = old_key_choice_menu
end

do
  local old_key_choice_menu = ui_mod.key_choice_menu
  local notifications, notify = notifications_fixture()
  local opened_picker = false
  local entry = { name = "alpha-builder", safe_name = "alpha-builder", mission_role = "Builder", status = "inactive" }
  ui_mod.key_choice_menu = function()
    opened_picker = true
    return true
  end
  local controller = mission_control_mod.new({
    notify = notify,
  })

  assert_false(controller:open_workspace_question_answer(entry))
  assert_false(opened_picker)
  assert_contains(notifications[#notifications], "workspace is inactive")
  ui_mod.key_choice_menu = old_key_choice_menu
end

do
  local calls = {}
  local notifications, notify = notifications_fixture()
  local focused_win
  local entry = { name = "alpha-builder", safe_name = "alpha-builder", mission_role = "Builder", status = "question" }
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_command_win = 30,
    },
    notify = notify,
    is_valid_win = function(win)
      return win == 10 or win == 30
    end,
    set_current_win = function(win)
      focused_win = win
      return true
    end,
    ui = {
      single_line_prompt = function(opts, callback)
        assert_equal(opts.allowed_chars, "1234")
        assert_equal(opts.max_length, 1)
        callback("   ")
        return true
      end,
    },
    select_workspace_question_option = function()
      table.insert(calls, "select")
      return true, nil
    end,
    submit_workspace_question_note = function()
      table.insert(calls, "note")
      return true, nil
    end,
  })

  assert_true(controller:open_question_option_input(entry, "Builder", false))
  assert_contains(notifications[#notifications], "Option number is required")
  assert_equal(#calls, 0)

  controller.ui.single_line_prompt = function(_, callback)
    callback("ship this plan")
    return true
  end
  assert_true(controller:open_question_option_input(entry, "Builder", true))
  assert_contains(notifications[#notifications], "Option number must be 1, 2, 3, or 4")
  assert_equal(#calls, 0)

  controller.ui.single_line_prompt = function(_, callback)
    callback("   ")
    return true
  end
  assert_true(controller:open_question_note_input(entry, "Builder"))
  assert_contains(notifications[#notifications], "Note is required")
  assert_equal(#calls, 0)
  assert_equal(focused_win, 30)
end

do
  local notifications, notify = notifications_fixture()
  local focused_win
  local rendered = false
  local entry = { name = "alpha-builder", safe_name = "alpha-builder", mission_role = "Builder", status = "question" }
  local controller = mission_control_mod.new({
    state = {
      mission_dashboard_win = 10,
      mission_dashboard_command_win = 30,
    },
    notify = notify,
    is_valid_win = function(win)
      return win == 10 or win == 30
    end,
    set_current_win = function(win)
      focused_win = win
      return true
    end,
    ui = {
      single_line_prompt = function(opts, callback)
        assert_true(opts.insert_input)
        callback("needs more detail")
        return true
      end,
    },
    submit_workspace_question_note = function()
      return false, "note failed"
    end,
  })
  function controller:render_dashboard()
    rendered = true
    return true
  end

  assert_true(controller:open_question_note_input(entry, "Builder"))
  assert_equal(notifications[#notifications], "note failed")
  assert_false(rendered)
  assert_equal(focused_win, 30)
end

do
  local calls = {}
  local notifications, notify = notifications_fixture()
  local rendered = false
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "active",
    codex_status = "working",
  }
  local controller = mission_control_mod.new({
    notify = notify,
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
      single_line_prompt = function(opts, callback)
        table.insert(calls, "prompt:" .. tostring(opts.prompt))
        callback("next task")
        return true
      end,
    },
    interrupt_workspace = function(workspace)
      table.insert(calls, "interrupt:" .. tostring(workspace.safe_name))
      return true, nil
    end,
    send_prompt_to_workspace = function(workspace, prompt)
      table.insert(calls, "send:" .. tostring(workspace.safe_name) .. ":" .. prompt)
      return true, nil
    end,
  })
  function controller:render_dashboard()
    rendered = true
    return true
  end

  assert_true(controller:interrupt_selected_workspace(entry))
  assert_equal(calls[1], "interrupt:alpha-builder")
  assert_equal(calls[2], nil)
  assert_true(rendered)
  assert_contains(notifications[#notifications], "Interrupted Builder")
end

do
  local calls = {}
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    codex_status = "idle",
  }
  local controller = mission_control_mod.new({
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
      single_line_prompt = function()
        table.insert(calls, "prompt")
        return true
      end,
    },
    interrupt_workspace = function()
      table.insert(calls, "interrupt")
      return true, nil
    end,
    send_prompt_to_workspace = function()
      table.insert(calls, "send")
      return true, nil
    end,
  })

  assert_false(controller:interrupt_selected_workspace(entry))
  assert_equal(#calls, 0)
end

do
  local prompted = false
  local notifications, notify = notifications_fixture()
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "active",
    codex_status = "working",
  }
  local controller = mission_control_mod.new({
    notify = notify,
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
      single_line_prompt = function()
        prompted = true
        return true
      end,
    },
    interrupt_workspace = function()
      return false, "interrupt failed"
    end,
  })

  assert_false(controller:interrupt_selected_workspace(entry))
  assert_false(prompted)
  assert_equal(notifications[#notifications], "interrupt failed")
end

do
  local calls = {}
  local notifications, notify = notifications_fixture()
  local rendered = false
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    codex_mode = "plan",
  }
  local controller = mission_control_mod.new({
    notify = notify,
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
    },
    switch_workspace_mode = function(workspace)
      table.insert(calls, "switch:" .. tostring(workspace.safe_name))
      return true, nil
    end,
  })
  function controller:render_dashboard()
    rendered = true
  end

  assert_true(controller:switch_selected_workspace_mode(entry))
  assert_equal(calls[1], "switch:alpha-builder")
  assert_true(rendered)
  assert_equal(notifications[#notifications], "Switched Codux mode for Builder")
end

do
  local notifications, notify = notifications_fixture()
  local rendered = false
  local entry = {
    name = "alpha-builder",
    safe_name = "alpha-builder",
    mission_role = "Builder",
    status = "idle",
    codex_mode = "plan",
  }
  local controller = mission_control_mod.new({
    notify = notify,
    ui = {
      close_window = function() end,
      delete_buffer = function() end,
    },
    switch_workspace_mode = function()
      return false, "workspace is inactive"
    end,
  })
  function controller:render_dashboard()
    rendered = true
  end

  assert_false(controller:switch_selected_workspace_mode(entry))
  assert_false(rendered)
  assert_equal(notifications[#notifications], "workspace is inactive")
end

do
  local notifications, notify = notifications_fixture()
  local prompted = false
  local sent = false
  local controller = mission_control_mod.new({
    notify = notify,
    ui = {
      single_line_prompt = function()
        prompted = true
        return true
      end,
    },
    send_prompt_to_workspace = function()
      sent = true
      return true, nil
    end,
  })

  assert_false(controller:open_workspace_prompt({
    name = "alpha-reviewer",
    safe_name = "alpha-reviewer",
    mission_role = "Reviewer",
    status = "inactive",
  }))
  assert_false(prompted)
  assert_false(sent)
  assert_equal(notifications[#notifications], "workspace is inactive")
end

do
  local confirmed_message
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function(message, choices, default)
    confirmed_message = message
    assert_equal(choices, "&Yes\n&No")
    assert_equal(default, 2)
    return 2
  end
  local controller = mission_control_mod.new({
    mission_dirty_roles = function()
      return {
        { name = "mission-builder", reason = "dirty" },
        { name = "mission-reviewer", reason = "unknown" },
      }
    end,
  })

  assert_false(controller:confirm_delete_mission({ name = "Mission" }, "/repo"))
  assert_contains(confirmed_message, "permanently remove every role workspace")
  assert_contains(confirmed_message, "mission-builder")
  assert_contains(confirmed_message, "mission-reviewer (status unknown)")
  assert_contains(confirmed_message, "nuke uncommitted and untracked work")
  vim.fn.confirm = old_confirm
end


print("mission_dashboard_workspace_actions_spec.lua: ok")
