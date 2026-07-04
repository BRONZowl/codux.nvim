local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local terminal_mod = require("codux.terminal")

do
  assert_nil(terminal_mod.detect_terminal_mode_from_lines({ "> /plan" }))
  assert_nil(terminal_mod.detect_terminal_mode_from_lines({ "/plan" }))
  assert_equal(terminal_mod.detect_terminal_mode_from_lines({ "Plan mode" }), "plan")
  assert_equal(terminal_mod.detect_terminal_mode_from_lines({ "Execute mode" }), "execute")
  assert_equal(terminal_mod.detect_terminal_mode_from_lines({ "gpt-5.5 xhigh · ~/repo · Plan mode (shift+tab to cycle)" }), "plan")
  assert_equal(terminal_mod.detect_terminal_mode_from_lines({ "gpt-5.5 high · ~/repo · Execute mode (shift+tab to cycle)" }), "execute")
  assert_equal(terminal_mod.detect_terminal_mode_from_lines({ "gpt-5.5 xhigh · ~/repo                Plan mode" }), "plan")
  assert_equal(terminal_mod.detect_terminal_mode_from_lines({ "gpt-5.5 high · ~/repo                Execute mode" }), "execute")
  assert_equal(terminal_mod.detect_terminal_mode_from_lines({
    "gpt-5.5 high · ~/repo · Execute mode (shift+tab to cycle)",
    "gpt-5.5 xhigh · ~/repo · Plan mode (shift+tab to cycle)",
  }), "plan")
end

do
  local calls = {}
  local controller = terminal_mod.new({})
  function controller:exit()
    table.insert(calls, { name = "exit" })
  end
  function controller:start_terminal(focus, initial_prompt, command, workspace, permission_profile, opts)
    table.insert(calls, {
      name = "start_terminal",
      focus = focus,
      initial_prompt = initial_prompt,
      command = command,
      workspace = workspace,
      permission_profile = permission_profile,
      hidden = type(opts) == "table" and opts.hidden,
    })
    return "started"
  end

  assert_equal(controller:restart_hidden_with_command("codex-auto", "auto", "hello"), "started")
  assert_equal(calls[1].name, "exit")
  assert_equal(calls[2].name, "start_terminal")
  assert_equal(calls[2].focus, false)
  assert_equal(calls[2].initial_prompt, "hello")
  assert_equal(calls[2].command, "codex-auto")
  assert_nil(calls[2].workspace)
  assert_equal(calls[2].permission_profile, "auto")
  assert_equal(calls[2].hidden, true)
end

do
  local calls = {}
  local controller = terminal_mod.new({})
  function controller:exit()
    table.insert(calls, { name = "exit" })
  end
  function controller:valid_win()
    return true
  end
  function controller:focus_window()
    table.insert(calls, { name = "focus_window" })
  end
  function controller:start_terminal(focus, initial_prompt, command, workspace, permission_profile, opts)
    table.insert(calls, {
      name = "start_terminal",
      focus = focus,
      initial_prompt = initial_prompt,
      command = command,
      workspace = workspace,
      permission_profile = permission_profile,
      initial_mode = type(opts) == "table" and opts.initial_mode,
    })
    return "started"
  end

  assert_equal(controller:open({
    initial_prompt = "hello",
    initial_mode = "plan",
    focus = false,
  }), "started")
  assert_equal(calls[1].name, "start_terminal")
  assert_equal(calls[1].focus, false)
  assert_equal(calls[1].initial_prompt, "hello")
  assert_equal(calls[1].permission_profile, "default")
  assert_equal(calls[1].initial_mode, "plan")

  assert_equal(controller:restart_with_command("codex-auto", true, "auto", "fix it", {
    initial_mode = "plan",
  }), "started")
  assert_equal(calls[2].name, "exit")
  assert_equal(calls[3].name, "start_terminal")
  assert_equal(calls[3].focus, true)
  assert_equal(calls[3].initial_prompt, "fix it")
  assert_equal(calls[3].command, "codex-auto")
  assert_equal(calls[3].permission_profile, "auto")
  assert_equal(calls[3].initial_mode, "plan")
end

do
  local function with_terminal_start_env(opts, callback)
    opts = opts or {}
    local old_api = vim.api
    local old_defer_fn = vim.defer_fn
    local old_executable = vim.fn.executable
    local old_termopen = vim.fn.termopen
    local old_chansend = vim.fn.chansend
    local old_sleep = vim.fn.sleep
    local env = {
      lines = opts.lines or { "›", "Plan mode (shift+tab to cycle)" },
      sent = {},
      scheduled = {},
      notifications = {},
      sleep_count = 0,
    }
    function env:set_lines(lines)
      self.lines = lines
    end
    vim.api = {
      nvim_get_current_win = function()
        return 1
      end,
      nvim_buf_call = function(_, inner_callback)
        return inner_callback()
      end,
      nvim_buf_is_valid = function()
        return true
      end,
      nvim_buf_is_loaded = function()
        return true
      end,
      nvim_buf_line_count = function()
        return #env.lines
      end,
      nvim_buf_get_lines = function(_, start_line, end_line)
        local result = {}
        for index = start_line + 1, end_line do
          table.insert(result, env.lines[index])
        end
        return result
      end,
    }
    vim.defer_fn = function(inner_callback, delay)
      if opts.queue_defer then
        table.insert(env.scheduled, { callback = inner_callback, delay = delay })
      else
        inner_callback()
      end
    end
    vim.fn.executable = function()
      return 1
    end
    vim.fn.termopen = function()
      return 42
    end
    vim.fn.chansend = function(_, value)
      table.insert(env.sent, value)
      return #tostring(value or "")
    end
    vim.fn.sleep = function()
      env.sleep_count = env.sleep_count + 1
      if type(opts.on_sleep) == "function" then
        opts.on_sleep(env)
      end
      return 0
    end

    local controller = terminal_mod.new({
      command_util = {
        error = function()
          return nil
        end,
        executable = function()
          return "codex"
        end,
        with_prompt = function(command, prompt)
          env.command_prompt = prompt
          return command
        end,
      },
      get_config = opts.get_config or function()
        return {
          codex_cmd = "codex",
          default_initial_mode = "plan",
        }
      end,
      notify = function(message, level)
        table.insert(env.notifications, {
          message = message,
          level = level,
        })
      end,
    })
    function controller:terminal_running()
      return self.state.job_id ~= nil
    end
    function controller:ensure_buffer()
      self.state.buf = 12
      return true
    end
    function controller:valid_win()
      return false
    end
    function controller:set_codex_working(value)
      self.state.codex_working = value
    end
    function controller:mark_terminal_prompt_submission()
      self.state.marked_prompt_submission = true
    end
    if type(opts.screen_height) == "number" then
      function controller:terminal_screen_height()
        return opts.screen_height
      end
    end

    local ok, err = pcall(callback, controller, env)
    vim.api = old_api
    vim.defer_fn = old_defer_fn
    vim.fn.executable = old_executable
    vim.fn.termopen = old_termopen
    vim.fn.chansend = old_chansend
    vim.fn.sleep = old_sleep
    if not ok then
      error(err, 0)
    end
  end

  with_terminal_start_env({
    lines = { "›", "Booting MCP server: codex_apps (0s • esc to interrupt)" },
  }, function(controller)
    controller.state.buf = 12
    controller.state.job_id = 42
    assert_false(controller:startup_sequence_ready())
  end)

  with_terminal_start_env({
    lines = { "Booting MCP server: codex_apps (0s • esc to interrupt)", "›" },
    screen_height = 1,
  }, function(controller)
    controller.state.buf = 12
    controller.state.job_id = 42
    assert_true(controller:startup_sequence_ready())
  end)

  with_terminal_start_env({
    lines = { "Plan mode (shift+tab to cycle)" },
  }, function(controller)
    controller.state.buf = 12
    controller.state.job_id = 42
    assert_true(controller:startup_sequence_ready())
  end)

  with_terminal_start_env({
    get_config = function()
      return {
        codex_cmd = "codex",
      }
    end,
  }, function(controller, env)
    assert_true(controller:start_terminal(false, nil, "codex", { name = "role" }, "auto", {
      hidden = true,
      initial_mode = "plan",
    }))
    assert_equal(controller.state.mode, "plan")
    assert_nil(env.command_prompt)
    assert_equal(#env.sent, 0)
    assert_false(controller.state.codex_working)
  end)

  with_terminal_start_env({
    get_config = function()
      return {
        codex_cmd = "codex",
      }
    end,
  }, function(controller, env)
    assert_true(controller:start_terminal(false, "hello", "codex", { name = "role" }, "auto", {
      hidden = true,
      initial_mode = "plan",
    }))
    assert_equal(controller.state.mode, "plan")
    assert_nil(env.command_prompt)
    assert_equal(#env.sent, 1)
    assert_equal(env.sent[1], "\27[200~hello\27[201~\r")
    assert_true(controller.state.codex_working)
    assert_true(controller.state.marked_prompt_submission)
  end)

  with_terminal_start_env({}, function(controller, env)
    assert_true(controller:start_terminal(false, nil, "codex", { name = "role" }, "auto", {
      hidden = true,
    }))
    assert_equal(controller.state.mode, "plan")
    assert_equal(#env.sent, 0)
  end)

  with_terminal_start_env({
    get_config = function()
      return {
        codex_cmd = "codex",
        default_initial_mode = "execute",
      }
    end,
  }, function(controller, env)
    assert_true(controller:start_terminal(false, nil, "codex", { name = "role" }, "auto", {
      hidden = true,
    }))
    assert_equal(controller.state.mode, "execute")
    assert_equal(#env.sent, 0)
  end)

  with_terminal_start_env({}, function(controller, env)
    assert_true(controller:start_terminal(false, "hello", "codex", { name = "role" }, "auto", {
      hidden = true,
      initial_mode = "execute",
    }))
    assert_equal(controller.state.mode, "execute")
    assert_equal(env.command_prompt, "hello")
    assert_equal(#env.sent, 0)
    assert_true(controller.state.codex_working)
  end)

  with_terminal_start_env({
    lines = { "›", "Booting MCP server: codex_apps (0s • esc to interrupt)" },
    queue_defer = true,
  }, function(controller, env)
    assert_true(controller:start_terminal(false, "hello", "codex", { name = "role" }, "auto", {
      hidden = true,
    }))
    assert_nil(env.command_prompt)
    assert_equal(#env.sent, 0)
    assert_equal(#env.scheduled, 1)
    assert_equal(env.scheduled[1].delay, 250)

    env.scheduled[1].callback()
    assert_equal(#env.sent, 0)
    assert_nil(controller.state.marked_prompt_submission)
    assert_equal(#env.scheduled, 2)
    assert_equal(env.scheduled[2].delay, 250)

    env:set_lines({ "›" })
    env.scheduled[2].callback()
    assert_equal(controller.state.mode, "execute")
    assert_equal(#env.sent, 0)
    assert_nil(controller.state.marked_prompt_submission)
    assert_equal(#env.scheduled, 3)
    assert_equal(env.scheduled[3].delay, 4000)

    env.scheduled[3].callback()
    assert_equal(controller.state.mode, "execute")
    assert_equal(#env.sent, 1)
    assert_equal(env.sent[1], "\27[200~/plan\27[201~\r")
    assert_equal(#env.scheduled, 4)
    assert_equal(env.scheduled[4].delay, 250)

    env:set_lines({ "Plan mode (shift+tab to cycle)" })
    env.scheduled[4].callback()
    assert_equal(controller.state.mode, "plan")
    assert_equal(#env.sent, 2)
    assert_equal(env.sent[2], "\27[200~hello\27[201~\r")
    assert_true(controller.state.marked_prompt_submission)
  end)

  with_terminal_start_env({
    lines = { "›" },
    queue_defer = true,
  }, function(controller, env)
    assert_true(controller:start_terminal(false, nil, "codex", { name = "role" }, "auto", {
      hidden = true,
    }))
    assert_equal(#env.sent, 0)
    assert_equal(#env.scheduled, 1)

    env.scheduled[1].callback()
    assert_equal(controller.state.mode, "execute")
    assert_equal(#env.sent, 0)
    assert_equal(#env.scheduled, 2)
    assert_equal(env.scheduled[2].delay, 4000)

    env.scheduled[2].callback()
    assert_equal(controller.state.mode, "execute")
    assert_equal(#env.sent, 1)
    assert_equal(env.sent[1], "\27[200~/plan\27[201~\r")
    assert_equal(#env.scheduled, 3)
    assert_equal(env.scheduled[3].delay, 250)

    env:set_lines({ "Plan mode (shift+tab to cycle)" })
    env.scheduled[3].callback()
    assert_equal(controller.state.mode, "plan")
    assert_equal(#env.sent, 1)
  end)

  with_terminal_start_env({
    lines = { "Plan mode (shift+tab to cycle)" },
  }, function(controller, env)
    controller.state.buf = 12
    controller.state.job_id = 42
    controller.state.mode = "execute"
    assert_true(controller:ensure_plan_mode({ attempts = 1 }))
    assert_equal(controller.state.mode, "plan")
    assert_equal(#env.sent, 0)
  end)

  with_terminal_start_env({
    lines = { "Execute mode (shift+tab to cycle)" },
    on_sleep = function(env)
      if env.sleep_count == 1 then
        env:set_lines({ "Execute mode (shift+tab to cycle)" })
      else
        env:set_lines({ "Plan mode (shift+tab to cycle)" })
      end
    end,
  }, function(controller, env)
    controller.state.buf = 12
    controller.state.job_id = 42
    controller.state.mode = "execute"
    assert_true(controller:ensure_plan_mode({ attempts = 3 }))
    assert_equal(controller.state.mode, "plan")
    assert_equal(#env.sent, 1)
    assert_equal(env.sent[1], "\27[200~/plan\27[201~\r")
  end)

  with_terminal_start_env({
    lines = { "›" },
    on_sleep = function(env)
      if env.sleep_count < 3 then
        env:set_lines({ "■ '/plan' is disabled while a task is in progress." })
      else
        env:set_lines({ "gpt-5.5 xhigh · ~/repo                Plan mode" })
      end
    end,
  }, function(controller, env)
    controller.state.buf = 12
    controller.state.job_id = 42
    controller.state.mode = "execute"
    assert_true(controller:ensure_plan_mode({ attempts = 4 }))
    assert_equal(controller.state.mode, "plan")
    assert_equal(#env.sent, 3)
    assert_equal(env.sent[1], "\27[200~/plan\27[201~\r")
    assert_equal(env.sent[2], "\27[200~/plan\27[201~\r")
    assert_equal(env.sent[3], "\27[200~/plan\27[201~\r")
  end)

  with_terminal_start_env({
    lines = { "Execute mode (shift+tab to cycle)" },
  }, function(controller, env)
    controller.state.buf = 12
    controller.state.job_id = 42
    controller.state.mode = "execute"
    controller:confirm_startup_plan_sequence(nil, false, 1, false)
    assert_equal(#env.notifications, 1)
    assert_equal(env.notifications[1].message, "Codex did not confirm plan mode on startup")
  end)

  with_terminal_start_env({
    lines = { "Execute mode (shift+tab to cycle)" },
  }, function(controller, env)
    controller.state.buf = 12
    controller.state.job_id = 42
    controller.state.mode = "execute"
    controller:confirm_startup_plan_sequence(nil, false, 1, false, {
      suppress_warning = true,
    })
    assert_equal(#env.notifications, 0)
  end)

  with_terminal_start_env({}, function(controller, env)
    controller.state.buf = 12
    controller.state.job_id = nil
    assert_false(controller:ensure_plan_mode({ attempts = 1 }))
    assert_equal(#env.sent, 0)
  end)
end

do
  local old_api = vim.api
  local old_schedule = vim.schedule
  local lines = { "> /plan" }
  local synced_mode
  vim.api = {
    nvim_buf_is_valid = function()
      return true
    end,
    nvim_buf_is_loaded = function()
      return true
    end,
    nvim_buf_line_count = function()
      return #lines
    end,
    nvim_buf_get_lines = function(_, start_line, end_line)
      local result = {}
      for index = start_line + 1, end_line do
        table.insert(result, lines[index])
      end
      return result
    end,
  }
  vim.schedule = function(callback)
    callback()
  end

  local controller = terminal_mod.new({
    state = {
      buf = 9,
      job_id = 42,
      mode = "execute",
    },
    sync_workspace_mode = function(mode)
      synced_mode = mode
    end,
  })

  controller:schedule_terminal_buffer_observation()
  assert_equal(controller.state.mode, "execute")
  assert_nil(synced_mode)

  lines = { "Plan mode" }
  controller:schedule_terminal_buffer_observation()
  assert_equal(controller.state.mode, "plan")
  assert_equal(synced_mode, "plan")

  vim.api = old_api
  vim.schedule = old_schedule
end

do
  local sent
  local old_chansend = vim.fn.chansend
  vim.fn.chansend = function(job_id, value)
    assert_equal(job_id, 42)
    sent = value
    return 1
  end

  local controller = terminal_mod.new({})
  controller.state.job_id = 42
  controller.state.codex_working = true
  controller.state.terminal_prompt_input = "unfinished"
  controller.state.terminal_prompt_tracking_valid = false
  function controller:terminal_running()
    return true
  end

  assert_true(controller:interrupt_codex_session())
  assert_equal(sent, "\3")
  assert_false(controller.state.codex_working)
  assert_equal(controller.state.terminal_prompt_input, "")
  assert_true(controller.state.terminal_prompt_tracking_valid)

  vim.fn.chansend = old_chansend
end

do
  local sent = {}
  local sleeps = {}
  local old_chansend = vim.fn.chansend
  local old_sleep = vim.fn.sleep
  vim.fn.chansend = function(job_id, value)
    assert_equal(job_id, 42)
    table.insert(sent, value)
    return 1
  end
  vim.fn.sleep = function(value)
    table.insert(sleeps, value)
    return 1
  end

  local controller = terminal_mod.new({})
  controller.state.job_id = 42
  function controller:terminal_running()
    return true
  end
  function controller:valid_buf()
    return true
  end
  function controller:mark_terminal_prompt_submission()
    table.insert(sent, "mark")
  end
  function controller:set_codex_working(working)
    self.state.codex_working = working == true
  end

  local up = "\27[A"
  local down = "\27[B"
  local function reset_records()
    sent = {}
    sleeps = {}
    controller.state.codex_working = false
  end
  local function assert_option_sequence(expected_down_count, submit_key, mark_expected)
    local index = 1
    for _ = 1, 20 do
      assert_equal(sent[index], up)
      assert_equal(sleeps[index], "15m")
      index = index + 1
    end
    for _ = 1, expected_down_count do
      assert_equal(sent[index], down)
      assert_equal(sleeps[index], "15m")
      index = index + 1
    end

    assert_equal(sent[index], submit_key)
    assert_equal(sleeps[index], "40m")
    index = index + 1
    if mark_expected then
      assert_equal(sent[index], "mark")
      index = index + 1
    end
    assert_equal(sent[index], nil)
  end

  assert_true(controller:select_codex_question_option("1", false))
  assert_option_sequence(0, "\r", true)

  reset_records()
  assert_true(controller:select_codex_question_option("2", false))
  assert_option_sequence(1, "\r", true)
  assert_true(controller.state.codex_working)

  reset_records()
  assert_true(controller:select_codex_question_option("3", true))
  assert_option_sequence(2, "\t", false)
  assert_equal(sleeps[23], "40m")
  assert_equal(sleeps[24], "40m")
  assert_equal(sleeps[25], nil)

  reset_records()
  assert_true(controller:submit_codex_question_note("ship it"))
  assert_equal(sent[1], "\27[200~ship it\27[201~\r")
  assert_equal(sent[2], "mark")

  assert_false(controller:select_codex_question_option("two", false))
  assert_false(controller:select_codex_question_option("0", false))
  assert_false(controller:select_codex_question_option("5", false))
  assert_equal(sent[3], nil)

  vim.fn.chansend = old_chansend
  vim.fn.sleep = old_sleep
end

print("terminal_spec.lua: ok")
