local ui = require("codux.ui")

local M = {}

function M.highlight(controller, bufnr, lines, items)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, controller.namespace, 0, -1)
  for index, line in ipairs(lines or {}) do
    pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "Comment", index - 1, 0, -1)
    local search_start = 1
    for _, item in ipairs(items or {}) do
      local key = tostring(item.key or "")
      local label = tostring(item.label or "")
      local pair = key .. " " .. label
      local pair_start = line:find(pair, search_start, true)
      if pair_start then
        local key_start = pair_start - 1
        local label_start = pair_start + #key
        pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "WhichKey", index - 1, key_start, key_start + #key)
        pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "Comment", index - 1, label_start, label_start + #label)
        search_start = pair_start + #pair
      end
    end
  end
end

function M.render(controller)
  if not controller.is_loaded_buf(controller.state.mission_dashboard.command_bar_buf) then
    return false
  end
  local width = controller:window_width() or controller:dashboard_config(1).width
  local lines = controller:dashboard_command_lines(width)
  controller.ui.set_lines(controller.state.mission_dashboard.command_bar_buf, lines, { modifiable = true })
  controller:highlight_command_bar(controller.state.mission_dashboard.command_bar_buf, lines)
  return true
end

function M.open(controller)
  if not controller.is_valid_win(controller.state.mission_dashboard.win) then
    return false
  end
  if
    controller.is_valid_win(controller.state.mission_dashboard.command_bar_win)
    and controller.is_loaded_buf(controller.state.mission_dashboard.command_bar_buf)
  then
    return controller:render_command_bar()
  end

  local lines = controller:dashboard_command_lines(controller:window_width() or controller:dashboard_config(1).width)
  local bufnr = controller.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-missions-commands",
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    controller.notify("Failed to create Codux mission commands", vim.log.levels.ERROR)
    return false
  end
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })
  controller.ui.set_lines(bufnr, lines, { modifiable = true })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, controller:dashboard_command_config(#lines))
  if not win_ok then
    controller.ui.delete_buffer(bufnr)
    controller.notify("Failed to open Codux mission commands", vim.log.levels.ERROR)
    return false
  end

  controller.state.mission_dashboard.command_bar_buf = bufnr
  controller.state.mission_dashboard.command_bar_win = win
  controller.ui.set_window_options(win, {
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  controller:highlight_command_bar(bufnr, lines)

  local group = vim.api.nvim_create_augroup("codux-mission-commands-" .. tostring(bufnr), { clear = true })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if controller.state.mission_dashboard.command_bar_buf == bufnr then
        controller.state.mission_dashboard.command_bar_buf = nil
        controller.state.mission_dashboard.command_bar_win = nil
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  return true
end

function M.close(controller)
  controller.ui.close_window(controller.state.mission_dashboard.command_bar_win)
  controller.ui.delete_buffer(controller.state.mission_dashboard.command_bar_buf)
  controller.state.mission_dashboard.command_bar_win = nil
  controller.state.mission_dashboard.command_bar_buf = nil
  return true
end

return M
