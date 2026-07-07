local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true

local compat = require("codux.compat")

do
  local api = compat.install({}, {
    project_root = function()
      return "/repo"
    end,
    names_for_project = function(root)
      assert_equal(root, "/repo")
      return { "review", "debug" }
    end,
    mission_names_for_project = function(root)
      assert_equal(root, "/repo")
      return { "Mission" }
    end,
  })

  assert_equal(api.permission_profile_choices()[1].profile, "default")
  assert_equal(api.keyed_permission_profile_choices()[2].key, "a")
  assert_true(api.should_select_permission_profile(nil))
  assert_equal(api.open_permission_profile_choice({ profile = "auto" }, {
    initial_prompt = "ship",
    open_auto = function(prompt)
      return "auto:" .. prompt
    end,
  }), "auto:ship")
  assert_equal(table.concat(api.complete_workspace_names(""), ","), "review,debug")
  assert_equal(table.concat(api.complete_mission_names(""), ","), "Mission")
end

do
  local calls = {}
  local api = compat.install_ui({}, {
    notify = function(message)
      table.insert(calls, "notify:" .. tostring(message))
    end,
    ui = {
      set_keymap = function(_, _, lhs)
        table.insert(calls, "key:" .. lhs)
      end,
      bind_close_keys = function()
        table.insert(calls, "close")
      end,
      single_line_prompt = function(opts, callback, deps)
        table.insert(calls, "prompt:" .. opts.prompt)
        deps.set_buffer_keymap(1, "n", "x", function() end, "X")
        deps.bind_close_keys(1, function() end, "Close")
        callback("ok")
        return true
      end,
    },
  })

  assert_true(api.single_line_prompt({ prompt = "Codux: " }, function(input)
    table.insert(calls, "input:" .. input)
  end))
  assert_equal(table.concat(calls, ","), "prompt:Codux: ,key:x,close,input:ok")
end

do
  local calls = {}
  local api = compat.install_terminal({}, {
    terminal = {
      mark_terminal_prompt_submission = function()
        return "mark"
      end,
      plan_question_pending = function()
        return true
      end,
      sync_terminal_mode_from_buffer = function()
        return "sync"
      end,
      schedule_terminal_buffer_observation = function()
        return "schedule"
      end,
      terminal_snapshot = function(_, max_lines)
        return "lines:" .. tostring(max_lines)
      end,
      send_to_codex = function(_, message)
        return message == "ok"
      end,
      select_codex_question_option = function(_, option, with_note)
        return option == "2" and with_note
      end,
      submit_codex_question_note = function(_, note)
        return note == "note"
      end,
      interrupt_codex_session = function()
        table.insert(calls, "interrupt")
        return true
      end,
      toggle_plan_mode = function()
        return true
      end,
      terminal_running = function()
        return true
      end,
      open_window = function(_, focus)
        return focus
      end,
      ensure_plan_mode = function()
        return true
      end,
    },
  })

  assert_equal(api.remote_terminal_snapshot(0), "lines:1")
  assert_equal(api.remote_send_to_codex("ok"), "ok")
  assert_equal(api.remote_send_to_codex("no"), "failed")
  assert_equal(api.remote_select_codex_question_option("2", true), "ok")
  assert_equal(api.remote_submit_codex_question_note("note"), "ok")
  assert_equal(api.remote_interrupt_codex_session(), "ok")
  assert_equal(table.concat(calls, ","), "interrupt")
  assert_equal(api.remote_switch_codex_mode(), "ok")
  assert_equal(api.remote_show_existing_codex_terminal(), "ok")
  assert_equal(api.remote_workspace_status(), "ready")
  assert_equal(api.remote_ensure_plan_mode(), "ok")
end

do
  local opened
  local sent
  local api = compat.install({}, {})
  compat.install_prompt_open(api, {
    state = {},
    terminal = {
      send_to_codex = function(_, message)
        sent = message
        return true
      end,
    },
    open_with_keyed_profile_menu = function(opts)
      opened = opts
      return true
    end,
  })

  assert_true(api.send_prompt_or_open_with_profile("build"))
  assert_equal(opened.initial_prompt, "build")
  assert_equal(opened.open_opts.initial_mode, "plan")

  opened = nil
  compat.install_prompt_open(api, {
    state = { job_id = 12 },
    terminal = {
      send_to_codex = function(_, message)
        sent = message
        return true
      end,
    },
    open_with_keyed_profile_menu = function()
      error("should not open profile menu while a job is running")
    end,
  })
  assert_true(api.send_prompt_or_open_with_profile("continue"))
  assert_equal(sent, "continue")
  assert_equal(opened, nil)
end

do
  local api = compat.install_workspace_manager({}, {
    controller = {
      render_search = function()
        return "render"
      end,
      update_query = function(_, query)
        return "update:" .. query
      end,
      append_query = function(_, input)
        return "append:" .. input
      end,
      delete_query_char = function()
        return "delete"
      end,
      clear_query = function()
        return "clear"
      end,
      open_search_input = function()
        return "open"
      end,
    },
    runtime = {
      close_saved_workspace_window = function(_, entry)
        return "close:" .. entry.name
      end,
      close_all_saved_workspace_windows = function(_, root)
        return "close-all:" .. root
      end,
      saved_workspace_instruction_request = function(_, entry)
        return { name = entry.name }
      end,
      update_saved_workspace_instruction = function(_, entry, instruction)
        return entry.name == "review" and instruction == "new"
      end,
    },
  })

  assert_equal(api.render_workspace_manager_search(), "render")
  assert_equal(api.update_workspace_manager_query("re"), "update:re")
  assert_equal(api.append_workspace_manager_query("v"), "append:v")
  assert_equal(api.delete_workspace_manager_query_char(), "delete")
  assert_equal(api.clear_workspace_manager_query(), "clear")
  assert_equal(api.open_workspace_manager_search_input(), "open")
  assert_equal(api.close_saved_workspace_window({ name = "review" }), "close:review")
  assert_equal(api.close_all_saved_workspace_windows("/repo"), "close-all:/repo")
  assert_equal(api.saved_workspace_instruction_request({ name = "review" }).name, "review")
  assert_true(api.update_saved_workspace_instruction({ name = "review" }, "new"))
end

do
  local api = compat.install_workspace_create({}, {
    controller = {
      preview_lines = function()
        return { "preview" }
      end,
      create_preview_config = function(_, line_count)
        return { height = line_count }
      end,
      create_footer_segments = function()
        return { "footer" }
      end,
      create_footer_line = function()
        return "footer"
      end,
      render_create_footer = function(_, _bufnr, width)
        return width
      end,
      open_create_footer = function(_, win)
        return win
      end,
      instruction_editor_config = function(_, line_count)
        return { height = line_count }
      end,
    },
  })

  assert_equal(api.workspace_create_preview_lines({})[1], "preview")
  assert_equal(api.workspace_create_preview_config(3).height, 3)
  assert_equal(api.workspace_create_footer_segments()[1], "footer")
  assert_equal(api.workspace_create_footer_line(), "footer")
  assert_equal(api.render_workspace_create_footer(1, 80), 80)
  assert_equal(api.open_workspace_create_footer(12), 12)
  assert_equal(api.workspace_instruction_editor_config(4).height, 4)
  assert_equal(api.workspace_instruction_mode_label("append"), " NORMAL ")
end

print("compat_spec.lua: ok")
