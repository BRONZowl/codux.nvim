local h = require("tests.helpers")
local fixtures = require("tests.workspace_fixtures")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local default_workspace_config = fixtures.default_workspace_config
local with_workspace_prepare_env = fixtures.with_workspace_prepare_env
local workspace_prepare_runtime = fixtures.workspace_prepare_runtime
do
  with_workspace_prepare_env(function()
    local commands = {}
    local expected_server = "/tmp/stale-review.sock"
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "ok\n", 0
        end
        return "", 1
      end,
    })
    local ok, error_message = runtime:send_prompt_to_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, "  /plan  ", { attempts = 1 })
    assert_nil(error_message)
    assert_true(ok)
    local command_text = table.concat(commands, "\n")
    local ensure_index = command_text:find("remote_ensure_plan_mode", 1, true)
    local send_index = command_text:find("remote_send_to_codex", 1, true)
    assert_true(type(ensure_index) == "number")
    assert_true(type(send_index) == "number")
    assert_true(ensure_index < send_index)
    assert_contains(command_text, "remote_send_to_codex")
    assert_contains(command_text, "  /plan  ")
    assert_contains(command_text, expected_server)
    assert_equal(command_text:find(runtime:workspace_server_path("/repo", "review"), 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local expected_server = "/tmp/stale-review.sock"
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "ok\n", 0
        end
        return "", 1
      end,
    })
    local ok, error_message = runtime:select_workspace_question_option({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, "2", { attempts = 1 })
    assert_nil(error_message)
    assert_true(ok)
    local command_text = table.concat(commands, "\n")
    local ensure_index = command_text:find("remote_ensure_plan_mode", 1, true)
    local answer_index = command_text:find("remote_select_codex_question_option", 1, true)
    assert_true(type(answer_index) == "number")
    assert_nil(ensure_index)
    assert_contains(command_text, '\\"2\\"')
    assert_contains(command_text, "false")
    assert_contains(command_text, expected_server)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local expected_server = "/tmp/stale-review.sock"
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "ok\n", 0
        end
        return "", 1
      end,
    })
    local ok, error_message = runtime:select_workspace_question_option({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, "3", { attempts = 1, with_note = true })
    assert_nil(error_message)
    assert_true(ok)
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "remote_select_codex_question_option")
    assert_equal(command_text:find("remote_ensure_plan_mode", 1, true), nil)
    assert_contains(command_text, '\\"3\\"')
    assert_contains(command_text, "true")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      system = function(args)
        table.insert(commands, table.concat(args, " "))
        return "", 1
      end,
    })
    local ok, error_message = runtime:select_workspace_question_option({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }, "5", { attempts = 1 })
    assert_false(ok)
    assert_equal(error_message, "Option number must be 1, 2, 3, or 4")
    assert_equal(#commands, 0)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local expected_server = "/tmp/stale-review.sock"
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "ok\n", 0
        end
        return "", 1
      end,
    })
    local ok, error_message = runtime:submit_workspace_question_note({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, "ship it", { attempts = 1 })
    assert_nil(error_message)
    assert_true(ok)
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "remote_submit_codex_question_note")
    assert_contains(command_text, "ship it")
    assert_equal(command_text:find("remote_ensure_plan_mode", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local expected_server = "/tmp/stale-review.sock"
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("remote_ensure_plan_mode", 1, true) then
          return "failed\n", 0
        end
        if command:find("remote_send_to_codex", 1, true) then
          error("prompt should not be sent before plan mode is confirmed")
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "ok\n", 0
        end
        return "", 1
      end,
    })
    local ok, error_message = runtime:send_prompt_to_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, "do work", { attempts = 1 })
    assert_false(ok)
    assert_equal(error_message, "failed")
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "remote_ensure_plan_mode")
    assert_equal(command_text:find("remote_send_to_codex", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local expected_server = "/tmp/stale-review.sock"
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "ok\n", 0
        end
        return "", 1
      end,
    })
    local ok, error_message = runtime:switch_workspace_mode({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, { attempts = 1 })
    assert_nil(error_message)
    assert_true(ok)
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "remote_switch_codex_mode")
    assert_contains(command_text, expected_server)
    assert_equal(command_text:find(runtime:workspace_server_path("/repo", "review"), 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local pane_checks = 0
    local expected_server = "/tmp/stale-review.sock"
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          pane_checks = pane_checks + 1
          if pane_checks == 1 then
            return "bash\n", 0
          end
          return "nvim\n", 0
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "ok\n", 0
        end
        return "", 1
      end,
    })
    local ok, error_message = runtime:ensure_workspace_plan_mode({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, { attempts = 1, remote_attempts = 2, remote_sleep_ms = 1 })
    assert_nil(error_message)
    assert_true(ok)
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "remote_ensure_plan_mode")
    assert_contains(command_text, expected_server)
    assert_equal(command_text:find(runtime:workspace_server_path("/repo", "review"), 1, true), nil)
    assert_equal(pane_checks, 2)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "bash\n", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:switch_workspace_mode({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/review.sock",
    }, { attempts = 1 })
    assert_false(ok)
    assert_equal(error_message, "workspace is inactive")
    assert_equal(table.concat(commands, "\n"):find("remote_switch_codex_mode", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local expected_server = "/tmp/stale-review.sock"
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "ok\n", 0
        end
        return "", 1
      end,
    })
    local ok, error_message = runtime:interrupt_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, { attempts = 1 })
    assert_nil(error_message)
    assert_true(ok)
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "remote_interrupt_codex_session")
    assert_contains(command_text, expected_server)
    assert_equal(command_text:find(runtime:workspace_server_path("/repo", "review"), 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:send_prompt_to_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/review.sock",
    }, "/plan", { attempts = 1 })
    assert_false(ok)
    assert_equal(error_message, "workspace is inactive")
    assert_equal(table.concat(commands, "\n"):find("remote_send_to_codex", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "bash\n", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:interrupt_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/review.sock",
    }, { attempts = 1 })
    assert_false(ok)
    assert_equal(error_message, "workspace is inactive")
    assert_equal(table.concat(commands, "\n"):find("remote_interrupt_codex_session", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "bash\n", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:send_prompt_to_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/review.sock",
    }, "/plan", { attempts = 1 })
    assert_false(ok)
    assert_equal(error_message, "workspace is inactive")
    assert_equal(table.concat(commands, "\n"):find("remote_send_to_codex", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local expected_server = "/tmp/stale-review.sock"
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "ok\n", 0
        end
        if command == "tmux kill-session -t codux-preview-test" then
          return "", 1
        end
        if command == "tmux new-session -d -t session -s codux-preview-test" then
          return "", 0
        end
        if command == "tmux select-window -t codux-preview-test:review" then
          return "", 0
        end
        return "", 1
      end,
    })
    local preview, error_message = runtime:workspace_interactive_preview({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, { attempts = 1, preview_session = "codux-preview-test" })
    assert_nil(error_message)
    assert_equal(table.concat(preview.command, " "), "env -u TMUX tmux attach-session -t codux-preview-test")
    assert_equal(preview.preview_session, "codux-preview-test")
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "remote_show_existing_codex_terminal")
    assert_contains(command_text, expected_server)
    assert_contains(command_text, "tmux new-session -d -t session -s codux-preview-test")
    assert_contains(command_text, "tmux select-window -t codux-preview-test:review")
    assert_equal(command_text:find(runtime:workspace_server_path("/repo", "review"), 1, true), nil)
    assert_equal(command_text:find(" codex ", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local runtime = workspace_prepare_runtime({
      get_config = function()
        local config = default_workspace_config()
        config.workspaces.tmux_cmd = "/usr/bin/tmux"
        return config
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "/usr/bin/tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "/usr/bin/tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "/usr/bin/tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("nvim --server ", 1, true) and command:find("remote_show_existing_codex_terminal", 1, true) then
          return "ok\n", 0
        end
        if command == "/usr/bin/tmux kill-session -t codux-preview-test" then
          return "", 1
        end
        if command == "/usr/bin/tmux new-session -d -t session -s codux-preview-test" then
          return "", 0
        end
        if command == "/usr/bin/tmux select-window -t codux-preview-test:review" then
          return "", 0
        end
        return "", 1
      end,
    })

    local preview, error_message = runtime:workspace_interactive_preview({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }, { attempts = 1, preview_session = "codux-preview-test" })
    assert_nil(error_message)
    assert_equal(table.concat(preview.command, " "), "env -u TMUX /usr/bin/tmux attach-session -t codux-preview-test")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local expected_server
    local runtime = workspace_prepare_runtime({
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "@1\treview\n", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if expected_server and command:find("nvim --server " .. expected_server .. " --remote-expr", 1, true) then
          return "not_running\n", 0
        end
        return "", 1
      end,
    })
    expected_server = runtime:workspace_server_path("/repo", "review")

    local preview, error_message = runtime:workspace_interactive_preview({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }, { attempts = 1, preview_session = "codux-preview-test" })
    assert_nil(preview)
    assert_equal(error_message, "workspace Codex session is not running")
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "remote_show_existing_codex_terminal")
    assert_equal(command_text:find("tmux new-session", 1, true), nil)
  end)
end


print("workspace_runtime_remote_spec.lua: ok")
