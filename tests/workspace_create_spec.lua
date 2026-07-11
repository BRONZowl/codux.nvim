local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_contains = h.assert_contains

local workspace_create_mod = require("codux.workspace_create")
local mission_control_mod = require("codux.mission_control")

local function with_editor_size(columns, lines, callback)
  local old_columns = vim.o.columns
  local old_lines = vim.o.lines
  local old_cmdheight = vim.o.cmdheight
  vim.o.columns = columns
  vim.o.lines = lines
  vim.o.cmdheight = 1

  local ok, err = pcall(callback)
  vim.o.columns = old_columns
  vim.o.lines = old_lines
  vim.o.cmdheight = old_cmdheight
  if not ok then
    error(err, 0)
  end
end

do
  local controller = workspace_create_mod.new({})
  local mission = mission_control_mod.new({})

  with_editor_size(140, 40, function()
    local config = controller:instruction_editor_config(1)
    local objective = mission:objective_editor_config(1)
    assert_equal(config.width, 96)
    assert_equal(config.height, 10)
    assert_equal(config.zindex, 80)
    assert_equal(config.width, objective.width)
    assert_equal(config.height, objective.height)
    assert_equal(config.zindex, objective.zindex)
    assert_equal(config.title, " Workspace Instruction ")
  end)

  with_editor_size(42, 12, function()
    local config = controller:instruction_editor_config(20)
    local objective = mission:objective_editor_config(20)
    assert_true(config.width <= 38)
    assert_true(config.height <= 7)
    assert_equal(config.width, objective.width)
    assert_equal(config.height, objective.height)
    assert_equal(config.zindex, 80)
  end)

  with_editor_size(120, 40, function()
    local config = controller:instruction_editor_config(20)
    local objective = mission:objective_editor_config(20)
    assert_equal(config.width, objective.width)
    assert_equal(config.height, objective.height)
    assert_equal(config.zindex, objective.zindex)
  end)
end

do
  h.with_vim_api({
    nvim_set_option_value = function() end,
    nvim_open_win = function()
      return 41
    end,
  }, function()
    local keymaps = {}
    local preview_lines = {}
    local created_name
    local created_opts
    local controller = workspace_create_mod.new({
      namespace = 1,
      is_loaded_buf = function()
        return true
      end,
      is_valid_win = function()
        return true
      end,
      ui = {
        create_scratch_buffer = function()
          return 11
        end,
        set_lines = function(_, lines)
          preview_lines = lines
        end,
        set_window_options = function() end,
        close_window = function() end,
        delete_buffer = function() end,
      },
      set_buffer_keymap = function(_, _, lhs, callback)
        keymaps[lhs] = callback
      end,
      bind_close_keys = function() end,
      create_workspace = function(name, opts)
        created_name = name
        created_opts = opts
        return true
      end,
    })
    controller.open_create_footer = function()
      return nil, nil
    end

    assert_true(controller:open_create_preview({
      name = "Research",
      custom_instruction = "Investigate APIs.",
      resolved_instruction = "Investigate APIs.",
      mission_id = "mission:alpha",
      mission_name = "Alpha",
      mission_objective = "Build it",
      agent_provider = "grok",
      permission_profile = "danger",
    }))
    assert_contains(table.concat(preview_lines, "\n"), "Mission: Alpha")
    assert_contains(table.concat(preview_lines, "\n"), "Agent: grok")
    assert_contains(table.concat(preview_lines, "\n"), "Profile: full")

    keymaps["<CR>"]()

    assert_equal(created_name, "Research")
    assert_equal(created_opts.mission_id, "mission:alpha")
    assert_equal(created_opts.mission_name, "Alpha")
    assert_equal(created_opts.mission_role, "Research")
    assert_equal(created_opts.mission_objective, "Build it")
    assert_equal(created_opts.agent_provider, "grok")
    assert_equal(created_opts.permission_profile, "danger")
    assert_equal(created_opts.custom_instruction, created_opts.resolved_instruction)
    assert_contains(created_opts.resolved_instruction, "You are the Research")
    assert_contains(created_opts.resolved_instruction, "Mission: Alpha")
    assert_contains(created_opts.resolved_instruction, "Objective:\nBuild it")
    assert_contains(created_opts.resolved_instruction, "Role focus:\nInvestigate APIs.")
  end)
end

do
  local prompt_opts
  local selected_opts
  local opened_name
  local opened_opts
  local controller = workspace_create_mod.new({
    namespace = 1,
    has_tmux_session = function()
      return true
    end,
    single_line_prompt = function(opts, callback)
      prompt_opts = opts
      callback("Research")
      return true
    end,
    select_provider_profile = function(opts)
      selected_opts = opts
      assert_equal(opts.open_provider, nil)
      assert_equal(opts.open_default, nil)
      assert_equal(opts.open_auto, nil)
      assert_equal(opts.open_danger, nil)
      return opts.on_select({
        agent_provider = "grok",
        profile = "auto",
      })
    end,
  })
  function controller:open_custom_instruction_prompt(name, opts)
    opened_name = name
    opened_opts = opts
    return true
  end

  assert_true(controller:open_prompt())
  assert_equal(prompt_opts.prompt, "Codux workspace: ")
  assert_equal(selected_opts.provider_filetype, "codux-workspace-provider")
  assert_equal(selected_opts.profile_filetype, "codux-workspace-profile")
  assert_nil(selected_opts.agent_provider)
  assert_equal(opened_name, "Research")
  assert_equal(opened_opts.agent_provider, "grok")
  assert_equal(opened_opts.permission_profile, "auto")
end

do
  local selected_opts
  local opened_opts
  local controller = workspace_create_mod.new({
    namespace = 1,
    has_tmux_session = function()
      return true
    end,
    single_line_prompt = function(_, callback)
      callback("Research")
      return true
    end,
    default_agent_provider = function()
      return "grok"
    end,
    select_provider_profile = function(opts)
      selected_opts = opts
      return opts.on_select({
        agent_provider = opts.agent_provider,
        profile = "default",
      })
    end,
  })
  function controller:open_custom_instruction_prompt(_, opts)
    opened_opts = opts
    return true
  end

  assert_true(controller:open_prompt())
  assert_equal(selected_opts.agent_provider, "grok")
  assert_equal(opened_opts.agent_provider, "grok")
  assert_equal(opened_opts.permission_profile, "default")
end

print("workspace_create_spec.lua: ok")
