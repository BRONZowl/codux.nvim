local ui = require("codux.ui")

local M = {}

function M.open(controller, mission)
  local initial_preview_lines = controller.mission.preview_lines(mission)
  local initial_config = controller:preview_config(#initial_preview_lines)
  local preview_lines = controller.mission.preview_lines(mission, {
    max_width = initial_config.width,
    max_lines = initial_config.height,
  })
  local preview_config = controller:preview_config(#preview_lines)
  local bufnr = controller.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-mission-preview",
  })
  if not bufnr then
    controller.notify("Failed to create Codux mission preview", vim.log.levels.ERROR)
    return false
  end
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })

  controller.ui.set_lines(bufnr, preview_lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, preview_config)
  if not win_ok then
    controller.ui.delete_buffer(bufnr)
    controller.notify("Failed to open Codux mission preview", vim.log.levels.ERROR)
    return false
  end
  if vim.api and type(vim.api.nvim_set_hl) == "function" then
    pcall(vim.api.nvim_set_hl, 0, "CoduxMissionPreviewCursor", { fg = "NONE", bg = "NONE", blend = 100 })
  end
  controller.ui.set_window_options(win, {
    wrap = false,
    linebreak = false,
    cursorline = false,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey,Cursor:CoduxMissionPreviewCursor,CursorIM:CoduxMissionPreviewCursor",
  })
  local sink_bufnr
  local sink_win
  local closed = false

  local function close_preview()
    if closed then
      return false
    end
    closed = true
    controller.ui.close_window(win)
    controller.ui.close_window(sink_win)
    controller.ui.delete_buffer(bufnr)
    controller.ui.delete_buffer(sink_bufnr)
    return true
  end

  local function defer_preview_action(action)
    local function run()
      if not close_preview() then
        return false
      end
      if type(action) == "function" then
        return action()
      end
      return true
    end

    if type(vim.schedule) == "function" then
      vim.schedule(run)
      return true
    end

    return run()
  end

  local function launch_mission()
    return defer_preview_action(function()
      if controller.create_mission(mission) then
        return controller:refresh_or_open_dashboard()
      end
      return false
    end)
  end

  local function edit_mission()
    return defer_preview_action(function()
      return controller:open_objective_editor(mission.name, mission.objective)
    end)
  end

  local sink_error
  sink_bufnr, sink_win, sink_error = ui.open_hidden_command_sink({
    ui = controller.ui,
    filetype = "codux-mission-preview-sink",
    enter = true,
    focusable = true,
    bind = function(target_bufnr)
      controller.set_buffer_keymap(target_bufnr, "n", "y", launch_mission, "Launch Codux Mission", { nowait = true })
      controller.set_buffer_keymap(target_bufnr, "n", "n", defer_preview_action, "Cancel Codux Mission", { nowait = true })
      controller.set_buffer_keymap(target_bufnr, "n", "e", edit_mission, "Edit Codux Mission Instruction", { nowait = true })
      controller.bind_close_keys(target_bufnr, defer_preview_action, "Cancel Codux Mission", "n", { escape = true, q = true })
    end,
  })
  if not sink_bufnr then
    controller.ui.close_window(win)
    controller.ui.delete_buffer(bufnr)
    controller.notify(
      sink_error == "open" and "Failed to open Codux mission preview" or "Failed to create Codux mission preview",
      vim.log.levels.ERROR
    )
    return false
  end
  return true
end

return M
