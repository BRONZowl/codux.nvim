local util = require("codux.util")

local M = {}

function M.create(codux, deps)
  deps = type(deps) == "table" and deps or {}
  local notify = type(deps.notify) == "function" and deps.notify or util.notify
  local workspace_manager_project_root = type(deps.workspace_manager_project_root) == "function"
      and deps.workspace_manager_project_root
    or function()
      return vim.loop.cwd()
    end
  local mission_controller = type(deps.mission_controller) == "table" and deps.mission_controller or nil

  local function open_workspace_instruction_from_args(opts)
    if #opts.fargs == 0 then
      codux.open_workspace_prompt()
      return
    end

    local name, _custom_requested, error_message, agent_provider = codux._v5.parse_create_args(opts.fargs)
    if error_message then
      notify(error_message, vim.log.levels.ERROR)
      return
    end
    codux._v5.open_workspace_provider_profile_menu(name, { agent_provider = agent_provider })
  end

  vim.api.nvim_create_user_command("Codux", function()
    codux.open()
  end, { force = true, desc = "Open or focus the Codux agent popup" })

  vim.api.nvim_create_user_command("CoduxOpen", function()
    codux.open()
  end, { force = true, desc = "Open or focus the Codux agent popup" })

  vim.api.nvim_create_user_command("CoduxOpenAuto", function()
    codux.open_workspace_auto()
  end, { force = true, desc = "Open Codux autopilot with approve-for-me permissions" })

  vim.api.nvim_create_user_command("CoduxOpenDanger", function()
    codux.open_danger_full_access()
  end, { force = true, desc = "Open Codex danger zone with no sandbox" })

  vim.api.nvim_create_user_command("CoduxOpenProvider", function(opts)
    codux.open_provider(opts.fargs[1], opts.fargs[2])
  end, {
    force = true,
    nargs = "+",
    complete = function(arglead)
      return codux._v5.filter_completion({ "codex", "grok", "default", "auto", "danger" }, arglead)
    end,
    desc = "Open Codux with a specific agent provider",
  })

  vim.api.nvim_create_user_command("CoduxSetDefaultProvider", function(opts)
    if type(opts.args) == "string" and opts.args ~= "" then
      codux.set_default_provider(opts.args)
      return
    end
    codux.set_default_provider_menu()
  end, {
    force = true,
    nargs = "?",
    complete = function(arglead)
      return codux._v5.filter_completion({ "codex", "grok" }, arglead)
    end,
    desc = "Set the global default Codux agent provider",
  })

  vim.api.nvim_create_user_command("CoduxSetGrokTheme", function(opts)
    if type(opts.args) == "string" and opts.args ~= "" then
      codux.set_grok_theme(opts.args)
      return
    end
    codux.set_grok_theme_menu()
  end, {
    force = true,
    nargs = "?",
    complete = function(arglead)
      local themes = {
        "auto",
        "groknight",
        "grokday",
        "tokyonight",
        "rosepine-moon",
        "oscura-midnight",
      }
      return codux._v5.filter_completion(themes, arglead)
    end,
    desc = "Set the preferred Grok TUI theme",
  })

  vim.api.nvim_create_user_command("CoduxOpenGrok", function()
    codux.open_grok()
  end, { force = true, desc = "Open Grok" })

  vim.api.nvim_create_user_command("CoduxOpenGrokAuto", function()
    codux.open_grok_auto()
  end, { force = true, desc = "Open Grok autopilot" })

  vim.api.nvim_create_user_command("CoduxOpenGrokDanger", function()
    codux.open_grok_danger()
  end, { force = true, desc = "Open Grok full access" })

  vim.api.nvim_create_user_command(
    "CoduxWorkspace",
    open_workspace_instruction_from_args,
    { force = true, nargs = "*", complete = codux._v5.complete_create, desc = "Create a named Codux tmux workspace" }
  )

  vim.api.nvim_create_user_command(
    "CoduxWorkspaceCreate",
    open_workspace_instruction_from_args,
    { force = true, nargs = "*", complete = codux._v5.complete_create, desc = "Create a named Codux tmux workspace" }
  )

  vim.api.nvim_create_user_command("CoduxWorkspaceOpen", function(opts)
    codux.open_saved_workspace(opts.args, workspace_manager_project_root())
  end, { force = true, nargs = 1, complete = codux._v5.complete_workspace_names, desc = "Open a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceSelect", function(opts)
    codux.select_workspace(opts.args)
  end, { force = true, nargs = 1, complete = codux._v5.complete_workspace_names, desc = "Select a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceDelete", function(opts)
    codux.delete_workspace(opts.args)
  end, { force = true, nargs = 1, complete = codux._v5.complete_workspace_names, desc = "Delete a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceRename", function(opts)
    local old_name = opts.fargs[1]
    local new_name = opts.fargs[2]
    if type(old_name) ~= "string" or old_name == "" or type(new_name) ~= "string" or new_name == "" then
      notify("Usage: CoduxWorkspaceRename <old> <new>", vim.log.levels.ERROR)
      return
    end
    codux.rename_workspace(old_name, new_name)
  end, { force = true, nargs = "+", complete = codux._v5.complete_workspace_names, desc = "Rename a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceRestore", function()
    codux.restore_workspaces()
  end, { force = true, desc = "Restore Codux workspace status from tmux" })

  vim.api.nvim_create_user_command("CoduxWorkspaceCloseAll", function()
    codux.close_all_workspace_windows()
  end, { force = true, desc = "Close all current-project Codux workspaces" })

  vim.api.nvim_create_user_command("CoduxWorkspaceIgnore", function()
    codux.ignore_workspace_files()
  end, { force = true, desc = "Add Codux workspace files to the current project's .gitignore" })

  vim.api.nvim_create_user_command("CoduxWorkspaces", function()
    codux.open_workspaces()
  end, { force = true, desc = "Show current Codux workspaces" })

  vim.api.nvim_create_user_command("CoduxMissionCreate", function(opts)
    if type(opts.args) == "string" and opts.args ~= "" then
      if mission_controller then
        if type(mission_controller.open_mission_provider_menu) == "function" then
          mission_controller:open_mission_provider_menu(opts.args)
        else
          mission_controller:open_objective_editor(opts.args)
        end
      end
      return
    end
    codux.open_mission_prompt()
  end, { force = true, nargs = "?", desc = "Create a Codux Mission Control crew" })

  vim.api.nvim_create_user_command("CoduxMissionCreateGrok", function(opts)
    if type(opts.args) == "string" and opts.args ~= "" then
      if mission_controller then
        mission_controller:open_mission_provider_menu(opts.args, { agent_provider = "grok" })
      end
      return
    end
    codux.open_mission_prompt({ agent_provider = "grok" })
  end, { force = true, nargs = "?", desc = "Create a Grok-backed Codux Mission Control crew" })

  vim.api.nvim_create_user_command("CoduxMissions", function()
    codux.open_missions()
  end, { force = true, desc = "Show Codux missions" })

  vim.api.nvim_create_user_command("CoduxMissionDashboard", function()
    codux.open_mission_dashboard()
  end, { force = true, desc = "Show the Codux mission dashboard" })

  vim.api.nvim_create_user_command("CoduxMissionEdit", function(opts)
    codux.edit_mission_objective(opts.args)
  end, { force = true, nargs = 1, complete = codux._v5.complete_mission_names, desc = "Edit a Codux mission objective" })

  vim.api.nvim_create_user_command("CoduxMissionFocus", function(opts)
    codux.edit_mission_focus_packet(opts.args)
  end, { force = true, nargs = 1, complete = codux._v5.complete_mission_names, desc = "Edit a Codux mission focus packet" })

  vim.api.nvim_create_user_command("CoduxMissionDelete", function(opts)
    codux.delete_saved_mission(opts.args)
  end, { force = true, nargs = 1, complete = codux._v5.complete_mission_names, desc = "Delete a Codux mission" })

  vim.api.nvim_create_user_command("CoduxMissionClose", function(opts)
    codux.close_saved_mission(opts.args)
  end, { force = true, nargs = 1, complete = codux._v5.complete_mission_names, desc = "Close a Codux mission" })

  vim.api.nvim_create_user_command("CoduxMissionProcessDispatch", function()
    local root = workspace_manager_project_root()
    local summary = codux.process_mission_dispatch({ project_root = root })
    if type(summary) ~= "table" then
      notify("Mission dispatch processing failed", vim.log.levels.ERROR)
      return
    end
    if (summary.processed or 0) == 0 then
      notify("No pending mission dispatch actions")
      return
    end
    notify(
      string.format(
        "Dispatched %d action(s) (%d ok, %d failed)",
        tonumber(summary.processed) or 0,
        tonumber(summary.succeeded) or 0,
        tonumber(summary.failed) or 0
      ),
      (summary.failed or 0) > 0 and vim.log.levels.WARN or vim.log.levels.INFO
    )
    if mission_controller and type(mission_controller.refresh_loaded_dashboard) == "function" then
      mission_controller:refresh_loaded_dashboard(root)
    end
  end, { force = true, desc = "Process pending Codux mission Manager dispatch files" })

  vim.api.nvim_create_user_command("CoduxToggle", function()
    codux.toggle()
  end, { force = true, desc = "Toggle the Codux agent popup" })

  vim.api.nvim_create_user_command("CoduxClose", function()
    codux.close()
  end, { force = true, desc = "Hide the Codux popup without stopping the agent" })

  vim.api.nvim_create_user_command("CoduxExit", function()
    codux.exit()
  end, { force = true, desc = "Stop the agent and close the popup" })

  vim.api.nvim_create_user_command("CoduxReview", function()
    codux.send_file_review()
  end, { force = true, desc = "Send current file or explorer node to the agent for review" })

  vim.api.nvim_create_user_command("CoduxReviewSelection", function(opts)
    codux.send_selection(opts)
  end, { force = true, range = true, desc = "Send selected code to the agent for review" })

  vim.api.nvim_create_user_command("CoduxDiagnostics", function()
    codux.send_diagnostics()
  end, { force = true, desc = "Send diagnostics, lists, and headless health output to the agent" })

  vim.api.nvim_create_user_command("CoduxDiff", function()
    codux.send_git_diff()
  end, { force = true, desc = "Send Git changes to the agent for review" })

  vim.api.nvim_create_user_command("CoduxTogglePlan", function()
    codux.toggle_plan_mode()
  end, { force = true, desc = "Toggle agent plan mode" })

  vim.api.nvim_create_user_command("CoduxHealth", function()
    codux.health()
  end, { force = true, desc = "Run codux.nvim health checks" })

  vim.api.nvim_create_user_command("CoduxDoctor", function()
    codux.doctor()
  end, { force = true, desc = "Run codux.nvim troubleshooting checks" })
end

return M
