local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_true = h.assert_true

local commands = require("codux.commands")

local created = {}
local original_api = vim.api
vim.api = vim.api or {}
local original_create_user_command = vim.api.nvim_create_user_command
vim.api.nvim_create_user_command = function(name, callback, opts)
  created[name] = {
    callback = callback,
    opts = opts,
  }
end

local notifications = {}
local calls = {}
local codux = {
  _v5 = {
    complete_create = function() end,
    complete_workspace_names = function() end,
    complete_mission_names = function() end,
    parse_create_args = function(args)
      if args[1] == "bad" then
        return nil, false, "bad workspace"
      end
      return args[1], false, nil
    end,
    open_workspace_provider_profile_menu = function(name)
      table.insert(calls, "workspace_profile:" .. tostring(name))
    end,
  },
}

for _, name in ipairs({
  "open",
  "open_workspace_prompt",
  "open_saved_workspace",
  "select_workspace",
  "delete_workspace",
  "rename_workspace",
  "restore_workspaces",
  "close_all_workspace_windows",
  "ignore_workspace_files",
  "open_workspaces",
  "open_mission_prompt",
  "open_missions",
  "open_mission_dashboard",
  "edit_mission_objective",
  "edit_mission_focus_packet",
  "delete_saved_mission",
  "close_saved_mission",
  "toggle",
  "close",
  "exit",
  "send_file_review",
  "send_selection",
  "send_diagnostics",
  "send_git_diff",
  "toggle_plan_mode",
  "health",
  "doctor",
  "set_default_provider",
  "set_default_provider_menu",
}) do
  codux[name] = function(...)
    table.insert(calls, name .. ":" .. tostring((...)))
  end
end

commands.create(codux, {
  notify = function(message)
    table.insert(notifications, message)
  end,
  workspace_manager_project_root = function()
    return "/repo"
  end,
  mission_controller = {
    open_mission_provider_menu = function(_, name, opts)
      opts = type(opts) == "table" and opts or {}
      table.insert(calls, "mission_provider:" .. tostring(name) .. ":" .. tostring(opts.agent_provider or ""))
    end,
    open_objective_editor = function(_, name)
      table.insert(calls, "mission_editor:" .. tostring(name))
    end,
  },
})

assert_true(type(created.Codux.callback) == "function")
assert_equal(created.CoduxWorkspace.opts.nargs, "*")
assert_equal(created.CoduxMissionEdit.opts.nargs, 1)
assert_equal(created.CoduxMissionFocus.opts.nargs, 1)

created.CoduxWorkspace.callback({ fargs = { "alpha" } })
assert_equal(calls[#calls], "workspace_profile:alpha")

created.CoduxWorkspace.callback({ fargs = { "bad" } })
assert_equal(notifications[#notifications], "bad workspace")

created.CoduxWorkspaceOpen.callback({ args = "alpha" })
assert_equal(calls[#calls], "open_saved_workspace:alpha")

created.CoduxWorkspaceRename.callback({ fargs = { "old", "new" } })
assert_equal(calls[#calls], "rename_workspace:old")

created.CoduxMissionCreate.callback({ args = "Mission" })
assert_equal(calls[#calls], "mission_provider:Mission:")

created.CoduxMissionCreateGrok.callback({ args = "Mission" })
assert_equal(calls[#calls], "mission_provider:Mission:grok")

assert_true(type(created.CoduxSetDefaultProvider.callback) == "function")
created.CoduxSetDefaultProvider.callback({ args = "grok" })
assert_equal(calls[#calls], "set_default_provider:grok")
created.CoduxSetDefaultProvider.callback({ args = "" })
assert_equal(calls[#calls], "set_default_provider_menu:nil")

vim.api.nvim_create_user_command = original_create_user_command
if original_api == nil then
  vim.api = nil
end

print("commands_spec.lua: ok")
