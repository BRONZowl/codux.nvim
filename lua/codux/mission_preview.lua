local ui = require("codux.ui")

local M = {}

local function create_footer_segments(controller)
  return controller.workspace_ui.create_footer_segments()
end

local function create_footer_line(controller)
  return controller.workspace_ui.footer_line(create_footer_segments(controller))
end

local function render_footer(controller, bufnr, width)
  if not controller.is_loaded_buf(bufnr) then
    return false
  end

  width = type(width) == "number" and width > 0 and width or 1
  local line = create_footer_line(controller)
  local padding = math.max(0, math.floor((width - #line) / 2))
  local text = string.rep(" ", padding) .. line

  controller.ui.set_lines(bufnr, { text }, { modifiable = true })
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, controller.namespace, 0, -1)

  local col = padding
  local segments = create_footer_segments(controller)
  for index, segment in ipairs(segments) do
    local key_end = col + #segment.key
    pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "WhichKey", 0, col, key_end)
    local desc_end = key_end + 1 + #segment.desc
    pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "WhichKeySeparator", 0, key_end, desc_end)
    col = desc_end
    if index < #segments then
      col = col + 2
    end
  end

  return true
end

local function open_footer(controller, win)
  if not controller.is_valid_win(win) then
    return nil, nil
  end

  local bufnr = controller.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-mission-preview-footer",
    modifiable = false,
  })
  if not bufnr then
    return nil, nil
  end

  local height_ok, height = pcall(vim.api.nvim_win_get_height, win)
  local width_ok, width = pcall(vim.api.nvim_win_get_width, win)
  height = height_ok and type(height) == "number" and height > 0 and height or 1
  width = width_ok and type(width) == "number" and width > 0 and width or 1

  local win_ok, footer_win = pcall(vim.api.nvim_open_win, bufnr, false, {
    relative = "win",
    win = win,
    col = 0,
    row = height - 1,
    width = width,
    height = 1,
    border = "none",
    style = "minimal",
    zindex = 81,
  })
  if not win_ok then
    controller.ui.delete_buffer(bufnr)
    return nil, nil
  end

  render_footer(controller, bufnr, width)
  return bufnr, footer_win
end

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

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, preview_config)
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
  local footer_bufnr, footer_win = open_footer(controller, win)
  local closed = false

  local function close_preview()
    if closed then
      return false
    end
    closed = true
    controller.ui.close_window(footer_win)
    controller.ui.delete_buffer(footer_bufnr)
    controller.ui.close_window(win)
    controller.ui.delete_buffer(bufnr)
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

  controller.set_buffer_keymap(bufnr, "n", "<CR>", launch_mission, "Create Codux Mission", { nowait = true })
  controller.set_buffer_keymap(bufnr, "n", "e", edit_mission, "Edit Codux Mission Instruction", { nowait = true })
  controller.bind_close_keys(bufnr, defer_preview_action, "Cancel Codux Mission", "n", { escape = true, q = true })
  return true
end

return M
