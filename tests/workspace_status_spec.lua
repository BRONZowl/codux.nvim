package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

if type(vim) ~= "table" then
  local function deepcopy(value)
    if type(value) ~= "table" then
      return value
    end
    local copy = {}
    for key, item in pairs(value) do
      copy[key] = deepcopy(item)
    end
    return copy
  end

  vim = {
    deepcopy = deepcopy,
    env = {},
    o = {
      columns = 120,
      lines = 40,
      cmdheight = 1,
    },
    fn = {
      confirm = function()
        return 1
      end,
      fnamemodify = function(value, modifier)
        if modifier == ":t" then
          return tostring(value or ""):match("[^/]+$") or tostring(value or "")
        end
        return tostring(value or "")
      end,
      strcharpart = function(value, start, length)
        value = tostring(value or "")
        start = tonumber(start) or 0
        if length == nil then
          return value:sub(start + 1)
        end
        return value:sub(start + 1, start + length)
      end,
      strchars = function(value)
        return #tostring(value or "")
      end,
      strdisplaywidth = function(value)
        return #tostring(value or "")
      end,
    },
    log = {
      levels = {
        ERROR = 4,
        WARN = 3,
      },
    },
    loop = {
      cwd = function()
        return "/repo"
      end,
    },
  }
end

local runtime_mod = require("codux.workspace_runtime")
local workspace_ui = require("codux.workspace_ui")
local manager_mod = require("codux.workspace_manager")
local terminal_mod = require("codux.terminal")

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function assert_nil(actual, message)
  if actual ~= nil then
    error((message or "assertion failed") .. ": expected nil, got " .. tostring(actual), 2)
  end
end

local function assert_true(actual, message)
  if actual ~= true then
    error((message or "assertion failed") .. ": expected true, got " .. tostring(actual), 2)
  end
end

local function assert_false(actual, message)
  if actual ~= false then
    error((message or "assertion failed") .. ": expected false, got " .. tostring(actual), 2)
  end
end

local function assert_contains(value, expected, message)
  if not tostring(value or ""):find(expected, 1, true) then
    error((message or "assertion failed") .. ": expected " .. tostring(value) .. " to contain " .. tostring(expected), 2)
  end
end

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
  assert_equal(workspace_ui.manager_mode_label({ status = "inactive", codex_mode = "plan" }), "--")
  assert_equal(workspace_ui.manager_mode_label({ status = "idle", codex_mode = "plan" }), "plan")
end

do
  local actions = workspace_ui.manager_action_items()
  local by_key = {}
  local labels_by_key = {}
  for _, action in ipairs(actions) do
    by_key[action.key] = action.action
    labels_by_key[action.key] = action.label
  end

  assert_nil(by_key.o)
  assert_equal(by_key.r, "rename")
  assert_equal(by_key.e, "edit_instructions")
  assert_equal(by_key.x, "close_window")
  assert_equal(by_key.X, "close_all_windows")
  assert_equal(by_key.d, "delete")
  assert_nil(by_key.h)
  assert_contains(workspace_ui.manager_action_line(actions[1], 40), "Rename Workspace")
  assert_equal(labels_by_key.X, "Close All Workspaces")
end

do
  local footer = workspace_ui.footer_line(workspace_ui.manager_footer_segments({}, 200))
  assert_contains(footer, "tab search/list")
  assert_contains(footer, "m menu")
  assert_contains(footer, "h doctor")
  assert_contains(footer, "enter open")
  assert_equal(footer:find("s search", 1, true), nil)
  assert_equal(footer:find("r rename", 1, true), nil)
  assert_equal(footer:find("x close", 1, true), nil)
  assert_equal(footer:find("d delete", 1, true), nil)
end

do
  local entries = workspace_ui.sort_entries({
    { name = "Backend Debug", status = "active", last_activity_at = "2026-06-30T12:00:00Z" },
    { name = "Code Review", status = "question", last_activity_at = "2026-06-29T12:00:00Z" },
    { name = "Architecture", status = "inactive", last_activity_at = "2026-06-30T13:00:00Z" },
  }, "status_recent")

  assert_equal(entries[1].name, "Code Review")
  assert_equal(entries[2].name, "Backend Debug")
  assert_equal(entries[3].name, "Architecture")

  local matches = workspace_ui.fuzzy_workspace_filter(entries, "cod")
  assert_equal(#matches, 1)
  assert_equal(matches[1].name, "Code Review")
end

do
  local bound = {}
  local controller = manager_mod.new({
    state = {},
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, mode, lhs, _rhs, desc)
      if mode == "n" then
        bound[lhs] = desc
      end
    end,
  })

  controller:bind_commands(12)

  assert_equal(bound.m, "Open Codux Workspace Menu")
  assert_equal(bound.h, "Run Codux Doctor")
  assert_equal(bound["<CR>"], "Open Codux Workspace")
  assert_equal(bound["<Tab>"], "Search/List Codux Workspaces")
  assert_nil(bound.s)
  assert_nil(bound.r)
  assert_nil(bound.x)
  assert_nil(bound.d)
end

do
  local current_win = 20
  local cursors = {}
  local controller = manager_mod.new({
    state = {
      workspace_manager_win = 10,
      workspace_manager_search_win = 20,
      workspace_manager_items = {
        { name = "Backend Debug" },
        { name = "Code Review" },
      },
      workspace_manager_best_match_index = 2,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20
    end,
    get_current_win = function()
      return current_win
    end,
    set_current_win = function(win)
      current_win = win
      return true
    end,
    set_window_cursor = function(win, cursor)
      cursors[win] = cursor
      return true
    end,
  })

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 10)
  assert_equal(cursors[10][1], 3)

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 20)
end

do
  local controller = manager_mod.new({
    state = {},
    workspace_manager_max_height = function()
      return 12
    end,
  })

  assert_equal(controller:dashboard_height(1), 5)
  assert_equal(controller:dashboard_height(9), 9)
  assert_equal(controller:dashboard_height(40), 12)
end

do
  local current_height = 5
  local configs = {}
  local controller = manager_mod.new({
    state = {
      workspace_manager_win = 10,
      workspace_manager_footer_win = 11,
    },
    is_valid_win = function(win)
      return win == 10 or win == 11
    end,
    get_window_config = function()
      return {
        relative = "editor",
        row = 4,
        col = 6,
        width = 84,
        height = current_height,
      }
    end,
    get_window_height = function(win)
      if win == 10 then
        return current_height
      end
      return 1
    end,
    get_window_width = function()
      return 84
    end,
    set_window_config = function(win, config)
      configs[win] = config
      if win == 10 then
        current_height = config.height
      end
      return true
    end,
    workspace_manager_max_height = function()
      return 9
    end,
  })

  assert_true(controller:resize_dashboard(20))
  assert_equal(configs[10].height, 9)
  assert_equal(configs[10].width, 84)
  assert_equal(configs[10].row, 4)
  assert_equal(configs[10].col, 6)
  assert_equal(configs[11].relative, "win")
  assert_equal(configs[11].win, 10)
  assert_equal(configs[11].row, 8)
  assert_equal(configs[11].width, 84)
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
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "inactive",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local delete_calls = 0
  local old_filereadable = vim.fn.filereadable
  vim.fn.filereadable = function()
    return 1
  end

  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    render_workspace_manager = function() end,
    close_workspace_manager = function() end,
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
        return "/repo/.agents/codux/review.md"
      end,
      delete_instruction_file = function()
        delete_calls = delete_calls + 1
        return true, nil
      end,
    },
  })

  assert_false(runtime:delete_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
  }))
  assert_equal(delete_calls, 0, "instruction file should not be deleted when state write fails")
  vim.fn.filereadable = old_filereadable
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        updated_at = "before",
        workspaces = {
          review = {
            name = "review",
            safe_name = "review",
            project_root = "/repo",
            tmux_window = "review",
            status = "inactive",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local write_count = 0
  local killed = false
  local old_filereadable = vim.fn.filereadable
  vim.fn.filereadable = function()
    return 1
  end

  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    render_workspace_manager = function() end,
    close_workspace_manager = function() end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        write_count = write_count + 1
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
        return "/repo/.agents/codux/review.md"
      end,
      delete_instruction_file = function()
        return false, "delete instruction failed"
      end,
    },
  })
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
  vim.fn.filereadable = old_filereadable
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
            status = "inactive",
            codex_status = "idle",
          },
        },
      },
    },
  }
  local delete_calls = 0
  local killed = false
  local old_filereadable = vim.fn.filereadable
  vim.fn.filereadable = function()
    return 1
  end

  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    render_workspace_manager = function() end,
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
        return "/repo/.agents/codux/review.md"
      end,
      delete_instruction_file = function(_, root, safe_name)
        delete_calls = delete_calls + 1
        assert_equal(root, "/repo")
        assert_equal(safe_name, "review")
        return true, nil
      end,
    },
  })
  runtime.kill_tmux_window_deferred = function(_, window_id)
    killed = window_id == "@1"
  end

  assert_true(runtime:delete_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_id = "@1",
  }))
  assert_nil(state_data.projects["/repo"].workspaces.review)
  assert_equal(delete_calls, 1)
  assert_true(killed)
  vim.fn.filereadable = old_filereadable
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {},
      },
    },
  }
  local delete_calls = 0
  local old_filereadable = vim.fn.filereadable
  vim.fn.filereadable = function()
    return 1
  end

  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    render_workspace_manager = function() end,
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
        return "/repo/.agents/codux/review.md"
      end,
      delete_instruction_file = function(_, root, safe_name)
        delete_calls = delete_calls + 1
        assert_equal(root, "/repo")
        assert_equal(safe_name, "review")
        return true, nil
      end,
    },
  })

  assert_true(runtime:delete_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
  }))
  assert_equal(delete_calls, 1)
  vim.fn.filereadable = old_filereadable
end

do
  local state_data = {
    projects = {
      ["/repo"] = {
        workspaces = {},
      },
    },
  }
  local closed = false
  local old_filereadable = vim.fn.filereadable
  vim.fn.filereadable = function()
    return 1
  end

  local runtime = runtime_mod.new({
    state = {
      workspace_manager_project_root = "/repo",
    },
    notify = function() end,
    render_workspace_manager = function() end,
    close_workspace_manager = function()
      closed = true
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
      project_state = function(_, next_state, root)
        return next_state.projects[root]
      end,
      instruction_file_path = function()
        return "/repo/.agents/codux/review.md"
      end,
      delete_instruction_file = function()
        return false, "delete instruction failed"
      end,
    },
  })

  assert_false(runtime:delete_saved_workspace({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
  }))
  assert_false(closed, "instruction-only delete should fail when instruction file remains")
  vim.fn.filereadable = old_filereadable
end

do
  local old_tmux = vim.env.TMUX
  local old_executable = vim.fn.executable
  local old_isdirectory = vim.fn.isdirectory
  local old_getcwd = vim.fn.getcwd
  local old_shellescape = vim.fn.shellescape
  vim.env.TMUX = "/tmp/tmux,1,0"
  vim.fn.executable = function()
    return 1
  end
  vim.fn.isdirectory = function(path)
    return path == "/repo" and 1 or 0
  end
  vim.fn.getcwd = function()
    return "/repo"
  end
  vim.fn.shellescape = function(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
  end

  local wrote_instruction = false
  local runtime = runtime_mod.new({
    state = {},
    get_config = function()
      return {
        codex_cmd = "codex",
        workspace_auto_cmd = "codex-auto",
        danger_full_access_cmd = "codex-danger",
        workspaces = {
          tmux_cmd = "tmux",
          nvim_cmd = "nvim",
        },
      }
    end,
    current_target = function()
      return { path = "/repo/file.lua", type = "file" }
    end,
    current_buffer_name = function()
      return "/repo/file.lua"
    end,
    git_root_for = function()
      return "/repo"
    end,
    git_branch_for = function()
      return "main"
    end,
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
    store = {
      read_state = function()
        return { projects = {} }, nil
      end,
      project_state = function(_, state, root)
        state.projects[root] = state.projects[root] or { workspaces = {} }
        return state.projects[root]
      end,
      workspace_from_state = function(record, fallback)
        local workspace = vim.deepcopy(fallback)
        if type(record) == "table" then
          for key, value in pairs(record) do
            workspace[key] = value
          end
        end
        return workspace
      end,
      read_instruction_file = function()
        return nil
      end,
      write_instruction_file = function()
        wrote_instruction = true
        return true, nil
      end,
      resolve_workspace_resume_session = function() end,
    },
  })

  local workspace, error_message = runtime:prepare_workspace("review", {
    resolved_instruction = "review the backend",
  })
  assert_nil(workspace)
  assert_contains(error_message, "Failed to create tmux window")
  assert_false(wrote_instruction, "instruction file should not be written when tmux creation fails")

  vim.env.TMUX = old_tmux
  vim.fn.executable = old_executable
  vim.fn.isdirectory = old_isdirectory
  vim.fn.getcwd = old_getcwd
  vim.fn.shellescape = old_shellescape
end

do
  local old_tmux = vim.env.TMUX
  local old_executable = vim.fn.executable
  local old_isdirectory = vim.fn.isdirectory
  local old_getcwd = vim.fn.getcwd
  local old_shellescape = vim.fn.shellescape
  vim.env.TMUX = "/tmp/tmux,1,0"
  vim.fn.executable = function()
    return 1
  end
  vim.fn.isdirectory = function(path)
    return path == "/repo" and 1 or 0
  end
  vim.fn.getcwd = function()
    return "/repo"
  end
  vim.fn.shellescape = function(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
  end

  local created = false
  local killed = false
  local deleted_instruction = false
  local runtime = runtime_mod.new({
    state = {},
    get_config = function()
      return {
        codex_cmd = "codex",
        workspace_auto_cmd = "codex-auto",
        danger_full_access_cmd = "codex-danger",
        workspaces = {
          tmux_cmd = "tmux",
          nvim_cmd = "nvim",
        },
      }
    end,
    current_target = function()
      return { path = "/repo/file.lua", type = "file" }
    end,
    current_buffer_name = function()
      return "/repo/file.lua"
    end,
    git_root_for = function()
      return "/repo"
    end,
    git_branch_for = function()
      return "main"
    end,
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
      return "", 1
    end,
    store = {
      read_state = function()
        return { projects = {} }, nil
      end,
      write_state = function()
        return false, "state write failed"
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = function(_, state, root)
        state.projects[root] = state.projects[root] or { workspaces = {} }
        return state.projects[root]
      end,
      workspace_from_state = function(record, fallback)
        local workspace = vim.deepcopy(fallback)
        if type(record) == "table" then
          for key, value in pairs(record) do
            workspace[key] = value
          end
        end
        return workspace
      end,
      state_record = function(_, workspace)
        return {
          name = workspace.name,
          safe_name = workspace.safe_name,
          project_root = workspace.project_root,
          tmux_window = workspace.window_name,
          status = workspace.status,
          codex_status = workspace.codex_status,
        }
      end,
      read_instruction_file = function()
        return nil
      end,
      write_instruction_file = function()
        return true, nil
      end,
      delete_instruction_file = function()
        deleted_instruction = true
        return true, nil
      end,
      resolve_workspace_resume_session = function() end,
    },
  })

  local workspace, error_message = runtime:prepare_workspace("review", {
    resolved_instruction = "review the backend",
  })
  assert_nil(workspace)
  assert_equal(error_message, "state write failed")
  assert_true(killed, "new tmux window should be cleaned up when state write fails")
  assert_true(deleted_instruction, "new instruction file should be cleaned up when state write fails")

  vim.env.TMUX = old_tmux
  vim.fn.executable = old_executable
  vim.fn.isdirectory = old_isdirectory
  vim.fn.getcwd = old_getcwd
  vim.fn.shellescape = old_shellescape
end

do
  local old_tmux = vim.env.TMUX
  local old_executable = vim.fn.executable
  local old_isdirectory = vim.fn.isdirectory
  local old_getcwd = vim.fn.getcwd
  local old_shellescape = vim.fn.shellescape
  vim.env.TMUX = "/tmp/tmux,1,0"
  vim.fn.executable = function()
    return 1
  end
  vim.fn.isdirectory = function(path)
    return path == "/repo" and 1 or 0
  end
  vim.fn.getcwd = function()
    return "/repo"
  end
  vim.fn.shellescape = function(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
  end

  local created_window = false
  local wrote_instruction = false
  local wrote_state = false
  local runtime = runtime_mod.new({
    state = {},
    get_config = function()
      return {
        codex_cmd = "codex",
        workspace_auto_cmd = "codex-auto",
        danger_full_access_cmd = "codex-danger",
        workspaces = {
          tmux_cmd = "tmux",
          nvim_cmd = "nvim",
        },
      }
    end,
    current_target = function()
      return { path = "/repo/file.lua", type = "file" }
    end,
    current_buffer_name = function()
      return "/repo/file.lua"
    end,
    git_root_for = function()
      return "/repo"
    end,
    git_branch_for = function()
      return "main"
    end,
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
    store = {
      read_state = function()
        return { projects = {} }, nil
      end,
      write_state = function()
        wrote_state = true
        return true, nil
      end,
      project_state = function(_, state, root)
        state.projects[root] = state.projects[root] or { workspaces = {} }
        return state.projects[root]
      end,
      read_instruction_file = function()
        return "existing instructions"
      end,
      write_instruction_file = function()
        wrote_instruction = true
        return true, nil
      end,
    },
  })

  local workspace, error_message = runtime:prepare_workspace("review", {
    resolved_instruction = "new instructions",
  })
  assert_nil(workspace)
  assert_equal(error_message, "workspace already exists")
  assert_false(created_window, "duplicate instruction-only workspace should not create tmux window")
  assert_false(wrote_instruction, "duplicate instruction-only workspace should not write instruction file")
  assert_false(wrote_state, "duplicate instruction-only workspace should not write state")

  vim.env.TMUX = old_tmux
  vim.fn.executable = old_executable
  vim.fn.isdirectory = old_isdirectory
  vim.fn.getcwd = old_getcwd
  vim.fn.shellescape = old_shellescape
end

do
  local old_tmux = vim.env.TMUX
  local old_executable = vim.fn.executable
  local old_isdirectory = vim.fn.isdirectory
  local old_getcwd = vim.fn.getcwd
  local old_shellescape = vim.fn.shellescape
  vim.env.TMUX = "/tmp/tmux,1,0"
  vim.fn.executable = function()
    return 1
  end
  vim.fn.isdirectory = function(path)
    return path == "/repo" and 1 or 0
  end
  vim.fn.getcwd = function()
    return "/repo"
  end
  vim.fn.shellescape = function(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
  end

  local created = false
  local state_data = { projects = {} }
  local runtime = runtime_mod.new({
    state = {},
    get_config = function()
      return {
        codex_cmd = "codex",
        workspace_auto_cmd = "codex-auto",
        danger_full_access_cmd = "codex-danger",
        workspaces = {
          tmux_cmd = "tmux",
          nvim_cmd = "nvim",
        },
      }
    end,
    current_target = function()
      return { path = "/repo/file.lua", type = "file" }
    end,
    current_buffer_name = function()
      return "/repo/file.lua"
    end,
    git_root_for = function()
      return "/repo"
    end,
    git_branch_for = function()
      return "main"
    end,
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
      project_state = function(_, state, root)
        state.projects[root] = state.projects[root] or { workspaces = {} }
        return state.projects[root]
      end,
      workspace_from_state = function(record, fallback)
        local workspace = vim.deepcopy(fallback)
        if type(record) == "table" then
          for key, value in pairs(record) do
            workspace[key] = value
          end
        end
        return workspace
      end,
      state_record = function(_, workspace)
        return {
          name = workspace.name,
          safe_name = workspace.safe_name,
          project_root = workspace.project_root,
          resolved_instruction = workspace.resolved_instruction,
          tmux_window = workspace.window_name,
          status = workspace.status,
          codex_status = workspace.codex_status,
        }
      end,
      read_instruction_file = function()
        return "existing instructions"
      end,
      write_instruction_file = function()
        return true, nil
      end,
      resolve_workspace_resume_session = function() end,
    },
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
  assert_equal(state_data.projects["/repo"].workspaces.review.resolved_instruction, "existing instructions")

  vim.env.TMUX = old_tmux
  vim.fn.executable = old_executable
  vim.fn.isdirectory = old_isdirectory
  vim.fn.getcwd = old_getcwd
  vim.fn.shellescape = old_shellescape
end

print("workspace_status_spec.lua: ok")
