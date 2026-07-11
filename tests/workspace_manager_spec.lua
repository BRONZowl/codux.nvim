local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local manager_mod = require("codux.workspace_manager")
local ui_mod = require("codux.ui")
local workspace_ui = require("codux.workspace_ui")

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_create_augroup = vim.api.nvim_create_augroup
  local old_create_autocmd = vim.api.nvim_create_autocmd
  local old_win_get_config = vim.api.nvim_win_get_config
  local enter_rhs
  local focused_win
  vim.api.nvim_open_win = function()
    return 20
  end
  vim.api.nvim_win_get_config = function()
    return { col = 0, row = 0 }
  end
  vim.api.nvim_create_augroup = function()
    return 92
  end
  vim.api.nvim_create_autocmd = function() end

  local controller = manager_mod.new({
    state = {
      workspace_manager_win = 10,
      workspace_manager_command_win = 30,
      workspace_manager_best_match_index = 2,
    },
    is_valid_win = function(win)
      return win == 10 or win == 20 or win == 30
    end,
    is_loaded_buf = function()
      return true
    end,
    get_window_config = function()
      return { col = 0, row = 0 }
    end,
    get_window_width = function()
      return 80
    end,
    ui = {
      create_scratch_buffer = function()
        return 32
      end,
      printable_prompt_keys = function()
        return {}
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function(_, _, lhs, rhs)
      if lhs == "<CR>" then
        enter_rhs = rhs
      end
    end,
    set_current_win = function(win)
      focused_win = win
      return true
    end,
  })
  function controller:render()
    return true
  end

  assert_true(controller:open_search_input())
  assert_true(enter_rhs())
  assert_equal(controller.state.workspace_manager_selected_index, 2)
  assert_equal(focused_win, 10)

  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_create_augroup = old_create_augroup
  vim.api.nvim_create_autocmd = old_create_autocmd
  vim.api.nvim_win_get_config = old_win_get_config
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local window_config
  vim.api.nvim_open_win = function(_, _, config)
    window_config = config
    return 41
  end

  local controller = manager_mod.new({
    state = {},
    ui = {
      create_scratch_buffer = function()
        return 32
      end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function() end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function() end,
  })

  assert_true(controller:open_command_sink())
  assert_equal(window_config.focusable, false)
  vim.api.nvim_open_win = old_open_win
end

do
  local confirmed_message
  local delete_called = false
  local controller = manager_mod.new({
    workspace_ui = workspace_ui,
    delete_saved_workspace = function()
      delete_called = true
      return true
    end,
  })
  local old_confirm = vim.fn.confirm
  vim.fn.confirm = function(message, choices, default)
    confirmed_message = message
    assert_equal(choices, "&Delete\n&Cancel")
    assert_equal(default, 2)
    return 2
  end

  assert_false(controller:delete_selected_workspace({
    name = "review",
    safe_name = "review",
    workspace_kind = "worktree",
    worktree_path = "/codux-worktrees/review",
    worktree_branch = "dev/review",
  }))
  assert_contains(confirmed_message, "Force delete will remove the Git worktree and delete its branch.")
  assert_false(delete_called)
  vim.fn.confirm = old_confirm
end

if type(vim.api) == "table" then
  local old_open_win = vim.api.nvim_open_win
  local old_win_set_cursor = vim.api.nvim_win_set_cursor
  local window_options
  vim.api.nvim_open_win = function()
    return 42
  end
  vim.api.nvim_win_set_cursor = function()
    return true
  end

  local controller = manager_mod.new({
    namespace = 77,
    state = {},
    is_loaded_buf = function()
      return true
    end,
    workspace_entries_for_project = function()
      return {
        { name = "review", safe_name = "review", project_root = "/repo" },
      }, nil
    end,
    get_window_config = function()
      return { col = 0, row = 0 }
    end,
    get_window_width = function()
      return 80
    end,
    get_window_height = function()
      return 10
    end,
    ui = {
      create_scratch_buffer = function()
        return 32
      end,
      set_lines = function() end,
      close_window = function() end,
      delete_buffer = function() end,
      set_window_options = function(_, opts)
        window_options = opts
      end,
    },
    bind_close_keys = function() end,
    set_buffer_keymap = function() end,
  })
  function controller:selected_or_notify()
    return { name = "review", safe_name = "review", project_root = "/repo" }
  end

  assert_true(controller:open_action_palette())
  assert_equal(window_options.winhighlight, "FloatBorder:WhichKey,FloatTitle:WhichKey")
  vim.api.nvim_open_win = old_open_win
  vim.api.nvim_win_set_cursor = old_win_set_cursor
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
  assert_equal(bound.j, "Next Codux Workspace")
  assert_equal(bound.k, "Previous Codux Workspace")
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
  local render_count = 0
  local controller = manager_mod.new({
    state = {
      workspace_manager_win = 10,
      workspace_manager_search_win = 20,
      workspace_manager_items = {
        { name = "Backend Debug" },
        { name = "Code Review" },
        { name = "Architecture" },
      },
      workspace_manager_best_match_index = 2,
      workspace_manager_search_confirmed = true,
      workspace_manager_selected_index = 2,
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
  function controller:render()
    render_count = render_count + 1
    return true
  end

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 10)
  assert_equal(cursors[10][1], 3)

  assert_true(controller:toggle_search_list_focus())
  assert_equal(current_win, 20)

  assert_true(controller:move_workspace_selection(1))
  assert_equal(controller.state.workspace_manager_selected_index, 3)
  assert_equal(cursors[10][1], 4)
  assert_equal(controller:selected_item().name, "Architecture")

  assert_true(controller:move_workspace_selection(1))
  assert_equal(controller.state.workspace_manager_selected_index, 3)
  assert_equal(cursors[10][1], 4)

  assert_true(controller:move_workspace_selection(-1))
  assert_equal(controller.state.workspace_manager_selected_index, 2)
  assert_equal(cursors[10][1], 3)
  assert_equal(controller:selected_item().name, "Code Review")
  assert_equal(render_count, 3)
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
  local selected
  local rendered = false
  local notifications = {}
  local controller = manager_mod.new({
    state = {},
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
    select_provider_profile = function(opts)
      assert_equal(opts.open_provider, nil)
      assert_equal(opts.open_default, nil)
      assert_equal(opts.provider_filetype, "codux-workspace-provider")
      assert_equal(opts.profile_filetype, "codux-workspace-profile")
      return opts.on_select({
        agent_provider = "grok",
        profile = "danger",
        profile_label = "Grok Full",
      })
    end,
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
  function controller:render()
    rendered = true
    return true
  end

  assert_true(controller:switch_selected_workspace_profile({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
  }))

  assert_equal(selected.workspace.safe_name, "review")
  assert_equal(selected.agent_provider, "grok")
  assert_equal(selected.permission_profile, "danger")
  assert_true(selected.restart)
  assert_true(rendered)
  assert_contains(notifications[#notifications], "Grok Full")
end

do
  local calls = {}
  local controller = manager_mod.new({
    state = {
      workspace_manager_action_workspace = {
        name = "review",
        safe_name = "review",
        project_root = "/repo",
      },
    },
    start_saved_workspace = function(entry)
      table.insert(calls, "start:" .. tostring(entry.name))
      return true
    end,
  })
  function controller:close_action_palette()
    table.insert(calls, "close_palette")
    return true
  end

  assert_true(controller:run_action("start_workspace"))
  assert_equal(calls[1], "close_palette")
  assert_equal(calls[2], "start:review")
end

print("workspace_manager_spec.lua: ok")
