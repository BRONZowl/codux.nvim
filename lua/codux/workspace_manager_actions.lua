local action_palette = require("codux.action_palette")
local providers = require("codux.providers")

local M = {}

local function profile_label(choice)
  return choice.profile_label or (providers.provider_label(choice.agent_provider) .. " " .. providers.profile_label(choice.profile))
end

local function open_profile_picker(controller, item, opts)
  opts = type(opts) == "table" and opts or {}
  item = type(item) == "table" and item or nil
  if not item then
    return false
  end

  local label = item.mission_role or item.name or item.safe_name or "workspace"
  if type(controller.select_provider_profile) ~= "function" then
    controller.notify("Codux profile picker is unavailable", vim.log.levels.ERROR)
    return false
  end
  return controller.select_provider_profile({
    provider_title = " Profile " .. tostring(label) .. " agent ",
    provider_filetype = opts.provider_filetype or "codux-workspace-provider",
    provider_zindex = opts.provider_zindex or opts.zindex or 75,
    provider_cancel_desc = "Cancel Codux Profile",
    provider_create_error = "Failed to create Codux profile menu",
    provider_open_error = "Failed to open Codux profile menu",
    profile_title = " Profile " .. tostring(label) .. " ",
    profile_filetype = opts.filetype or "codux-workspace-profile",
    profile_zindex = opts.profile_zindex or opts.zindex or 76,
    profile_cancel_desc = "Cancel Codux Profile",
    profile_create_error = "Failed to create Codux profile menu",
    profile_open_error = "Failed to open Codux profile menu",
    on_select = function(choice)
      if type(choice) ~= "table" then
        return false
      end

      local ok, error_message, restarted = controller.switch_workspace_profile(item, choice.agent_provider, choice.profile, {
        restart = true,
      })
      if ok then
        controller.notify(
          "Switched Codux workspace "
            .. tostring(label)
            .. " to "
            .. profile_label(choice)
            .. (restarted and " and restarted it" or "")
        )
        if type(controller.render) == "function" then
          controller:render()
        end
        return true
      end
      controller.notify(error_message or "Failed to switch Codux workspace profile", vim.log.levels.ERROR)
      return false
    end,
  })
end

function M.selected_or_notify(controller)
  local item = controller:selected_item()
  if not item then
    controller.notify("No Codux workspace selected", vim.log.levels.WARN)
    return nil
  end
  return item
end

function M.close_action_palette(controller)
  return controller:action_palette_controller():close()
end

function M.action_palette_width(controller)
  return action_palette.palette_width(controller:window_width() or 58)
end

function M.action_palette_config(controller, item, item_count)
  local dashboard_config = controller.is_valid_win(controller.state.workspace_manager_win)
      and vim.api.nvim_win_get_config(controller.state.workspace_manager_win)
    or {}
  local dashboard_width = controller:window_width() or 58
  local width = controller:action_palette_width()

  return action_palette.centered_window_config({
    dashboard_width = dashboard_width,
    dashboard_height = controller:window_height() or math.max(1, item_count or 1),
    col = type(dashboard_config.col) == "number" and dashboard_config.col or nil,
    row = type(dashboard_config.row) == "number" and dashboard_config.row or nil,
    width = width,
    height = math.max(1, item_count or 1),
    title = " Codux actions: "
      .. controller.workspace_ui.truncate_display_tail(item and item.name or "workspace", width - 16)
      .. " ",
  })
end

function M.render_action_palette(controller)
  return controller:action_palette_controller():render()
end

function M.run_action(controller, action, item)
  item = item or controller.state.workspace_manager_action_workspace or controller:selected_or_notify()
  if not item then
    return false
  end

  if action == "rename" then
    controller:close_action_palette()
    return controller:rename_selected_workspace(item)
  end
  if action == "edit_instructions" then
    controller:close_action_palette()
    return controller.edit_saved_workspace_instruction(item)
  end
  if action == "switch_profile" then
    controller:close_action_palette()
    return controller:switch_selected_workspace_profile(item)
  end
  if action == "close_window" then
    controller:close_action_palette()
    return controller.close_saved_workspace_window(item)
  end
  if action == "close_all_windows" then
    controller:close_action_palette()
    return controller:close_all_workspace_windows()
  end
  if action == "delete" then
    controller:close_action_palette()
    return controller:delete_selected_workspace(item)
  end
  return false
end

function M.run_highlighted_action(controller)
  return controller:action_palette_controller():run_highlighted()
end

function M.move_action_cursor(controller, delta)
  return controller:action_palette_controller():move_cursor(delta)
end

function M.open_action_palette(controller)
  local item = controller:selected_or_notify()
  if not item then
    return false
  end

  return controller:action_palette_controller():open(item)
end

function M.open_selected_workspace(controller, item)
  item = item or controller:selected_or_notify()
  if not item then
    return false
  end
  local root = item.project_root or controller.state.workspace_manager_project_root
  controller:close()
  return controller.open_saved_workspace(item.name, root)
end

function M.rename_selected_workspace(controller, item)
  item = item or controller:selected_or_notify()
  if not item then
    return false
  end
  controller.single_line_prompt({ prompt = "Rename Codux workspace: ", default = item.name }, function(input)
    local new_name = controller.trim(input)
    if new_name == "" then
      return
    end
    controller.rename_saved_workspace(item, new_name)
  end)
end

function M.switch_selected_workspace_profile(controller, item)
  item = item or controller:selected_or_notify()
  if not item then
    return false
  end
  return open_profile_picker(controller, item)
end

function M.delete_selected_workspace(controller, item)
  item = item or controller:selected_or_notify()
  if not item then
    return false
  end
  if controller.workspace_ui.confirm_delete_workspace(item) then
    return controller.delete_saved_workspace(item)
  end
  return false
end

function M.close_selected_workspace_window(controller, item)
  item = item or controller:selected_or_notify()
  if not item then
    return false
  end
  return controller.close_saved_workspace_window(item)
end

function M.close_all_workspace_windows(controller)
  local root = controller.state.workspace_manager_project_root or controller.project_root()
  local choice = vim.fn.confirm("Close all Codux workspaces for this project?", "&Yes\n&No", 2)
  if choice ~= 1 then
    return false
  end
  return controller.close_all_saved_workspace_windows(root)
end

function M.open_codux_menu(controller)
  controller:close()
  vim.schedule(function()
    local leader = tostring(vim.g.mapleader or "\\")
    local keys = vim.api.nvim_replace_termcodes(leader .. "z", true, false, true)
    vim.api.nvim_feedkeys(keys, "m", false)
  end)
end

function M.bind_commands(controller, target_bufnr)
  controller.bind_close_keys(target_bufnr, function()
    return controller:close()
  end, "Close Codux Workspaces", "n", { escape = true, q = true })
  controller.set_buffer_keymap(target_bufnr, "n", "<leader>z", function()
    return controller:open_codux_menu()
  end, "Open Codux Menu", {
    nowait = true,
  })
  controller.set_buffer_keymap(target_bufnr, "n", "<Tab>", function()
    return controller:toggle_search_list_focus()
  end, "Search/List Codux Workspaces", {
    nowait = true,
  })
  controller.set_buffer_keymap(target_bufnr, "n", "m", function()
    return controller:open_action_palette()
  end, "Open Codux Workspace Menu")
  controller.set_buffer_keymap(target_bufnr, "n", "h", function()
    return controller.doctor()
  end, "Run Codux Doctor")
  controller.set_buffer_keymap(target_bufnr, "n", "j", function()
    return controller:move_workspace_selection(1)
  end, "Next Codux Workspace", {
    nowait = true,
  })
  controller.set_buffer_keymap(target_bufnr, "n", "k", function()
    return controller:move_workspace_selection(-1)
  end, "Previous Codux Workspace", {
    nowait = true,
  })
  controller.set_buffer_keymap(target_bufnr, "n", "<CR>", function()
    return controller:open_selected_workspace()
  end, "Open Codux Workspace")
end

return M
