local M = {}

function M.is_valid_buf(bufnr)
  if type(bufnr) ~= "number" then
    return false
  end

  local ok, valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
  return ok and valid == true
end

function M.is_loaded_buf(bufnr)
  if not M.is_valid_buf(bufnr) then
    return false
  end

  local ok, loaded = pcall(vim.api.nvim_buf_is_loaded, bufnr)
  return ok and loaded == true
end

function M.is_valid_win(winid)
  if type(winid) ~= "number" then
    return false
  end

  local ok, valid = pcall(vim.api.nvim_win_is_valid, winid)
  return ok and valid == true
end

function M.window_buffer(winid)
  if not M.is_valid_win(winid) then
    return nil
  end

  local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
  if ok and type(bufnr) == "number" then
    return bufnr
  end

  return nil
end

function M.buffer_filetype(bufnr)
  if not M.is_loaded_buf(bufnr) then
    return nil
  end

  local ok, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
  if ok then
    return filetype
  end

  return nil
end

function M.buffer_lines(bufnr, start_line, end_line)
  if not M.is_loaded_buf(bufnr) then
    return nil
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, end_line, false)
  if ok then
    return lines
  end

  return nil
end

function M.set_buffer_options(bufnr, options)
  if type(options) ~= "table" then
    return
  end

  for option, value in pairs(options) do
    pcall(vim.api.nvim_set_option_value, option, value, { buf = bufnr })
  end
end

function M.set_window_options(winid, options)
  if type(options) ~= "table" then
    return
  end

  for option, value in pairs(options) do
    pcall(vim.api.nvim_set_option_value, option, value, { win = winid })
  end
end

function M.delete_buffer(bufnr, opts)
  if M.is_loaded_buf(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, opts or { force = true })
  end
end

function M.close_window(winid, force)
  if M.is_valid_win(winid) then
    pcall(vim.api.nvim_win_close, winid, force ~= false)
  end
end

function M.create_scratch_buffer(options)
  local ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not ok or not M.is_loaded_buf(bufnr) then
    return nil
  end

  M.set_buffer_options(bufnr, options)
  return bufnr
end

function M.set_lines(bufnr, lines, opts)
  if not M.is_loaded_buf(bufnr) then
    return false
  end

  opts = type(opts) == "table" and opts or {}
  if opts.modifiable then
    pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = bufnr })
  end
  local ok = pcall(vim.api.nvim_buf_set_lines, bufnr, opts.start_line or 0, opts.end_line or -1, false, lines)
  if opts.modifiable then
    pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })
  end
  return ok
end

function M.set_keymap(bufnr, modes, lhs, rhs, desc, opts)
  opts = type(opts) == "table" and opts or {}
  return pcall(vim.keymap.set, modes, lhs, rhs, {
    buffer = bufnr,
    nowait = opts.nowait == true,
    silent = opts.silent ~= false,
    desc = desc,
  })
end

function M.bind_close_keys(bufnr, close_fn, desc, modes, opts)
  modes = modes or "n"
  M.set_keymap(bufnr, modes, "<C-q>", close_fn, desc, opts)
  if opts and opts.escape then
    M.set_keymap(bufnr, modes, "<Esc>", close_fn, desc, opts)
  end
  if opts and opts.q then
    M.set_keymap(bufnr, modes, "q", close_fn, desc, opts)
  end
end

function M.printable_prompt_keys()
  local keys = { { "<Space>", " " } }

  for code = string.byte("a"), string.byte("z") do
    local char = string.char(code)
    table.insert(keys, { char, char })
    table.insert(keys, { char:upper(), char:upper() })
  end

  for code = string.byte("0"), string.byte("9") do
    local char = string.char(code)
    table.insert(keys, { char, char })
  end

  for _, char in ipairs({
    "!",
    '"',
    "#",
    "$",
    "%",
    "&",
    "'",
    "(",
    ")",
    "*",
    "+",
    ",",
    "-",
    ".",
    "/",
    ":",
    ";",
    "=",
    ">",
    "?",
    "@",
    "[",
    "\\",
    "]",
    "^",
    "_",
    "`",
    "{",
    "|",
    "}",
    "~",
  }) do
    table.insert(keys, { char, char })
  end

  table.insert(keys, { "<lt>", "<" })

  return keys
end

function M.single_line_prompt(opts, callback, deps)
  opts = type(opts) == "table" and opts or {}
  deps = type(deps) == "table" and deps or {}
  callback = type(callback) == "function" and callback or function() end
  local notify = type(deps.notify) == "function" and deps.notify or function(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "codux.nvim" })
  end
  local set_keymap = type(deps.set_buffer_keymap) == "function" and deps.set_buffer_keymap or M.set_keymap
  local bind_close_keys = type(deps.bind_close_keys) == "function" and deps.bind_close_keys or M.bind_close_keys
  local prompt = tostring(opts.prompt or "")
  local value = tostring(opts.default or "")
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local prompt_width_ok, prompt_width = pcall(vim.fn.strdisplaywidth, prompt)
  prompt_width = prompt_width_ok and type(prompt_width) == "number" and prompt_width or #prompt
  local min_width = math.max(24, prompt_width + 12)
  local width = math.min(58, math.max(min_width, math.floor(total_width * 0.38)))
  local closed = false
  local bufnr
  local win

  local function render()
    if not M.is_loaded_buf(bufnr) then
      return false
    end

    M.set_lines(bufnr, { value .. " " }, { modifiable = true })
    if M.is_valid_win(win) then
      pcall(vim.api.nvim_win_set_cursor, win, { 1, math.min(#value, math.max(0, width - 1)) })
    end
    return true
  end

  local function close_prompt(result)
    if closed then
      return false
    end
    closed = true
    if M.is_valid_win(win) then
      M.close_window(win)
    end
    M.delete_buffer(bufnr)
    callback(result)
    return true
  end

  bufnr = M.create_scratch_buffer({
    bufhidden = "wipe",
    buftype = "nofile",
    filetype = opts.filetype or "codux-prompt",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    notify("Failed to create Codux prompt", vim.log.levels.ERROR)
    return false
  end
  if type(opts.on_create_buffer) == "function" then
    pcall(opts.on_create_buffer, bufnr)
  end

  local win_ok, created_win = pcall(vim.api.nvim_open_win, bufnr, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " " .. prompt,
    title_pos = "center",
    width = width,
    height = 1,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - 1) / 2) - 2),
    zindex = opts.zindex or 60,
  })
  if not win_ok then
    M.delete_buffer(bufnr)
    notify("Failed to open Codux prompt", vim.log.levels.ERROR)
    return false
  end
  win = created_win

  M.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })

  bind_close_keys(bufnr, function()
    return close_prompt(nil)
  end, "Cancel Codux Prompt", "n", { escape = true })
  set_keymap(bufnr, "n", "<CR>", function()
    return close_prompt(value)
  end, "Submit Codux Prompt")
  set_keymap(bufnr, "n", "<BS>", function()
    local length = vim.fn.strchars(value)
    if length > 0 then
      value = vim.fn.strcharpart(value, 0, length - 1)
      return render()
    end
    return true
  end, "Delete Codux Prompt Character", { nowait = true })
  set_keymap(bufnr, "n", "<C-h>", function()
    local length = vim.fn.strchars(value)
    if length > 0 then
      value = vim.fn.strcharpart(value, 0, length - 1)
      return render()
    end
    return true
  end, "Delete Codux Prompt Character", { nowait = true })
  set_keymap(bufnr, "n", "<C-u>", function()
    value = ""
    return render()
  end, "Clear Codux Prompt", { nowait = true })
  for _, key in ipairs(M.printable_prompt_keys()) do
    local lhs = key[1]
    local input = key[2]
    set_keymap(bufnr, "n", lhs, function()
      value = value .. input
      return render()
    end, "Type in Codux Prompt", { nowait = true })
  end

  render()
  return true
end

return M
