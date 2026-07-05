local text_util = require("codux.text")

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

function M.disable_buffer_completion(bufnr, opts)
  opts = type(opts) == "table" and opts or {}
  local is_loaded_buf = type(opts.is_loaded_buf) == "function" and opts.is_loaded_buf or M.is_loaded_buf
  if not is_loaded_buf(bufnr) then
    return false
  end

  for _, option in ipairs({ "complete", "completefunc", "omnifunc", "thesaurusfunc", "tagfunc", "dictionary" }) do
    pcall(vim.api.nvim_set_option_value, option, "", { buf = bufnr })
  end

  local buffer_vars = {
    blink_cmp_enabled = false,
    cmp_enabled = false,
    codux_disable_completion = true,
    completion = false,
    copilot_enabled = false,
    minicompletion_disable = true,
  }

  for key, value in pairs(buffer_vars) do
    pcall(function()
      vim.b[bufnr][key] = value
    end)
  end

  return true
end

function M.open_hidden_command_sink(opts)
  opts = type(opts) == "table" and opts or {}
  local ui_impl = type(opts.ui) == "table" and opts.ui or M
  local open_win = type(opts.open_win) == "function" and opts.open_win or vim.api.nvim_open_win
  local bufnr = ui_impl.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = opts.filetype,
    buftype = "nofile",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    return nil, nil, "create"
  end

  if type(opts.on_create_buffer) == "function" then
    opts.on_create_buffer(bufnr)
  end

  local focusable = opts.focusable == true
  local win_ok, win = pcall(open_win, bufnr, opts.enter == true, {
    relative = "editor",
    style = "minimal",
    border = "none",
    width = 1,
    height = 1,
    col = vim.o.columns + 1,
    row = vim.o.lines + 1,
    focusable = focusable,
    zindex = 1,
  })
  if not win_ok then
    ui_impl.delete_buffer(bufnr)
    return nil, nil, "open"
  end

  ui_impl.set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
  })

  if type(opts.bind) == "function" then
    opts.bind(bufnr)
  end

  return bufnr, win
end

function M.open_scratch_float(opts)
  opts = type(opts) == "table" and opts or {}
  local ui_impl = type(opts.ui) == "table" and opts.ui or M
  local create_scratch_buffer = type(ui_impl.create_scratch_buffer) == "function" and ui_impl.create_scratch_buffer
    or M.create_scratch_buffer
  local set_lines = type(ui_impl.set_lines) == "function" and ui_impl.set_lines or M.set_lines
  local set_window_options = type(ui_impl.set_window_options) == "function" and ui_impl.set_window_options
    or M.set_window_options
  local delete_buffer = type(ui_impl.delete_buffer) == "function" and ui_impl.delete_buffer or M.delete_buffer
  local close_window = type(ui_impl.close_window) == "function" and ui_impl.close_window or M.close_window
  local bind_close_keys = type(ui_impl.bind_close_keys) == "function" and ui_impl.bind_close_keys or M.bind_close_keys
  local open_win = type(opts.open_win) == "function" and opts.open_win or vim.api.nvim_open_win

  local bufnr = create_scratch_buffer(opts.buffer_options or {
    bufhidden = "wipe",
    buftype = "nofile",
    swapfile = false,
  })
  if not bufnr then
    return nil, "create"
  end

  if type(opts.on_create_buffer) == "function" then
    opts.on_create_buffer(bufnr)
  end
  if type(opts.lines) == "table" then
    set_lines(bufnr, opts.lines, { modifiable = opts.modifiable == true })
  end

  local config = opts.config
  if type(config) == "function" then
    config = config()
  end
  if type(config) ~= "table" then
    config = {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      width = math.min(60, math.max(1, vim.o.columns - 4)),
      height = 1,
      col = 2,
      row = 2,
    }
  end

  local win_ok, win = pcall(open_win, bufnr, opts.enter == true, config)
  if not win_ok then
    delete_buffer(bufnr)
    return nil, "open"
  end

  if type(opts.window_options) == "table" then
    set_window_options(win, opts.window_options)
  end

  local closed = false
  local handle = {
    bufnr = bufnr,
    win = win,
  }
  function handle.close()
    if closed then
      return false
    end
    closed = true
    close_window(win)
    delete_buffer(bufnr)
    return true
  end

  if type(opts.close) == "function" then
    bind_close_keys(bufnr, opts.close, opts.close_desc or "Close Codux Window", opts.close_modes or "n", opts.close_opts)
  end

  return handle, nil
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

local function display_width(value)
  return text_util.display_width(value)
end

function M.key_choice_lines(choices)
  local lines = {}
  for _, choice in ipairs(type(choices) == "table" and choices or {}) do
    local key = tostring(choice.key or "")
    local label = tostring(choice.label or "")
    if key ~= "" and label ~= "" then
      table.insert(lines, key .. " - " .. label)
    end
  end
  return lines
end

function M.key_choice_menu(opts, callback, deps)
  opts = type(opts) == "table" and opts or {}
  deps = type(deps) == "table" and deps or {}
  callback = type(callback) == "function" and callback or function() end
  local notify = type(deps.notify) == "function" and deps.notify or function(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "codux.nvim" })
  end
  local create_scratch_buffer = type(deps.create_scratch_buffer) == "function" and deps.create_scratch_buffer
    or M.create_scratch_buffer
  local set_lines = type(deps.set_lines) == "function" and deps.set_lines or M.set_lines
  local set_window_options = type(deps.set_window_options) == "function" and deps.set_window_options or M.set_window_options
  local delete_buffer = type(deps.delete_buffer) == "function" and deps.delete_buffer or M.delete_buffer
  local close_window = type(deps.close_window) == "function" and deps.close_window or M.close_window
  local set_keymap = type(deps.set_buffer_keymap) == "function" and deps.set_buffer_keymap or M.set_keymap
  local bind_close_keys = type(deps.bind_close_keys) == "function" and deps.bind_close_keys or M.bind_close_keys
  local open_win = type(deps.open_win) == "function" and deps.open_win or vim.api.nvim_open_win
  local choices = type(opts.choices) == "table" and opts.choices or {}
  local lines = M.key_choice_lines(choices)
  local width = display_width(tostring(opts.title or ""))

  for _, line in ipairs(lines) do
    width = math.max(width, display_width(line))
  end
  width = math.min(math.max(width + 4, 20), math.max(20, vim.o.columns - 4))

  local closed = false
  local win
  local sink_win
  local sink_bufnr
  local sink_error
  local bufnr = create_scratch_buffer({
    bufhidden = "wipe",
    buftype = "nofile",
    filetype = opts.filetype or "codux-key-choice",
    swapfile = false,
    modifiable = false,
  })
  if not bufnr then
    notify(opts.create_error or "Failed to create Codux menu", vim.log.levels.ERROR)
    return false
  end

  local function close_menu(choice)
    if closed then
      return false
    end
    closed = true
    close_window(win)
    close_window(sink_win)
    delete_buffer(bufnr)
    delete_buffer(sink_bufnr)
    callback(choice)
    return true
  end

  set_lines(bufnr, lines, { modifiable = true })
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local height = math.max(1, #lines)
  local win_ok, winid = pcall(open_win, bufnr, false, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = opts.title or " Codux ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2) - 2),
    focusable = false,
    zindex = opts.zindex or 60,
  })
  if not win_ok then
    delete_buffer(bufnr)
    notify(opts.open_error or "Failed to open Codux menu", vim.log.levels.ERROR)
    return false
  end
  win = winid

  if vim.api and type(vim.api.nvim_set_hl) == "function" then
    pcall(vim.api.nvim_set_hl, 0, "CoduxKeyChoiceCursor", { fg = "NONE", bg = "NONE", blend = 100 })
  end
  set_window_options(win, {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    winfixbuf = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey,Cursor:CoduxKeyChoiceCursor,CursorIM:CoduxKeyChoiceCursor",
  })

  sink_bufnr, sink_win, sink_error = M.open_hidden_command_sink({
    ui = {
      create_scratch_buffer = create_scratch_buffer,
      delete_buffer = delete_buffer,
      set_window_options = set_window_options,
    },
    filetype = (opts.filetype or "codux-key-choice") .. "-sink",
    enter = true,
    focusable = true,
    open_win = open_win,
    bind = function(target_bufnr)
      bind_close_keys(target_bufnr, function()
        return close_menu(nil)
      end, opts.cancel_desc or "Cancel Codux Menu", "n", { escape = true, q = true })
      for _, choice in ipairs(choices) do
        local key = choice.key
        if type(key) == "string" and key ~= "" then
          local bound_choice = choice
          set_keymap(target_bufnr, "n", key, function()
            return close_menu(bound_choice)
          end, tostring(choice.desc or choice.label or "Select Codux Menu Item"), { nowait = true })
        end
      end
    end,
  })
  if not sink_bufnr then
    close_window(win)
    delete_buffer(bufnr)
    if sink_error == "open" then
      notify(opts.open_error or "Failed to open Codux menu", vim.log.levels.ERROR)
    else
      notify(opts.create_error or "Failed to create Codux menu", vim.log.levels.ERROR)
    end
    return false
  end

  return true
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
  local insert_input = opts.insert_input == true
  local allowed_chars
  if type(opts.allowed_chars) == "string" then
    allowed_chars = {}
    for index = 1, #opts.allowed_chars do
      allowed_chars[opts.allowed_chars:sub(index, index)] = true
    end
  end
  local max_length = tonumber(opts.max_length)
  if max_length ~= nil then
    max_length = math.max(0, math.floor(max_length))
  end
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

    local display_value = insert_input and value or value .. " "
    M.set_lines(bufnr, { display_value })
    if M.is_valid_win(win) then
      local cursor_col = insert_input and #display_value or #value
      pcall(vim.api.nvim_win_set_cursor, win, { 1, math.min(cursor_col, math.max(0, width - 1)) })
    end
    return true
  end

  local function submitted_value()
    local lines = M.buffer_lines(bufnr, 0, 1)
    local line = type(lines) == "table" and tostring(lines[1] or "") or value
    if line:sub(-1) == " " then
      line = line:sub(1, -2)
    end
    return line
  end

  local function close_prompt(result)
    if closed then
      return false
    end
    closed = true
    if insert_input then
      pcall(vim.cmd, "stopinsert")
    end
    if M.is_valid_win(win) then
      M.close_window(win)
    end
    M.delete_buffer(bufnr)
    callback(result)
    return true
  end

  local function can_append_input(input)
    if allowed_chars and allowed_chars[input] ~= true then
      return false
    end
    if max_length ~= nil and vim.fn.strchars(value) >= max_length then
      return false
    end
    return true
  end

  bufnr = M.create_scratch_buffer({
    bufhidden = "wipe",
    buftype = "nofile",
    filetype = opts.filetype or "codux-prompt",
    swapfile = false,
    modifiable = true,
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
  end, "Cancel Codux Prompt", insert_input and { "n", "i" } or "n", { escape = true })
  set_keymap(bufnr, insert_input and { "n", "i" } or "n", "<CR>", function()
    return close_prompt(submitted_value())
  end, "Submit Codux Prompt")
  if not insert_input then
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
    local function append_prompt_input(input)
      if not can_append_input(input) then
        return true
      end
      value = value .. input
      return render()
    end
    for _, key in ipairs(M.printable_prompt_keys()) do
      local lhs = key[1]
      local input = key[2]
      set_keymap(bufnr, "n", lhs, function()
        return append_prompt_input(input)
      end, "Type in Codux Prompt", { nowait = true })
    end
    if type(vim.g) == "table" and vim.g.mapleader == " " then
      set_keymap(bufnr, "n", "<Leader>", function()
        return append_prompt_input(" ")
      end, "Type in Codux Prompt", { nowait = true })
    end
  end

  render()
  if insert_input then
    pcall(vim.cmd, "startinsert")
  end
  return true
end

return M
