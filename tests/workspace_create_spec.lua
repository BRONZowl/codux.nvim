local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true
local assert_contains = h.assert_contains

local workspace_create_mod = require("codux.workspace_create")

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
    }))
    assert_contains(table.concat(preview_lines, "\n"), "Mission: Alpha")

    keymaps["<CR>"]()

    assert_equal(created_name, "Research")
    assert_equal(created_opts.mission_id, "mission:alpha")
    assert_equal(created_opts.mission_name, "Alpha")
    assert_equal(created_opts.mission_role, "Research")
    assert_equal(created_opts.mission_objective, "Build it")
    assert_equal(created_opts.custom_instruction, created_opts.resolved_instruction)
    assert_contains(created_opts.resolved_instruction, "You are the Research")
    assert_contains(created_opts.resolved_instruction, "Mission: Alpha")
    assert_contains(created_opts.resolved_instruction, "Objective:\nBuild it")
    assert_contains(created_opts.resolved_instruction, "Role focus:\nInvestigate APIs.")
  end)
end

print("workspace_create_spec.lua: ok")
