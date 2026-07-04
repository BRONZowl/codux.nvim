local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local runtime_mod = require("codux.workspace_runtime")
local mission_mod = require("codux.mission")
local workspace_ui = require("codux.workspace_ui")

local function runtime_with_tmux(responses, state)
  return runtime_mod.new({
    state = state or {},
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      local response = responses[command]
      if response == nil then
        return "", 1
      end
      return response[1], response[2]
    end,
  })
end

local function review_workspace_record(fields)
  local record = {
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    tmux_window = "review",
    status = "inactive",
    codex_status = "idle",
  }
  for key, value in pairs(fields or {}) do
    record[key] = value
  end
  return record
end

local function workspace_state(workspaces, fields)
  local project = {
    workspaces = workspaces or {},
  }
  for key, value in pairs(fields or {}) do
    project[key] = value
  end
  return {
    projects = {
      ["/repo"] = project,
    },
  }
end

local function default_workspace_config()
  return {
    codex_cmd = "codex",
    workspace_auto_cmd = "codex-auto",
    danger_full_access_cmd = "codex-danger",
    default_initial_mode = "plan",
    workspaces = {
      tmux_cmd = "tmux",
      nvim_cmd = "nvim",
    },
  }
end

local function default_workspace_from_state(record, fallback)
  local workspace = vim.deepcopy(fallback)
  if type(record) == "table" then
    for key, value in pairs(record) do
      workspace[key] = value
    end
  end
  return workspace
end

local function default_state_record(_, workspace)
  return {
    name = workspace.name,
    safe_name = workspace.safe_name,
    project_root = workspace.project_root,
    resolved_instruction = workspace.resolved_instruction,
    target_path = workspace.target_path,
    target_type = workspace.target_type,
    permission_profile = workspace.permission_profile,
    tmux_window = workspace.window_name,
    status = workspace.status,
    codex_status = workspace.codex_status,
    git_branch = workspace.git_branch,
    workspace_kind = workspace.workspace_kind,
    git_common_dir = workspace.git_common_dir,
    worktree_path = workspace.worktree_path,
    worktree_branch = workspace.worktree_branch,
    worktree_base = workspace.worktree_base,
    worktree_base_commit = workspace.worktree_base_commit,
    mission_id = workspace.mission_id,
    mission_name = workspace.mission_name,
    mission_role = workspace.mission_role,
    mission_objective = workspace.mission_objective,
    nvim_server = workspace.nvim_server,
    initial_mode = workspace.initial_mode,
    codex_mode = workspace.codex_mode,
  }
end

local function project_state(_, state, root)
  state.projects[root] = state.projects[root] or { workspaces = {} }
  return state.projects[root]
end

local function with_filereadable(value, callback)
  local old_filereadable = vim.fn.filereadable
  vim.fn.filereadable = function()
    return value
  end
  local ok, err = pcall(callback)
  vim.fn.filereadable = old_filereadable
  if not ok then
    error(err, 0)
  end
end

local function with_workspace_prepare_env(callback)
  local old_tmux = vim.env.TMUX
  local old_executable = vim.fn.executable
  local old_isdirectory = vim.fn.isdirectory
  local old_filereadable = vim.fn.filereadable
  local old_getcwd = vim.fn.getcwd
  local old_shellescape = vim.fn.shellescape

  vim.env.TMUX = "/tmp/tmux,1,0"
  vim.fn.executable = function()
    return 1
  end
  vim.fn.isdirectory = function(path)
    return path == "/repo" and 1 or 0
  end
  vim.fn.filereadable = function(path)
    return (path == "/repo/file.lua" or path == "/codux-worktrees/review/file.lua") and 1 or 0
  end
  vim.fn.getcwd = function()
    return "/repo"
  end
  vim.fn.shellescape = function(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
  end

  local ok, err = pcall(callback)
  vim.env.TMUX = old_tmux
  vim.fn.executable = old_executable
  vim.fn.isdirectory = old_isdirectory
  vim.fn.filereadable = old_filereadable
  vim.fn.getcwd = old_getcwd
  vim.fn.shellescape = old_shellescape
  if not ok then
    error(err, 0)
  end
end

local function workspace_prepare_runtime(opts)
  opts = opts or {}
  local custom_system = opts.system
  return runtime_mod.new({
    state = opts.state or {},
    notify = opts.notify,
    get_config = opts.get_config or default_workspace_config,
    current_target = opts.current_target or function()
      return { path = "/repo/file.lua", type = "file" }
    end,
    current_buffer_name = opts.current_buffer_name or function()
      return "/repo/file.lua"
    end,
    current_buffer = opts.current_buffer or function()
      return 1
    end,
    alternate_buffer = opts.alternate_buffer or function()
      return 1
    end,
    list_buffers = opts.list_buffers or function()
      return {}
    end,
    is_loaded_buf = opts.is_loaded_buf or function()
      return false
    end,
    git_root_for = opts.git_root_for or function()
      return "/repo"
    end,
    git_branch_for = opts.git_branch_for or function()
      return "main"
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if custom_system then
        local output, code = custom_system(args)
        if code == 0 or output ~= "" or command:find("^tmux") then
          return output, code
        end
      end
      if command == "git -C /repo status --porcelain" then
        return "", 0
      end
      if command == "git -C /repo branch --show-current" then
        return "main\n", 0
      end
      if command == "git -C /repo rev-parse main" then
        return "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 0
      end
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
        return "", 1
      end
      if command == "git -C /repo worktree add -b dev/review /codux-worktrees/review main" then
        return "", 0
      end
      if command == "git -C /repo worktree remove --force /codux-worktrees/review" then
        return "", 0
      end
      if command == "git -C /repo branch -D dev/review" then
        return "", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 1
      end
      return "", 1
    end,
    store = opts.store or {},
  })
end

local function workspace_store(opts)
  opts = opts or {}
  local state_data = opts.state_data or { projects = {} }
  return {
    state_data = function()
      return state_data
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = opts.write_state or function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = opts.project_state or project_state,
      workspace_from_state = opts.workspace_from_state or default_workspace_from_state,
      state_record = opts.state_record or default_state_record,
      instruction_file_path = opts.instruction_file_path or function()
        return "/repo/.agents/codux/review.md"
      end,
      read_instruction_file = opts.read_instruction_file or function()
        return nil
      end,
      write_instruction_file = opts.write_instruction_file or function()
        return true, nil
      end,
      delete_instruction_file = opts.delete_instruction_file or function()
        return true, nil
      end,
      instruction_file_records = opts.instruction_file_records or function()
        return {}
      end,
      resolve_workspace_resume_session = opts.resolve_workspace_resume_session or function() end,
    },
  }
end

local function workspace_delete_runtime(store, opts)
  opts = opts or {}
  return runtime_mod.new({
    state = opts.state or {
      workspace_manager_project_root = "/repo",
    },
    notify = opts.notify or function() end,
    render_workspace_manager = opts.render_workspace_manager or function() end,
    close_workspace_manager = opts.close_workspace_manager or function() end,
    system = opts.system,
    store = store,
  })
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      table.insert(calls, table.concat(args, " "))
      return "", 0
    end,
  })

  local status = runtime:workspace_instruction_ignore_status("/repo")
  assert_equal(status.status, "ignored")
  assert_equal(status.relative_dir, ".agents/codux")
  assert_equal(status.rule, ".agents/")
  assert_equal(calls[1], "git -C /repo check-ignore --quiet -- .agents/codux/.codux-ignore-check")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })

  local status = runtime:workspace_instruction_ignore_status("/repo")
  assert_equal(status.status, "not_ignored")
  assert_contains(runtime:workspace_instruction_ignore_warning("/repo"), "run :CoduxWorkspaceIgnore")
end

do
  local calls = 0
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            enabled = false,
          },
        },
      }
    end,
    system = function()
      calls = calls + 1
      return "", 1
    end,
  })

  assert_equal(runtime:workspace_instruction_ignore_status("/repo").status, "skipped")
  assert_equal(calls, 0)
end

do
  local checked
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            directory = "codux-workspaces",
          },
        },
      }
    end,
    system = function(args)
      checked = table.concat(args, " ")
      return "", 1
    end,
  })

  local status = runtime:workspace_instruction_ignore_status("/repo")
  assert_equal(status.status, "not_ignored")
  assert_equal(status.rule, "codux-workspaces/")
  assert_equal(checked, "git -C /repo check-ignore --quiet -- codux-workspaces/.codux-ignore-check")
end

do
  local calls = 0
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            directory = "/tmp/codux-workspaces",
          },
        },
      }
    end,
    system = function()
      calls = calls + 1
      return "", 1
    end,
  })

  assert_equal(runtime:workspace_instruction_ignore_status("/repo").status, "skipped")
  assert_equal(calls, 0)
end

do
  local calls = 0
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            directory = "../codux-workspaces",
          },
        },
      }
    end,
    system = function()
      calls = calls + 1
      return "", 1
    end,
  })

  assert_equal(runtime:workspace_instruction_ignore_status("/repo").status, "skipped")
  assert_equal(calls, 0)
end

do
  local messages = {}
  local runtime = runtime_mod.new({
    state = {},
    get_config = default_workspace_config,
    notify = function(message)
      table.insert(messages, message)
    end,
    system = function()
      return "", 1
    end,
  })

  assert_true(runtime:warn_workspace_instruction_ignore("/repo"))
  assert_false(runtime:warn_workspace_instruction_ignore("/repo"))
  assert_equal(#messages, 1)
  assert_contains(messages[1], "Add .agents/ to .gitignore")
end

do
  local old_filereadable = vim.fn.filereadable
  local old_writefile = vim.fn.writefile
  local written_path
  local written_lines
  vim.fn.filereadable = function()
    return 0
  end
  vim.fn.writefile = function(lines, path)
    written_lines = lines
    written_path = path
    return 0
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.writefile = old_writefile

  assert_true(ok)
  assert_equal(message, "Added .agents/ to .gitignore")
  assert_equal(written_path, "/repo/.gitignore")
  assert_equal(written_lines[#written_lines], ".agents/")
end

do
  local old_filereadable = vim.fn.filereadable
  local old_readfile = vim.fn.readfile
  local old_writefile = vim.fn.writefile
  local written_lines
  vim.fn.filereadable = function()
    return 1
  end
  vim.fn.readfile = function()
    return { "*.log" }
  end
  vim.fn.writefile = function(lines)
    written_lines = lines
    return 0
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 0
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.readfile = old_readfile
  vim.fn.writefile = old_writefile

  assert_true(ok)
  assert_equal(message, "Added .agents/ to .gitignore")
  assert_equal(written_lines[#written_lines], ".agents/")
end

do
  local old_filereadable = vim.fn.filereadable
  local old_readfile = vim.fn.readfile
  local old_writefile = vim.fn.writefile
  local wrote = false
  vim.fn.filereadable = function()
    return 1
  end
  vim.fn.readfile = function()
    return { ".agents/" }
  end
  vim.fn.writefile = function()
    wrote = true
    return 0
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.readfile = old_readfile
  vim.fn.writefile = old_writefile

  assert_true(ok)
  assert_equal(message, "Codux workspace instructions are already ignored by Git")
  assert_false(wrote)
end

do
  local old_filereadable = vim.fn.filereadable
  local old_writefile = vim.fn.writefile
  vim.fn.filereadable = function()
    return 0
  end
  vim.fn.writefile = function()
    return -1
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to update .gitignore")
end

do
  local runtime = runtime_with_tmux({
    ["tmux list-panes -t @1 -F #{pane_current_command}"] = { "bash\nnvim\n", 0 },
  })

  assert_equal(runtime:status_for_window("@1"), "active", "nvim in any pane should mark window active")
end

do
  local runtime = runtime_with_tmux({
    ["tmux list-panes -t @1 -F #{pane_current_command}"] = { "bash\nzsh\n", 0 },
  })

  assert_equal(runtime:status_for_window("@1"), "inactive", "non-nvim panes should mark window inactive")
end

do
  local runtime = runtime_with_tmux({})

  assert_equal(runtime:status_for_window(nil), "inactive")
  assert_equal(runtime:dashboard_workspace_status({ status = "idle", codex_status = "idle" }, nil), "inactive")
  assert_equal(runtime:dashboard_workspace_status({ status = "inactive", codex_status = "idle" }, nil), "inactive")
end

do
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        safe_name = "review",
      },
    },
  })

  assert_false(runtime:target_sync_allowed("BufEnter", function()
    return "codux-missions"
  end))
  assert_false(runtime:target_sync_allowed("BufEnter", function()
    return "codux-missions-actions"
  end))
  assert_false(runtime:target_sync_allowed("BufEnter", function()
    return "codux-mission-workspace-prompt"
  end))
  assert_true(runtime:target_sync_allowed("BufEnter", function()
    return "lua"
  end))
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
    local ok, error_message = runtime:send_prompt_to_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      nvim_server = "/tmp/stale-review.sock",
    }, "  /plan  ", { attempts = 1 })
    assert_nil(error_message)
    assert_true(ok)
    local command_text = table.concat(commands, "\n")
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

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
        return "", 1
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(error_message)
  assert_equal(branch, "dev/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1/review" then
        return "", 1
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(error_message)
  assert_equal(branch, "dev1/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1" then
        return "", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev2" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev2/review" then
        return "", 1
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(error_message)
  assert_equal(branch, "dev2/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
        return "", 0
      end
      return "", 1
    end,
  })

  local branch, error_message = runtime:resolve_worktree_branch("/repo", "review")
  assert_nil(branch)
  assert_equal(error_message, "branch already exists: dev/review")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
  })

  assert_equal(runtime:renamed_worktree_branch({ worktree_branch = "dev1/review" }, "search"), "dev1/search")
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          docs = {
            name = "docs",
            safe_name = "docs",
            project_root = "/repo",
            tmux_window = "docs",
          },
        },
      },
      ["/codux-worktrees/review"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/codux-worktrees/review",
            tmux_window = "review",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_path = "/codux-worktrees/review",
            worktree_branch = "dev/review",
            worktree_base = "main",
          },
        },
      },
    },
  }
  local runtime = runtime_mod.new({
    store = {
      read_state = function()
        return state_data, nil
      end,
      instruction_file_records = function()
        return {}
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      return "", 1
    end,
  })

  local entries = runtime:entries_for_project("/repo")
  local by_name = {}
  for _, entry in ipairs(entries) do
    by_name[entry.name] = entry
  end
  assert_equal(by_name.docs.project_root, "/repo")
  assert_equal(by_name.review.project_root, "/codux-worktrees/review")
  assert_equal(by_name.review.worktree_branch, "dev/review")
end

do
  local builder_instruction = mission_mod.role_instruction("Alpha", "Old objective", {
    name = "Builder",
    safe_name = "builder",
    focus = "Build it.",
  })
  local reviewer_instruction = mission_mod.role_instruction("Alpha", "Old objective", {
    name = "Reviewer",
    safe_name = "reviewer",
    focus = "Review it.",
  })
  local state_data = {
    projects = {
      ["/codux-worktrees/alpha-builder"] = {
        workspaces = {
          ["alpha-builder"] = review_workspace_record({
            name = "alpha-builder",
            safe_name = "alpha-builder",
            project_root = "/codux-worktrees/alpha-builder",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
            mission_id = "mission:alpha",
            mission_name = "Alpha",
            mission_role = "Builder",
            mission_objective = "Old objective",
            resolved_instruction = builder_instruction,
          }),
        },
      },
      ["/codux-worktrees/alpha-reviewer"] = {
        workspaces = {
          ["alpha-reviewer"] = review_workspace_record({
            name = "alpha-reviewer",
            safe_name = "alpha-reviewer",
            project_root = "/codux-worktrees/alpha-reviewer",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
            mission_id = "mission:alpha",
            mission_name = "Alpha",
            mission_role = "Reviewer",
            mission_objective = "Old objective",
            resolved_instruction = reviewer_instruction,
          }),
        },
      },
    },
  }
  local written_instructions = {}
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        mission_id = "mission:alpha",
        mission_objective = "Old objective",
        resolved_instruction = builder_instruction,
        project_root = "/codux-worktrees/alpha-builder",
        safe_name = "alpha-builder",
      },
    },
    notify = function() end,
    render_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-07-02T00:00:00Z"
      end,
      project_state = project_state,
      instruction_file_records = function()
        return {}
      end,
      write_instruction_file = function(_, root, safe_name, instruction)
        table.insert(written_instructions, root .. ":" .. safe_name .. ":" .. instruction)
        return true, nil
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/alpha-builder status --porcelain" then
        return " M lua/codux/init.lua\n", 0
      end
      if command == "git -C /codux-worktrees/alpha-reviewer status --porcelain" then
        return "", 0
      end
      return "", 1
    end,
  })

  assert_equal(runtime:mission_names_for_project("/repo")[1], "Alpha")
  local ok, error_message = runtime:update_mission_objective("Alpha", "New objective", { project_root = "/repo" })
  assert_true(ok)
  assert_nil(error_message)
  assert_equal(
    state_data.projects["/codux-worktrees/alpha-builder"].workspaces["alpha-builder"].mission_objective,
    "New objective"
  )
  assert_contains(
    state_data.projects["/codux-worktrees/alpha-reviewer"].workspaces["alpha-reviewer"].resolved_instruction,
    "Objective:\nNew objective\n\nRole focus:"
  )
  assert_equal(runtime.state.workspace.mission_objective, "New objective")
  assert_equal(#written_instructions, 2)

  local dirty_roles, dirty_error = runtime:mission_dirty_roles("Alpha", { project_root = "/repo" })
  assert_nil(dirty_error)
  assert_equal(#dirty_roles, 1)
  assert_equal(dirty_roles[1].name, "alpha-builder")
  assert_equal(dirty_roles[1].reason, "dirty")

  assert_true(runtime:close_mission("Alpha", { project_root = "/repo" }))
  assert_equal(state_data.projects["/codux-worktrees/alpha-builder"].workspaces["alpha-builder"].status, "inactive")
  assert_equal(state_data.projects["/codux-worktrees/alpha-builder"].workspaces["alpha-builder"].codex_status, "idle")
  assert_nil(state_data.projects["/codux-worktrees/alpha-builder"].workspaces["alpha-builder"].codex_mode)
  assert_equal(state_data.projects["/codux-worktrees/alpha-reviewer"].workspaces["alpha-reviewer"].status, "inactive")
  assert_equal(state_data.projects["/codux-worktrees/alpha-reviewer"].workspaces["alpha-reviewer"].mission_id, "mission:alpha")

  local deleted = {}
  runtime.delete_saved_workspace = function(_, entry)
    table.insert(deleted, entry.safe_name)
    return true
  end
  assert_true(runtime:delete_mission("Alpha", { project_root = "/repo" }))
  table.sort(deleted)
  assert_equal(table.concat(deleted, ","), "alpha-builder,alpha-reviewer")
end

do
  local calls = {}
  local notifications = {}
  local rendered_manager = false
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(notifications, message)
    end,
    render_workspace_manager = function()
      rendered_manager = true
    end,
  })
  function runtime:mission_for_name(root, name)
    assert_equal(root, "/repo")
    assert_equal(name, "Alpha")
    return {
      name = "Alpha",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_role = "Builder",
          permission_profile = "danger",
          project_root = "/codux-worktrees/alpha-builder",
        },
        {
          name = "alpha-reviewer",
          safe_name = "alpha-reviewer",
          mission_role = "Reviewer",
          project_root = "/codux-worktrees/alpha-reviewer",
        },
      },
    }
  end
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    assert_true(opts.allow_existing)
    assert_true(opts.require_existing)
    assert_nil(opts.initial_prompt)
    assert_equal(opts.initial_mode, "plan")
    if name == "alpha-builder" then
      assert_equal(opts.permission_profile, "danger")
    else
      assert_equal(opts.permission_profile, "auto")
    end
    if name == "alpha-reviewer" then
      return nil, "workspace failed"
    end
    return { name = name, window_id = "@1" }, nil
  end
  function runtime:ensure_workspace_plan_mode(workspace)
    assert_equal(workspace.name, "alpha-builder")
    return true, nil
  end

  assert_false(runtime:start_mission("Alpha", { project_root = "/repo" }))
  assert_equal(#calls, 2)
  assert_equal(calls[1].name, "alpha-builder")
  assert_equal(calls[1].opts.project_root, "/codux-worktrees/alpha-builder")
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_equal(calls[1].opts.permission_profile, "danger")
  assert_equal(calls[2].name, "alpha-reviewer")
  assert_equal(calls[2].opts.project_root, "/codux-worktrees/alpha-reviewer")
  assert_equal(calls[2].opts.initial_mode, "plan")
  assert_equal(calls[2].opts.permission_profile, "auto")
  assert_true(rendered_manager)
  assert_contains(table.concat(notifications, "\n"), "Failed to start Codux mission role Reviewer: workspace failed")
  assert_contains(table.concat(notifications, "\n"), "Started 1 roles in Codux mission Alpha; 1 failed")
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    render_workspace_manager = function() end,
  })
  function runtime:mission_for_name(root, name)
    assert_equal(root, "/repo")
    assert_equal(name, "Alpha")
    return {
      name = "Alpha",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_role = "Builder",
          project_root = "/repo",
          initial_mode = "execute",
        },
      },
    }
  end
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    return {
      name = name,
      safe_name = name,
      project_root = "/repo",
      window_id = "@1",
      status = "idle",
      initial_mode = opts.initial_mode,
      window_created = false,
    }, nil
  end
  function runtime:ensure_workspace_plan_mode(workspace)
    assert_equal(workspace.safe_name, "alpha-builder")
    table.insert(calls, { name = "ensure_plan" })
    return true, nil
  end

  assert_true(runtime:start_mission("Alpha", { project_root = "/repo" }))
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_equal(calls[2].name, "ensure_plan")
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    render_workspace_manager = function() end,
  })
  function runtime:mission_for_name(root, name)
    assert_equal(root, "/repo")
    assert_equal(name, "Alpha")
    return {
      name = "Alpha",
      objective = "Build it",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_role = "Builder",
          project_root = "/repo",
        },
      },
    }
  end
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    assert_true(opts.restart_inactive)
    return {
      name = name,
      safe_name = name,
      project_root = "/repo",
      window_id = "@1",
      status = "idle",
      initial_mode = opts.initial_mode,
    }, nil
  end
  function runtime:ensure_workspace_plan_mode(workspace)
    assert_equal(workspace.initial_mode, "plan")
    table.insert(calls, { name = "ensure_plan", workspace = workspace })
    return true, nil
  end
  function runtime:send_prompt_to_workspace(workspace, prompt)
    table.insert(calls, { name = "send_prompt", workspace = workspace, prompt = prompt })
    error("start_mission should not prompt roles on startup")
  end
  function runtime:switch_tmux_window(window_id)
    table.insert(calls, { name = "focus", window_id = window_id })
    return true
  end

  assert_true(runtime:start_mission("Alpha", {
    project_root = "/repo",
    restart_inactive = true,
    prompt_roles = true,
    focus_first = true,
  }))
  assert_equal(calls[1].name, "alpha-builder")
  assert_equal(calls[2].name, "ensure_plan")
  assert_equal(calls[3].name, "focus")
  assert_equal(calls[3].window_id, "@1")
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    notify = function() end,
  })
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    return {
      name = name,
      safe_name = name,
      project_root = "/repo",
      window_id = "@1",
      git_branch = "",
      initial_mode = opts.initial_mode,
    }, nil
  end
  function runtime:switch_tmux_window(window_id)
    table.insert(calls, { name = "focus", window_id = window_id })
    return true
  end

  assert_true(runtime:create_workspace("review", { initial_mode = "execute", initial_prompt = "start now" }))
  assert_equal(calls[1].name, "review")
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_nil(calls[1].opts.initial_prompt)
  assert_equal(calls[2].name, "focus")
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    notify = function() end,
  })
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    return {
      name = name,
      safe_name = name,
      project_root = opts.project_root,
      window_id = "@1",
      git_branch = "",
      initial_mode = opts.initial_mode,
    }, nil
  end
  function runtime:switch_tmux_window(window_id)
    table.insert(calls, { name = "focus", window_id = window_id })
    return true
  end

  assert_true(runtime:open_saved_workspace("review", "/repo"))
  assert_equal(calls[1].name, "review")
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_equal(calls[2].name, "focus")
end

do
  local calls = {}
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    render_workspace_manager = function() end,
  })
  function runtime:mission_for_name(root, name)
    assert_equal(root, "/repo")
    assert_equal(name, "Alpha")
    return {
      name = "Alpha",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_role = "Builder",
          project_root = "/repo",
        },
      },
    }
  end
  function runtime:prepare_workspace(name, opts)
    table.insert(calls, { name = name, opts = opts })
    return {
      name = name,
      safe_name = name,
      project_root = "/repo",
      window_id = "@1",
      status = "inactive",
      initial_mode = opts.initial_mode,
      window_created = true,
    }, nil
  end
  function runtime:ensure_workspace_plan_mode(workspace)
    assert_equal(workspace.safe_name, "alpha-builder")
    assert_true(workspace.window_created)
    table.insert(calls, { name = "ensure_plan" })
    return true, nil
  end

  assert_true(runtime:start_mission("Alpha", { project_root = "/repo" }))
  assert_equal(calls[1].opts.initial_mode, "plan")
  assert_equal(calls[2].name, "ensure_plan")
end

do
  local notifications = {}
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(notifications, message)
    end,
    render_workspace_manager = function() end,
  })
  function runtime:mission_for_name()
    return {
      name = "Alpha",
      roles = {
        {
          name = "alpha-builder",
          safe_name = "alpha-builder",
          mission_role = "Builder",
          project_root = "/repo",
        },
      },
    }
  end
  function runtime:prepare_workspace(_, opts)
    return {
      name = "alpha-builder",
      safe_name = "alpha-builder",
      project_root = "/repo",
      window_id = "@1",
      status = "idle",
      initial_mode = opts.initial_mode,
      window_created = false,
    }, nil
  end
  function runtime:ensure_workspace_plan_mode()
    return false, "still execute"
  end

  assert_false(runtime:start_mission("Alpha", { project_root = "/repo" }))
  assert_contains(table.concat(notifications, "\n"), "Failed to start Codux mission role Builder: still execute")
  assert_contains(table.concat(notifications, "\n"), "Started 0 roles in Codux mission Alpha; 1 failed")
end

do
  local runtime = runtime_mod.new({
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /codux-worktrees/review rev-list --count aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..dev/review" then
        return "2\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 0
      end
      return "", 1
    end,
  })

  local state = runtime:workspace_branch_state({
    project_root = "/codux-worktrees/review",
    workspace_kind = "worktree",
    worktree_branch = "dev/review",
    worktree_base = "main",
    worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  })
  assert_true(state.worktree)
  assert_equal(state.ahead_count, 2)
  assert_true(state.merged)

  local missing = runtime:workspace_branch_state({
    workspace_kind = "worktree",
    worktree_branch = "dev/review",
    worktree_base = "main",
  })
  assert_true(missing.worktree)
  assert_equal(missing.error, "missing base")
end

do
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function()
    error("fresh workspace should not prompt for deletion")
  end
  local state_data = workspace_state({}, {})
  state_data.projects = {
    ["/codux-worktrees/review"] = {
      workspaces = {
        review = review_workspace_record({
          project_root = "/codux-worktrees/review",
          workspace_kind = "worktree",
          git_common_dir = "/repo/.git",
          worktree_path = "/codux-worktrees/review",
          worktree_branch = "dev/review",
          worktree_base = "main",
          worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }),
      },
    },
  }
  local runtime = runtime_mod.new({
    state = {},
    store = {
      read_state = function()
        return state_data, nil
      end,
      instruction_file_records = function()
        return {}
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/review rev-list --count aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..dev/review" then
        return "0\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 0
      end
      return "", 1
    end,
  })

  local ok, err = pcall(function()
    assert_true(runtime:prompt_merged_workspaces("/repo"))
  end)
  vim.fn.confirm = old_confirm
  if not ok then
    error(err, 0)
  end
end

do
  local old_filereadable = vim.fn.filereadable
  local old_confirm = vim.fn.confirm
  vim.fn.filereadable = function()
    return 1
  end
  vim.fn.confirm = function()
    return 1
  end
  local state_data = workspace_state({}, {})
  state_data.projects = {
    ["/codux-worktrees/review"] = {
      workspaces = {
        review = review_workspace_record({
          project_root = "/codux-worktrees/review",
          workspace_kind = "worktree",
          git_common_dir = "/repo/.git",
          worktree_path = "/codux-worktrees/review",
          worktree_branch = "dev/review",
          worktree_base = "main",
          worktree_base_commit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        }),
      },
    },
  }
  local removed_worktree = false
  local deleted_branch = false
  local runtime = runtime_mod.new({
    state = {},
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = project_state,
      instruction_file_records = function()
        return {}
      end,
      instruction_file_path = function()
        return "/codux-worktrees/review/.agents/codux/review.md"
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    },
    notify = function() end,
    render_workspace_manager = function() end,
    close_workspace_manager = function() end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/review rev-list --count aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa..dev/review" then
        return "1\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 0
      end
      if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
        removed_worktree = true
        return "", 0
      end
      if command == "git --git-dir=/repo/.git branch -D dev/review" then
        deleted_branch = true
        return "", 0
      end
      return "", 1
    end,
  })

  local ok, err = pcall(function()
    assert_true(runtime:prompt_merged_workspaces("/repo"))
    assert_true(removed_worktree)
    assert_true(deleted_branch)
    assert_nil(state_data.projects["/codux-worktrees/review"].workspaces.review)
  end)
  vim.fn.filereadable = old_filereadable
  vim.fn.confirm = old_confirm
  if not ok then
    error(err, 0)
  end
end

do
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function()
    error("backfilled workspace should not prompt during the same dashboard refresh")
  end
  local state_data = workspace_state({}, {})
  state_data.projects = {
    ["/codux-worktrees/review"] = {
      workspaces = {
        review = review_workspace_record({
          project_root = "/codux-worktrees/review",
          workspace_kind = "worktree",
          git_common_dir = "/repo/.git",
          worktree_path = "/codux-worktrees/review",
          worktree_branch = "dev/review",
          worktree_base = "main",
        }),
      },
    },
  }
  local runtime = runtime_mod.new({
    state = {},
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = project_state,
      instruction_file_records = function()
        return {}
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /codux-worktrees/review merge-base dev/review main" then
        return "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", 0
      end
      return "", 1
    end,
  })

  local ok, err = pcall(function()
    assert_true(runtime:prompt_merged_workspaces("/repo"))
    assert_equal(
      state_data.projects["/codux-worktrees/review"].workspaces.review.worktree_base_commit,
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    )
  end)
  vim.fn.confirm = old_confirm
  if not ok then
    error(err, 0)
  end
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          stale = {
            name = "stale",
            safe_name = "stale",
            project_root = "/repo",
            tmux_window = "stale",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
          },
        },
      },
    },
  }
  local writes = 0
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        project_root = "/repo",
        safe_name = "stale",
        window_name = "stale",
      },
    },
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        return "@2\tother\n", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        writes = writes + 1
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
    },
  })

  assert_equal(runtime:sync_activity("working"), true)
  local record = state_data.projects["/repo"].workspaces.stale
  assert_equal(record.status, "inactive", "activity sync should not revive inactive window")
  assert_equal(record.codex_status, "idle")
  assert_equal(record.codex_mode, nil)
  assert_equal(writes, 1)
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
          },
          debug = {
            name = "debug",
            safe_name = "debug",
            project_root = "/repo",
            tmux_window = "debug",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
          },
        },
      },
    },
  }
  local messages = {}
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(messages, message)
    end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        return "@1\treview\n@2\tdebug\n", 0
      end
      if command == "tmux kill-window -t @1" or command == "tmux kill-window -t @2" then
        return "", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
    },
  })

  assert_true(runtime:close_all_saved_workspace_windows("/repo"))
  assert_equal(state_data.projects["/repo"].workspaces.review.status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "inactive")
  assert_nil(state_data.projects["/repo"].workspaces.debug.codex_mode)
  assert_contains(messages[#messages], "Closed 2 Codux workspaces")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
          },
          debug = {
            name = "debug",
            safe_name = "debug",
            project_root = "/repo",
            tmux_window = "debug",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        project_root = "/repo",
        safe_name = "debug",
        status = "active",
        codex_status = "working",
        codex_mode = "execute",
        tmux_target = "session:debug",
      },
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        return "@1\treview\n@2\tdebug\n", 0
      end
      if command == "tmux kill-window -t @1" then
        return "", 0
      end
      if command == "tmux kill-window -t @2" then
        return "", 1
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
    },
  })

  assert_false(runtime:close_all_saved_workspace_windows("/repo"))
  assert_equal(state_data.projects["/repo"].workspaces.review.status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "active")
  assert_equal(state_data.projects["/repo"].workspaces.debug.codex_status, "working")
  assert_equal(state_data.projects["/repo"].workspaces.debug.codex_mode, "execute")
  assert_equal(runtime.state.workspace.status, "active")
  assert_equal(runtime.state.workspace.codex_status, "working")
  assert_equal(runtime.state.workspace.codex_mode, "execute")
  assert_equal(runtime.state.workspace.tmux_target, "session:debug")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "idle",
            codex_status = "idle",
            codex_mode = "plan",
          },
          debug = {
            name = "debug",
            safe_name = "debug",
            project_root = "/repo",
            tmux_window = "debug",
            status = "active",
            codex_status = "working",
            codex_mode = "execute",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace = {
        project_root = "/repo",
        safe_name = "review",
        status = "idle",
        codex_status = "idle",
        codex_mode = "plan",
        tmux_target = "session:review",
      },
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        return "@1\treview\n@2\tdebug\n", 0
      end
      if command == "tmux kill-window -t @1" then
        return "", 0
      end
      if command == "tmux kill-window -t @2" then
        return "", 1
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
    },
  })

  assert_false(runtime:close_all_saved_workspace_windows("/repo"))
  assert_equal(state_data.projects["/repo"].workspaces.review.status, "inactive")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "active")
  assert_equal(runtime.state.workspace.status, "inactive")
  assert_equal(runtime.state.workspace.codex_status, "idle")
  assert_nil(runtime.state.workspace.codex_mode)
  assert_nil(runtime.state.workspace.tmux_target)
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            tmux_target = "session:review",
            status = "idle",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local messages = {}
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = nil
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      table.insert(messages, message)
    end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      return "", 1
    end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_true(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_nil(state_data.projects["/repo"].workspaces.debug.tmux_target)
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_window, "debug")
  assert_contains(messages[#messages], "Renamed Codux workspace to debug")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            tmux_target = "session:review",
            status = "inactive",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function()
      return "", 1
    end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_true(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_name = "review",
  }, "debug"))
  assert_nil(state_data.projects["/repo"].workspaces.debug.tmux_target)
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_window, "debug")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "inactive")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            tmux_target = "session:review",
            status = "idle",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = "/tmp/tmux,1,0"
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      return "", 1
    end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_true(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_target, "session:debug")
  assert_equal(state_data.projects["/repo"].workspaces.debug.tmux_window, "debug")
  assert_equal(state_data.projects["/repo"].workspaces.debug.status, "idle")
  vim.env.TMUX = old_tmux
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "idle",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local commands = {}
  local notification
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      notification = message
    end,
    system = function(args)
      local command = table.concat(args, " ")
      table.insert(commands, command)
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux rename-window -t @1 review" then
        return "", 0
      end
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function()
        return false, "write failed"
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return nil
      end,
    },
  })

  assert_false(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_equal(state_data.projects["/repo"].workspaces.review.name, "review")
  assert_nil(state_data.projects["/repo"].workspaces.debug)
  assert_contains(table.concat(commands, "\n"), "tmux rename-window -t @1 debug")
  assert_contains(table.concat(commands, "\n"), "tmux rename-window -t @1 review")
  assert_equal(notification, "write failed")
end

do
  local state_data = {
    projects = {
      ["/codux-worktrees/review"] = {
        workspaces = {
          review = review_workspace_record({
            name = "review",
            safe_name = "review",
            project_root = "/codux-worktrees/review",
            tmux_window = "review",
            status = "idle",
            codex_status = "idle",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_path = "/codux-worktrees/review",
            worktree_branch = "dev/review",
            git_branch = "dev/review",
          }),
        },
      },
    },
  }
  local commands = {}
  local notification
  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function(message)
      notification = message
    end,
    system = function(args)
      local command = table.concat(args, " ")
      table.insert(commands, command)
      if command == "git -C /codux-worktrees/review show-ref --verify --quiet refs/heads/dev/debug" then
        return "", 1
      end
      if command == "git -C /codux-worktrees/review worktree move /codux-worktrees/review /codux-worktrees/debug" then
        return "", 0
      end
      if command == "git -C /codux-worktrees/debug branch -m dev/review dev/debug" then
        return "", 0
      end
      if command == "tmux rename-window -t @1 debug" then
        return "", 0
      end
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      if command == "tmux rename-window -t @1 review" then
        return "", 0
      end
      if command == "git -C /codux-worktrees/debug branch -m dev/debug dev/review" then
        return "", 0
      end
      if command == "git -C /codux-worktrees/debug worktree move /codux-worktrees/debug /codux-worktrees/review" then
        return "", 0
      end
      return "", 1
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function()
        return false, "write failed"
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = project_state,
      instruction_file_path = function(_, root, safe_name)
        return root .. "/.agents/codux/" .. safe_name .. ".md"
      end,
    },
  })

  assert_false(runtime:rename_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/codux-worktrees/review",
    window_id = "@1",
    window_name = "review",
  }, "debug"))
  assert_equal(state_data.projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
  assert_nil(state_data.projects["/codux-worktrees/debug"])
  local command_text = table.concat(commands, "\n")
  assert_contains(command_text, "git -C /codux-worktrees/review worktree move /codux-worktrees/review /codux-worktrees/debug")
  assert_contains(command_text, "git -C /codux-worktrees/debug branch -m dev/debug dev/review")
  assert_contains(command_text, "git -C /codux-worktrees/debug worktree move /codux-worktrees/debug /codux-worktrees/review")
  assert_equal(notification, "write failed")
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          old = {
            name = "old",
            safe_name = "old",
            project_root = "/repo",
            tmux_window = "old",
            status = "inactive",
            codex_status = "idle",
            codex_session_captured_at = "2026-06-30T12:00:00Z",
          },
          other = {
            name = "other",
            safe_name = "other",
            project_root = "/repo",
            tmux_window = "other",
            status = "inactive",
            codex_status = "idle",
            created_at = "2026-06-01T12:00:00Z",
          },
        },
      },
    },
  }
  local runtime = runtime_mod.new({
    state = {},
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      instruction_file_records = function()
        return {}
      end,
    },
  })

  local entries = runtime:entries_for_project("/repo")
  local by_name = {}
  for _, entry in ipairs(entries) do
    by_name[entry.name] = entry
  end

  assert_equal(by_name.old.codex_session_captured_at, "2026-06-30T12:00:00Z")
  assert_equal(workspace_ui.activity_timestamp(by_name.old), "2026-06-30T12:00:00Z")
  assert_equal(workspace_ui.sort_entries(entries, "status_recent")[1].name, "old")
end

do
  with_filereadable(1, function()
    local delete_calls = 0
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record(),
      }),
      write_state = function()
        return false, "write failed"
      end,
      delete_instruction_file = function()
        delete_calls = delete_calls + 1
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store)

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }))
    assert_equal(delete_calls, 0, "instruction file should not be deleted when state write fails")
  end)
end

do
  with_filereadable(1, function()
    local state_data = workspace_state({
      review = review_workspace_record(),
    }, {
      updated_at = "before",
    })
    local write_count = 0
    local killed = false
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        write_count = write_count + 1
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return false, "delete instruction failed"
      end,
    })
    local runtime = workspace_delete_runtime(store.store)
    runtime.kill_tmux_window_deferred = function()
      killed = true
    end

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      window_id = "@1",
    }))
    assert_equal(write_count, 2, "failed instruction delete should restore prior state")
    assert_equal(state_data.projects["/repo"].workspaces.review.name, "review")
    assert_false(killed, "tmux window should not be killed when delete is rolled back")
  end)
end

do
  with_filereadable(1, function()
    local delete_calls = 0
    local killed = false
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record(),
      }),
      delete_instruction_file = function(_, root, safe_name)
        delete_calls = delete_calls + 1
        assert_equal(root, "/repo")
        assert_equal(safe_name, "review")
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store)
    runtime.kill_tmux_window_deferred = function(_, window_id)
      killed = window_id == "@1"
    end

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
      window_id = "@1",
    }))
    assert_nil(store.state_data().projects["/repo"].workspaces.review)
    assert_equal(delete_calls, 1)
    assert_true(killed)
  end)
end

do
  with_filereadable(1, function()
    local deleted_instruction = false
    local removed_worktree = false
    local deleted_branch = false
    local closed = false
    local state_data = {
      projects = {
        ["/codux-worktrees/review"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/codux-worktrees/review",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function(_, root, safe_name)
        deleted_instruction = root == "/codux-worktrees/review" and safe_name == "review"
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      close_workspace_manager = function()
        closed = true
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/codux-worktrees/review",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_true(deleted_instruction)
    assert_true(removed_worktree)
    assert_true(deleted_branch)
    assert_true(closed)
    assert_nil(state_data.projects["/codux-worktrees/review"].workspaces.review)
  end)
end

do
  with_filereadable(1, function()
    local deleted_instruction = false
    local removed_worktree = false
    local state_data = {
      projects = {
        ["/codux-worktrees/review"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/codux-worktrees/review",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function()
        return false, "write failed"
      end,
      delete_instruction_file = function()
        deleted_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/codux-worktrees/review",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_false(deleted_instruction)
    assert_false(removed_worktree)
    assert_equal(state_data.projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
  end)
end

do
  with_filereadable(1, function()
    local notification
    local rendered = false
    local closed = false
    local attempted_branch_delete = false
    local state_data = {
      projects = {
        ["/codux-worktrees/review"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/codux-worktrees/review",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      notify = function(message)
        notification = message
      end,
      render_workspace_manager = function()
        rendered = true
      end,
      close_workspace_manager = function()
        closed = true
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          return "fatal: worktree is locked\n", 1
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          attempted_branch_delete = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/codux-worktrees/review",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_contains(notification, "Failed to remove Git worktree /codux-worktrees/review")
    assert_contains(notification, "fatal: worktree is locked")
    assert_true(rendered)
    assert_false(closed)
    assert_false(attempted_branch_delete)
    assert_equal(state_data.projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
  end)
end

do
  with_filereadable(1, function()
    local notification
    local rendered = false
    local closed = false
    local removed_worktree = false
    local state_data = {
      projects = {
        ["/codux-worktrees/review"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/codux-worktrees/review",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      notify = function(message)
        notification = message
      end,
      render_workspace_manager = function()
        rendered = true
      end,
      close_workspace_manager = function()
        closed = true
      end,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          return "fatal: branch delete failed\n", 1
        end
        return "", 1
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/codux-worktrees/review",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_true(removed_worktree)
    assert_contains(notification, "Failed to delete Git branch dev/review")
    assert_contains(notification, "fatal: branch delete failed")
    assert_true(rendered)
    assert_false(closed)
    assert_nil(state_data.projects["/codux-worktrees/review"].workspaces.review)
  end)
end

do
  with_filereadable(1, function()
    local deleted_branch = false
    local state_data = {
      projects = {
        ["/codux-worktrees/review"] = {
          workspaces = {
            review = review_workspace_record({
              project_root = "/codux-worktrees/review",
              workspace_kind = "worktree",
              git_common_dir = "/repo/.git",
              worktree_path = "/codux-worktrees/review",
              worktree_branch = "dev/review",
              worktree_base = "main",
            }),
          },
        },
      },
    }
    local store = workspace_store({
      state_data = state_data,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      delete_instruction_file = function()
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      system = function(args)
        local command = table.concat(args, " ")
        if command == "git --git-dir=/repo/.git worktree remove --force /codux-worktrees/review" then
          return "", 0
        end
        if command == "git --git-dir=/repo/.git branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/codux-worktrees/review",
      workspace_kind = "worktree",
      git_common_dir = "/repo/.git",
      worktree_path = "/codux-worktrees/review",
      worktree_branch = "dev/review",
    }))
    assert_true(deleted_branch)
    assert_nil(state_data.projects["/codux-worktrees/review"].workspaces.review)
  end)
end

do
  local state_data = {
    projects = {
      ["/codux-worktrees/alpha-research"] = {
        workspaces = {
          ["alpha-research"] = review_workspace_record({
            name = "alpha-research",
            safe_name = "alpha-research",
            project_root = "/codux-worktrees/alpha-research",
            workspace_kind = "worktree",
            git_common_dir = "/repo/.git",
            worktree_branch = "dev/alpha-research",
            mission_id = "mission:alpha",
            mission_name = "Alpha",
            mission_role = "Research",
            mission_objective = "Build it",
          }),
        },
      },
    },
  }
  local runtime = runtime_mod.new({
    store = {
      read_state = function()
        return state_data, nil
      end,
      instruction_file_records = function()
        return {}
      end,
    },
    system = function(args)
      local command = table.concat(args, " ")
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      return "", 1
    end,
  })

  local entries = runtime:entries_for_project("/repo")
  local missions = mission_mod.group_entries(entries)
  local mission = assert(mission_mod.find_mission(missions, "Alpha"))
  assert_equal(#mission.roles, 1)
  assert_equal(mission.roles[1].safe_name, "alpha-research")
  assert_equal(mission.roles[1].mission_role, "Research")
end

do
  with_filereadable(1, function()
    local delete_calls = 0
    local store = workspace_store({
      state_data = workspace_state({}),
      delete_instruction_file = function(_, root, safe_name)
        delete_calls = delete_calls + 1
        assert_equal(root, "/repo")
        assert_equal(safe_name, "review")
        return true, nil
      end,
    })
    local runtime = workspace_delete_runtime(store.store)

    assert_true(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }))
    assert_equal(delete_calls, 1)
  end)
end

do
  with_filereadable(1, function()
    local closed = false
    local store = workspace_store({
      state_data = workspace_state({}),
      delete_instruction_file = function()
        return false, "delete instruction failed"
      end,
    })
    local runtime = workspace_delete_runtime(store.store, {
      close_workspace_manager = function()
        closed = true
      end,
    })

    assert_false(runtime:delete_saved_workspace({
      name = "review",
      safe_name = "review",
      project_root = "/repo",
    }))
    assert_false(closed, "instruction-only delete should fail when instruction file remains")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local created = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("remote_workspace_status", 1, true) then
          return "ready\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(error_message)
    assert_equal(workspace.project_root, "/codux-worktrees/review")
    assert_equal(workspace.workspace_kind, "worktree")
    assert_equal(workspace.worktree_branch, "dev/review")
    assert_equal(workspace.worktree_base, "main")
    assert_equal(workspace.worktree_base_commit, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    assert_equal(workspace.git_common_dir, "/repo/.git")
    assert_equal(workspace.target_path, "/codux-worktrees/review/file.lua")
    assert_contains(table.concat(commands, "\n"), "git -C /repo status --porcelain")
    assert_contains(table.concat(commands, "\n"), "git -C /repo worktree add -b dev/review /codux-worktrees/review main")
    assert_equal(store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev/review")
    assert_equal(
      store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_base_commit,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    )
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local created = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/mission-builder main" then
          return "", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\tmission-builder\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("remote_workspace_status", 1, true) then
          return "ready\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("mission-builder", {
      resolved_instruction = "builder instructions",
      initial_prompt = "start building",
      initial_mode = "plan",
      permission_profile = "auto",
      mission_id = "mission:mission",
      mission_name = "Mission",
      mission_role = "Builder",
      mission_objective = "Build it",
    })
    assert_nil(error_message)
    assert_equal(workspace.permission_profile, "auto")
    assert_equal(workspace.status, "active")
    assert_equal(workspace.codex_status, "working")
    assert_contains(table.concat(commands, "\n"), "start building")
    local record = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(record.permission_profile, "auto")
    assert_equal(record.mission_id, "mission:mission")
    assert_equal(record.mission_role, "Builder")
    assert_equal(record.mission_objective, "Build it")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local killed = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/mission-builder main" then
          return "", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\tmission-builder\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("remote_workspace_status", 1, true) then
          return "not_running\n", 0
        end
        if command == "tmux kill-window -t @1" then
          killed = true
          return "", 0
        end
        if command == "git -C /repo worktree remove --force /codux-worktrees/mission-builder" then
          removed_worktree = true
          return "", 0
        end
        if command == "git -C /repo branch -D dev/mission-builder" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("mission-builder", {
      resolved_instruction = "builder instructions",
      initial_prompt = "start building",
      initial_mode = "plan",
      permission_profile = "auto",
      mission_id = "mission:mission",
      mission_name = "Mission",
      mission_role = "Builder",
      launch_verify_attempts = 1,
    })

    assert_nil(error_message)
    assert_equal(workspace.safe_name, "mission-builder")
    assert_false(killed)
    local record = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(record.initial_mode, "plan")
    assert_equal(record.permission_profile, "auto")
    assert_equal(record.mission_id, "mission:mission")
    assert_equal(record.codex_mode, "plan")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local killed = false
    local removed_worktree = false
    local deleted_branch = false
    local deleted_instruction = false
    local store = workspace_store({
      delete_instruction_file = function(_, root, safe_name)
        deleted_instruction = root == "/codux-worktrees/mission-builder" and safe_name == "mission-builder"
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/mission-builder main" then
          return "", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\tmission-builder\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command == "tmux kill-window -t @1" then
          killed = true
          return "", 0
        end
        if command == "git -C /repo worktree remove --force /codux-worktrees/mission-builder" then
          removed_worktree = true
          return "", 0
        end
        if command == "git -C /repo branch -D dev/mission-builder" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("mission-builder", {
      resolved_instruction = "builder instructions",
      initial_prompt = "start building",
      permission_profile = "auto",
      mission_id = "mission:mission",
      mission_name = "Mission",
      mission_role = "Builder",
      launch_verify_attempts = 1,
    })

    assert_nil(workspace)
    assert_equal(error_message, "workspace is not reachable")
    assert_true(killed)
    assert_true(deleted_instruction)
    assert_true(removed_worktree)
    assert_true(deleted_branch)
    assert_nil(store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"])
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local state_data = {
      projects = {
        ["/codux-worktrees/mission-builder"] = {
          workspaces = {
            ["mission-builder"] = review_workspace_record({
              name = "mission-builder",
              safe_name = "mission-builder",
              project_root = "/codux-worktrees/mission-builder",
              workspace_kind = "worktree",
            }),
          },
        },
      },
    }
    local runtime = workspace_prepare_runtime({
      store = workspace_store({
        state_data = state_data,
      }).store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        return "", 1
      end,
    })
    local mission = assert(mission_mod.plan("Mission", "Build it", {
      roles = {
        { name = "Builder" },
      },
    }))

    local ok, error_message = runtime:preflight_mission(mission)
    assert_false(ok)
    assert_equal(error_message, "workspace already exists: mission-builder")
    assert_equal(table.concat(commands, "\n"):find("worktree add", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local windows = {}
    local next_window_id = 1
    local store = workspace_store({
      instruction_file_path = function(_, root, safe_name)
        return root .. "/.agents/codux/" .. safe_name .. ".md"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          local lines = {}
          for name, id in pairs(windows) do
            table.insert(lines, id .. "\t" .. name)
          end
          table.sort(lines)
          return table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""), 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-architect" then
          return "", 1
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev/mission-architect /codux-worktrees/mission-architect main" then
          return "", 0
        end
        if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/mission-builder main" then
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          local name = command:find("mission%-architect") and "mission-architect" or "mission-builder"
          windows[name] = "@" .. tostring(next_window_id)
          next_window_id = next_window_id + 1
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command == "tmux list-panes -t @2 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command:find("remote_workspace_status", 1, true) then
          return "ready\n", 0
        end
        return "", 1
      end,
    })

    local mission, error_message = mission_mod.plan("Mission", "Build it", {
      roles = {
        { name = "Architect", safe_name = "architect", focus = "Design it" },
        { name = "Builder", safe_name = "builder", focus = "Build it" },
      },
    })
    assert_nil(error_message)
    assert_true(runtime:create_mission(mission))

    local architect =
      store.state_data().projects["/codux-worktrees/mission-architect"].workspaces["mission-architect"]
    local builder = store.state_data().projects["/codux-worktrees/mission-builder"].workspaces["mission-builder"]
    assert_equal(architect.permission_profile, "auto")
    assert_equal(builder.permission_profile, "auto")
    assert_equal(architect.mission_id, "mission:mission")
    assert_equal(builder.mission_id, "mission:mission")
    assert_equal(architect.mission_role, "Architect")
    assert_equal(builder.mission_role, "Builder")
    assert_equal(architect.mission_objective, "Build it")
    assert_equal(builder.mission_objective, "Build it")
    assert_equal(architect.initial_mode, "plan")
    assert_equal(builder.initial_mode, "plan")
    assert_equal(architect.codex_status, "idle")
    assert_equal(builder.codex_status, "idle")
    assert_nil(architect.codex_mode)
    assert_nil(builder.codex_mode)
    assert_contains(table.concat(commands, "\n"), "git -C /repo status --porcelain")
    assert_contains(table.concat(commands, "\n"), "--listen")
    assert_equal(table.concat(commands, "\n"):find("Start your Mission Control role now.", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local runtime = workspace_prepare_runtime({})
    local lua = runtime:bootstrap_lua({
      name = "mission-builder",
      safe_name = "mission-builder",
      project_root = "/codux-worktrees/mission-builder",
      mission_id = "mission:mission",
      mission_name = "Mission",
      mission_role = "Builder",
      mission_objective = "Build it",
      nvim_server = "/tmp/codux/mission-builder.sock",
      initial_mode = "plan",
    })

    assert_contains(lua, 'mission_id="mission:mission"')
    assert_contains(lua, 'mission_name="Mission"')
    assert_contains(lua, 'mission_role="Builder"')
    assert_contains(lua, 'mission_objective="Build it"')
    assert_contains(lua, 'nvim_server="/tmp/codux/mission-builder.sock"')
    assert_contains(lua, 'initial_mode="plan"')
  end)
end

do
  with_workspace_prepare_env(function()
    local written = {}
    local notifications = {}
    local state_data = workspace_state({
      ["mission-architect"] = review_workspace_record({
        name = "mission-architect",
        safe_name = "mission-architect",
        mission_id = "mission:mission",
        mission_name = "Mission",
        mission_role = "Architect",
        mission_objective = "Build it",
        resolved_instruction = mission_mod.role_instruction("Mission", "Build it", {
          name = "Architect",
          safe_name = "architect",
          focus = "Design it",
        }),
      }),
      ["mission-builder"] = review_workspace_record({
        name = "mission-builder",
        safe_name = "mission-builder",
        mission_id = "mission:mission",
        mission_name = "Mission",
        mission_role = "Builder",
        mission_objective = "Build it",
        resolved_instruction = mission_mod.role_instruction("Mission", "Build it", {
          name = "Builder",
          safe_name = "builder",
          focus = "Build it",
        }),
      }),
    })
    local store = workspace_store({
      state_data = state_data,
      write_instruction_file = function(_, root, safe_name, instruction)
        written[root .. "/" .. safe_name] = instruction
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      notify = function(message)
        table.insert(notifications, message)
      end,
    })

    local ok, error_message = runtime:update_mission_objective("Mission", "Ship the dashboard")
    assert_nil(error_message)
    assert_true(ok)
    local architect = store.state_data().projects["/repo"].workspaces["mission-architect"]
    local builder = store.state_data().projects["/repo"].workspaces["mission-builder"]
    assert_equal(architect.mission_objective, "Ship the dashboard")
    assert_equal(builder.mission_objective, "Ship the dashboard")
    assert_contains(architect.resolved_instruction, "Ship the dashboard")
    assert_contains(builder.resolved_instruction, "Ship the dashboard")
    assert_contains(written["/repo/mission-architect"], "Mission: Mission")
    assert_contains(written["/repo/mission-builder"], "Role focus:")
    assert_contains(notifications[#notifications], "Updated Codux mission Mission objective for 2 roles")
  end)
end

do
  with_workspace_prepare_env(function()
    local runtime = workspace_prepare_runtime({
      store = workspace_store().store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        return "", 1
      end,
    })

    local ok, error_message = runtime:preflight_mission({
      roles = {
        { workspace_name = "mission-role!" },
        { workspace_name = "mission-role@" },
      },
    })
    assert_false(ok)
    assert_equal(error_message, "Duplicate mission workspace: mission-role")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local created = false
    local store = workspace_store()
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
          return "", 0
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1" then
          return "", 1
        end
        if command == "git -C /repo show-ref --verify --quiet refs/heads/dev1/review" then
          return "", 1
        end
        if command == "git -C /repo worktree add -b dev1/review /codux-worktrees/review main" then
          return "", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(error_message)
    assert_equal(workspace.worktree_branch, "dev1/review")
    assert_contains(table.concat(commands, "\n"), "git -C /repo worktree add -b dev1/review /codux-worktrees/review main")
    assert_equal(store.state_data().projects["/codux-worktrees/review"].workspaces.review.worktree_branch, "dev1/review")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local runtime = workspace_prepare_runtime({
      store = workspace_store().store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "git -C /repo status --porcelain" then
          return " M file.lua\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_equal(error_message, "current branch must be clean before creating a Codux workspace")
    assert_equal(table.concat(commands, "\n"):find("worktree add", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    local wrote_instruction = false
    local store = workspace_store({
      read_instruction_file = function()
        return nil
      end,
      write_instruction_file = function()
        wrote_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          return "", 1
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_contains(error_message, "Failed to create tmux window")
    assert_false(wrote_instruction, "instruction file should not be written when tmux creation fails")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local killed = false
    local deleted_instruction = false
    local removed_worktree = false
    local deleted_branch = false
    local store = workspace_store({
      write_state = function()
        return false, "state write failed"
      end,
      read_instruction_file = function()
        return nil
      end,
      delete_instruction_file = function()
        deleted_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        if command == "tmux kill-window -t @1" then
          killed = true
          return "", 0
        end
        if command == "git -C /repo worktree remove --force /codux-worktrees/review" then
          removed_worktree = true
          return "", 0
        end
        if command == "git -C /repo branch -D dev/review" then
          deleted_branch = true
          return "", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "review the backend",
    })
    assert_nil(workspace)
    assert_equal(error_message, "state write failed")
    assert_true(killed, "new tmux window should be cleaned up when state write fails")
    assert_true(deleted_instruction, "new instruction file should be cleaned up when state write fails")
    assert_true(removed_worktree, "new git worktree should be cleaned up when state write fails")
    assert_true(deleted_branch, "new git branch should be cleaned up when state write fails")
  end)
end

do
  with_workspace_prepare_env(function()
    local created_window = false
    local wrote_instruction = false
    local wrote_state = false
    local store = workspace_store({
      write_state = function()
        wrote_state = true
        return true, nil
      end,
      read_instruction_file = function()
        return "existing instructions"
      end,
      write_instruction_file = function()
        wrote_instruction = true
        return true, nil
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created_window = true
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      resolved_instruction = "new instructions",
    })
    assert_nil(workspace)
    assert_equal(error_message, "workspace already exists")
    assert_false(created_window, "duplicate instruction-only workspace should not create tmux window")
    assert_false(wrote_instruction, "duplicate instruction-only workspace should not write instruction file")
    assert_false(wrote_state, "duplicate instruction-only workspace should not write state")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local store = workspace_store({
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
    })
    assert_nil(error_message)
    assert_equal(workspace.safe_name, "review")
    assert_equal(workspace.resolved_instruction, "existing instructions")
    assert_false(workspace.open_visible)
    assert_equal(store.state_data().projects["/repo"].workspaces.review.resolved_instruction, "existing instructions")
  end)
end

do
  with_workspace_prepare_env(function()
    local target_path, target_type = runtime_mod.normalize_workspace_target("/repo", "directory", "/fallback")
    assert_equal(target_path, "/repo")
    assert_equal(target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local commands = {}
    local killed = false
    local created = false
    local store = workspace_store({
      state_data = {
        projects = {
          ["/repo"] = {
            workspaces = {
              review = review_workspace_record({
                name = "review",
                safe_name = "review",
                project_root = "/repo",
                tmux_window = "review",
                nvim_server = "/tmp/stale-review.sock",
              }),
            },
          },
        },
      },
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        table.insert(commands, command)
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@2\treview\n", 0
          end
          if not killed then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "bash\n", 0
        end
        if command == "tmux kill-window -t @1" then
          killed = true
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          return "", 0
        end
        if command == "tmux list-panes -t @2 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
      restart_inactive = true,
    })
    assert_nil(error_message)
    assert_equal(workspace.window_id, "@2")
    assert_contains(workspace.nvim_server, "/codux/ws-review-repo-")
    assert_true(killed)
    assert_true(created)
    local command_text = table.concat(commands, "\n")
    assert_contains(command_text, "tmux kill-window -t @1")
    assert_contains(command_text, "--listen")
    assert_contains(command_text, workspace.nvim_server)
    assert_equal(command_text:find("/tmp/stale-review.sock", 1, true), nil)
  end)
end

do
  with_workspace_prepare_env(function()
    assert_false(runtime_mod.target_path_exists("health://"))
    assert_false(runtime_mod.target_path_exists("codux://codex"))
    assert_false(runtime_mod.target_path_exists("term://terminal"))

    local target_path, target_type = runtime_mod.normalize_workspace_target("health://", "file", "/repo")
    assert_equal(target_path, "/repo")
    assert_equal(target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local runtime = workspace_prepare_runtime({
      current_target = function()
        return { path = "health://", type = "file" }
      end,
      current_buffer_name = function()
        return "health://"
      end,
      git_root_for = function(path)
        assert_equal(path, "/repo")
        return "/repo"
      end,
      git_branch_for = function(path)
        assert_equal(path, "/repo")
        return "main"
      end,
    })

    local context = runtime:target_context()
    assert_nil(context.path)
    assert_equal(context.directory, "/repo")
    assert_equal(context.root, "/repo")
    assert_equal(context.branch, "main")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local new_window_command
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record({
          resolved_instruction = "existing instructions",
          target_path = "/repo/neo-tree filesystem [1]",
          target_type = "file",
          initial_mode = "execute",
        }),
      }),
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          new_window_command = command
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
      initial_mode = "plan",
    })
    assert_nil(error_message)
    assert_equal(workspace.initial_mode, "plan")
    assert_equal(workspace.target_path, "/repo")
    assert_equal(workspace.target_type, "directory")
    assert_contains(new_window_command, "'nvim' --listen")
    assert_contains(new_window_command, 'initial_mode="plan"')
    assert_contains(new_window_command, "/codux/ws-review-repo-")
    assert_contains(new_window_command, "' '.'")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.initial_mode, "plan")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_path, "/repo")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record({
          target_path = "/repo/file.lua",
          target_type = "file",
        }),
      }),
    })
    local runtime = workspace_prepare_runtime({
      state = {
        workspace = {
          project_root = "/repo",
          safe_name = "review",
          target_path = "/repo/file.lua",
          target_type = "file",
          git_branch = "main",
        },
      },
      store = store.store,
      current_target = function()
        return nil
      end,
      current_buffer_name = function()
        return "/repo/neo-tree filesystem [1]"
      end,
    })

    assert_true(runtime:sync_target("BufEnter", function()
      return "neo-tree"
    end))
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_path, "/repo")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_type, "directory")
    assert_equal(runtime.state.workspace.target_path, "/repo")
    assert_equal(runtime.state.workspace.target_type, "directory")
  end)
end

do
  with_workspace_prepare_env(function()
    local created = false
    local new_window_command
    local store = workspace_store({
      state_data = workspace_state({
        review = review_workspace_record({
          resolved_instruction = "existing instructions",
          target_path = "/repo/file.lua",
          target_type = "file",
        }),
      }),
      read_instruction_file = function()
        return "existing instructions"
      end,
    })
    local runtime = workspace_prepare_runtime({
      store = store.store,
      system = function(args)
        local command = table.concat(args, " ")
        if command == "tmux display-message -p #S" then
          return "session\n", 0
        end
        if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
          if created then
            return "@1\treview\n", 0
          end
          return "", 0
        end
        if command:find("tmux new%-window", 1, false) == 1 then
          created = true
          new_window_command = command
          return "", 0
        end
        if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
          return "nvim\n", 0
        end
        return "", 1
      end,
    })

    local workspace, error_message = runtime:prepare_workspace("review", {
      allow_existing = true,
      require_existing = true,
      project_root = "/repo",
    })
    assert_nil(error_message)
    assert_equal(workspace.target_path, "/repo/file.lua")
    assert_equal(workspace.target_type, "file")
    assert_contains(new_window_command, "'nvim' --listen")
    assert_contains(new_window_command, "/codux/ws-review-repo-")
    assert_contains(new_window_command, "' '/repo/file.lua'")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_path, "/repo/file.lua")
    assert_equal(store.state_data().projects["/repo"].workspaces.review.target_type, "file")
  end)
end

print("workspace_runtime_spec.lua: ok")
