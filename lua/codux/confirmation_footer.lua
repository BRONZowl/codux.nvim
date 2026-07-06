local M = {}

local function footer_segments(opts)
  opts = type(opts) == "table" and opts or {}
  return type(opts.segments) == "table" and opts.segments or {}
end

function M.line(controller, opts)
  return controller.workspace_ui.footer_line(footer_segments(opts))
end

function M.render(controller, bufnr, opts)
  opts = type(opts) == "table" and opts or {}
  if not controller.is_loaded_buf(bufnr) then
    return false
  end

  local segments = footer_segments(opts)
  local width = type(opts.width) == "number" and opts.width > 0 and opts.width or 1
  local line = M.line(controller, opts)
  local padding = math.max(0, math.floor((width - #line) / 2))
  local text = string.rep(" ", padding) .. line

  controller.ui.set_lines(bufnr, { text }, { modifiable = true })
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, controller.namespace, 0, -1)

  local col = padding
  for index, segment in ipairs(segments) do
    local key = tostring(segment.key or "")
    local desc = tostring(segment.desc or "")
    local key_end = col + #key
    pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "WhichKey", 0, col, key_end)
    local desc_end = key_end + 1 + #desc
    pcall(vim.api.nvim_buf_add_highlight, bufnr, controller.namespace, "WhichKeySeparator", 0, key_end, desc_end)
    col = desc_end
    if index < #segments then
      col = col + 2
    end
  end

  return true
end

function M.open(controller, win, opts)
  opts = type(opts) == "table" and opts or {}
  if not controller.is_valid_win(win) then
    return nil, nil
  end

  local bufnr = controller.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = opts.filetype,
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
    zindex = opts.zindex,
  })
  if not win_ok then
    controller.ui.delete_buffer(bufnr)
    return nil, nil
  end

  M.render(controller, bufnr, {
    width = width,
    segments = footer_segments(opts),
  })
  return bufnr, footer_win
end

return M
