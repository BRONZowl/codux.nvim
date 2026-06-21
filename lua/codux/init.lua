local M = {}

local defaults = {
  codex_cmd = vim.env.CODEX_CMD or 'codex -s workspace-write -a on-request -c approvals_reviewer="user"',
  workspace_auto_cmd = vim.env.CODEX_WORKSPACE_AUTO_CMD
    or 'codex -s workspace-write -a on-request -c approvals_reviewer="auto_review"',
  danger_full_access_cmd = vim.env.CODEX_DANGER_FULL_ACCESS_CMD or "codex -s danger-full-access -a never",
  auto_open = true,
  auto_focus = true,
  popup = {
    width = 0.85,
    height = 0.85,
    border = "rounded",
    lock_focus = true,
  },
  working_idle_ms = 3000,
  health_timeout_ms = 10000,
  token_monitor = {
    enabled = true,
    refresh_ms = 60000,
    timeout_ms = 5000,
  },
  workspaces = {
    enabled = true,
    tmux_cmd = vim.env.TMUX_CMD or "tmux",
    state_file = nil,
  },
  mappings = {
    open = "<leader>zc",
    open_auto = "<leader>za",
    open_danger = "<leader>zA",
    review_file = "<leader>zf",
    review_selection = "<leader>zs",
    diagnostics = "<leader>zd",
    diff = "<leader>zg",
    workspace = "<leader>zw",
    workspaces = "<leader>zW",
    mode = "<leader>zp",
  },
  prompts = {
    file = "Review this %{target_type}, identify issues, and suggest or make fixes where appropriate: %{path}",
    review_selection = "Review this selected code from %{relative_path}%{line_range} (%{filetype}):\n\n%{selection}",
    diagnostics = "Explain these %{diagnostics_source} issues for %{relative_path}, identify the likely causes, and suggest fixes:\n\n%{diagnostics}",
    git_diff = "Review these Git changes on branch %{git_branch} in %{relative_path}. Identify issues, risks, and concrete improvements:\n\n%{git_diff}",
  },
  explorers = {
    neo_tree = true,
    oil = true,
    nvim_tree = true,
    mini_files = true,
  },
  target_providers = {},
}

local config = vim.deepcopy(defaults)
local state = {
  buf = nil,
  win = nil,
  job_id = nil,
  mode = "not running",
  working_buf = nil,
  working_win = nil,
  working_timer = nil,
  working_idle_timer = nil,
  working_frame = 1,
  codex_working = false,
  last_working_activity = 0,
  token_usage = {
    five_hour_percent = nil,
    weekly_percent = nil,
    last_error = nil,
    in_flight = false,
    job_id = nil,
    stdout = "",
    initialized = false,
    timeout_timer = nil,
  },
  terminal_attached_buf = nil,
  terminal_command_tail = "",
  permission_profile = "default",
  last_permission_profile = "default",
  workspace = nil,
  workspace_manager_buf = nil,
  workspace_manager_win = nil,
  workspace_manager_footer_buf = nil,
  workspace_manager_footer_win = nil,
  workspace_manager_items = {},
  workspace_manager_project_root = nil,
  closing_popup = false,
  focus_lock_pending = false,
  focus_lock_autocmd = nil,
  exiting_jobs = {},
  pending_delete_buffers = {},
}

local augroup = vim.api.nvim_create_augroup("codux.nvim", { clear = true })
local refresh_which_key
local update_terminal_mode_mapping
local update_working_indicator
local close_working_indicator
local set_codex_working
local refresh_which_key_header
local refresh_token_usage
local start_token_monitor_timer
local stop_token_monitor_timer
local current_target
local git_branch_for
local git_root_for
local codux_icon = "󰚩"
local which_key_header_hooked = false

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "codux.nvim" })
end

local function set_mode(mode)
  if state.mode == mode then
    return
  end

  state.mode = mode
  if type(refresh_which_key_header) == "function" then
    refresh_which_key_header()
  end
end

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function system(args, input)
  local output = vim.fn.system(args, input)
  return output, vim.v.shell_error
end

local function system_with_timeout(args, timeout_ms)
  if vim.system then
    local ok, result = pcall(function()
      return vim.system(args, { text = true, timeout = timeout_ms }):wait()
    end)
    if not ok then
      return tostring(result), 124
    end

    return (result.stdout or "") .. (result.stderr or ""), result.code or 0
  end

  return system(args)
end

local function is_valid_buf(bufnr)
  if type(bufnr) ~= "number" then
    return false
  end

  local ok, valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
  return ok and valid == true
end

local function is_loaded_buf(bufnr)
  if not is_valid_buf(bufnr) then
    return false
  end

  local ok, loaded = pcall(vim.api.nvim_buf_is_loaded, bufnr)
  return ok and loaded == true
end

local function is_valid_win(winid)
  if type(winid) ~= "number" then
    return false
  end

  local ok, valid = pcall(vim.api.nvim_win_is_valid, winid)
  return ok and valid == true
end

local function valid_buf()
  return is_loaded_buf(state.buf)
end

local function clear_stale_buffer()
  if state.buf ~= nil and not is_valid_buf(state.buf) then
    state.buf = nil
  end
end

local function window_buffer(winid)
  if not is_valid_win(winid) then
    return nil
  end

  local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
  if ok and type(bufnr) == "number" then
    return bufnr
  end

  return nil
end

local function valid_win()
  local bufnr = window_buffer(state.win)
  return bufnr ~= nil and bufnr == state.buf and valid_buf()
end

local function buffer_filetype(bufnr)
  if not is_loaded_buf(bufnr) then
    return nil
  end

  local ok, filetype = pcall(vim.api.nvim_get_option_value, "filetype", { buf = bufnr })
  if ok then
    return filetype
  end

  return nil
end

local function current_filetype()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = buffer_filetype(bufnr)
  if filetype == nil or filetype == "" then
    return "unknown"
  end

  return filetype
end

local function current_buffer_name()
  local bufnr = vim.api.nvim_get_current_buf()
  if not is_valid_buf(bufnr) then
    return ""
  end

  local ok, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  if ok and type(name) == "string" then
    return name
  end

  return ""
end

local function buffer_lines(bufnr, start_line, end_line)
  if not is_loaded_buf(bufnr) then
    return nil
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, end_line, false)
  if ok then
    return lines
  end

  return nil
end

local function delete_buffer_deferred(bufnr)
  if not is_valid_buf(bufnr) then
    return
  end

  vim.defer_fn(function()
    if is_valid_buf(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end, 100)
end

local function terminal_running()
  if state.job_id == nil then
    if type(stop_token_monitor_timer) == "function" then
      stop_token_monitor_timer()
    end
    set_codex_working(false)
    set_mode("not running")
    return false
  end

  if not valid_buf() then
    pcall(vim.fn.jobstop, state.job_id)
    state.exiting_jobs[state.job_id] = nil
    state.job_id = nil
    if type(stop_token_monitor_timer) == "function" then
      stop_token_monitor_timer()
    end
    set_codex_working(false)
    set_mode("not running")
    return false
  end

  local wait_ok, statuses = pcall(vim.fn.jobwait, { state.job_id }, 0)
  if not wait_ok or type(statuses) ~= "table" then
    state.exiting_jobs[state.job_id] = nil
    state.job_id = nil
    if type(stop_token_monitor_timer) == "function" then
      stop_token_monitor_timer()
    end
    set_codex_working(false)
    set_mode("not running")
    return false
  end

  local status = statuses[1]
  if status == -1 then
    return true
  end

  state.job_id = nil
  if type(stop_token_monitor_timer) == "function" then
    stop_token_monitor_timer()
  end
  set_codex_working(false)
  set_mode("not running")
  return false
end

local function focus_terminal_prompt(input)
  if not valid_win() then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(state.buf)
  pcall(vim.api.nvim_win_set_cursor, state.win, { line_count, 0 })
  pcall(vim.cmd, "startinsert")

  if type(input) == "string" and input ~= "" and terminal_running() then
    pcall(vim.fn.chansend, state.job_id, input)
  end

  return true
end

local function toggle_mode_state()
  set_mode(state.mode == "plan" and "execute" or "plan")
  notify("Codex mode: " .. state.mode)
end

local function send_mode_toggle_sequence(sequence)
  if not terminal_running() then
    notify("Codex terminal is not running", vim.log.levels.WARN)
    return false
  end

  local send_ok, sent = pcall(vim.fn.chansend, state.job_id, sequence)
  if not send_ok or sent == 0 then
    notify("Failed to toggle Codex plan mode", vim.log.levels.ERROR)
    return false
  end

  toggle_mode_state()
  return true
end

local function send_mode_toggle_to_codex()
  return send_mode_toggle_sequence("\27[200~/plan\27[201~\r")
end

local function send_shift_tab_mode_toggle_to_codex()
  return send_mode_toggle_sequence("\27[Z")
end

local function reset_terminal_command_tail()
  state.terminal_command_tail = ""
end

local function append_terminal_command_tail(input)
  state.terminal_command_tail = ((state.terminal_command_tail or "") .. input):sub(-5)
end

local function terminal_tail_key(input)
  return function()
    if not terminal_running() then
      return false
    end

    append_terminal_command_tail(input)
    local send_ok, sent = pcall(vim.fn.chansend, state.job_id, input)
    return send_ok and sent ~= 0
  end
end

local function terminal_prompt_key(input)
  return function()
    return focus_terminal_prompt(input)
  end
end

local function printable_prompt_keys()
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

local function focus_window()
  if not valid_win() then
    return false
  end

  local focus_ok = pcall(vim.api.nvim_set_current_win, state.win)
  if not focus_ok then
    state.win = nil
    return false
  end
  if terminal_running() then
    focus_terminal_prompt()
  end

  return true
end

local function dimension(value, total, fallback)
  if type(value) == "number" then
    if value > 0 and value < 1 then
      return math.max(1, math.floor(total * value))
    end
    if value >= 1 then
      return math.max(1, math.floor(value))
    end
  end

  return math.max(1, math.floor(total * fallback))
end

local function popup_config()
  local popup = config.popup or {}
  local total_width = vim.o.columns
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local has_border = popup.border ~= nil and popup.border ~= "none"
  local available_width = math.max(1, total_width - (has_border and 2 or 0))
  local available_height = math.max(1, total_height - (has_border and 2 or 0))
  local width = math.min(available_width, dimension(popup.width, available_width, 0.85))
  local height = math.min(available_height, dimension(popup.height, available_height, 0.85))
  local border_size = has_border and 2 or 0

  return {
    relative = "editor",
    style = "minimal",
    border = popup.border or "rounded",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width - border_size) / 2)),
    row = math.max(0, math.floor((total_height - height - border_size) / 2) - 1),
  }
end

local function popup_focus_lock_enabled()
  local popup = config.popup or {}
  return popup.lock_focus ~= false
end

local function schedule_popup_focus_lock()
  if state.closing_popup or state.focus_lock_pending then
    return
  end
  if not popup_focus_lock_enabled() or not valid_win() then
    return
  end

  state.focus_lock_pending = true
  vim.schedule(function()
    state.focus_lock_pending = false
    if state.closing_popup or not popup_focus_lock_enabled() or not valid_win() then
      return
    end

    local current_ok, current_win = pcall(vim.api.nvim_get_current_win)
    if current_ok and current_win == state.win then
      return
    end

    focus_window()
  end)
end

local working_frames = {
  " codex is working    ",
  " codex is working.   ",
  " codex is working..  ",
  " codex is working... ",
}

local function stop_working_timer()
  local timer = state.working_timer
  state.working_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

local function stop_working_idle_timer()
  local timer = state.working_idle_timer
  state.working_idle_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

close_working_indicator = function()
  stop_working_timer()

  if is_valid_win(state.working_win) then
    pcall(vim.api.nvim_win_close, state.working_win, true)
  end
  state.working_win = nil

  if is_valid_buf(state.working_buf) then
    pcall(vim.api.nvim_buf_delete, state.working_buf, { force = true })
  end
  state.working_buf = nil
  state.working_frame = 1
end

local function now_ms()
  local loop = vim.uv or vim.loop
  if loop and type(loop.now) == "function" then
    return loop.now()
  end
  if loop and type(loop.hrtime) == "function" then
    return math.floor(loop.hrtime() / 1000000)
  end

  return os.time() * 1000
end

local function working_idle_ms()
  local value = tonumber(config.working_idle_ms)
  if value == nil or value < 500 then
    return defaults.working_idle_ms
  end

  return value
end

local function start_working_idle_timer()
  if state.working_idle_timer then
    return
  end

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  state.working_idle_timer = timer
  timer:start(working_idle_ms(), 500, vim.schedule_wrap(function()
    if not state.codex_working then
      stop_working_idle_timer()
      return
    end

    if not terminal_running() then
      set_codex_working(false)
      return
    end

    if now_ms() - state.last_working_activity >= working_idle_ms() then
      set_codex_working(false)
      return
    end

    update_working_indicator()
  end))
end

set_codex_working = function(working)
  state.codex_working = working == true
  if not state.codex_working then
    state.last_working_activity = 0
    stop_working_idle_timer()
    close_working_indicator()
  else
    state.last_working_activity = now_ms()
    start_working_idle_timer()
    update_working_indicator()
  end
end

local function note_terminal_activity()
  if not state.codex_working then
    return
  end

  state.last_working_activity = now_ms()
  update_working_indicator()
end

local function attach_terminal_activity(bufnr)
  if state.terminal_attached_buf == bufnr then
    return
  end

  state.terminal_attached_buf = bufnr
  local attach_ok = pcall(vim.api.nvim_buf_attach, bufnr, false, {
    on_lines = function(_, attached_buf)
      if attached_buf == state.buf then
        vim.schedule(note_terminal_activity)
      end
    end,
    on_detach = function(_, attached_buf)
      if state.terminal_attached_buf == attached_buf then
        state.terminal_attached_buf = nil
      end
    end,
  })

  if not attach_ok then
    state.terminal_attached_buf = nil
  end
end

local function working_indicator_config()
  local width = 21
  local height = 1
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)

  return {
    relative = "editor",
    style = "minimal",
    focusable = false,
    width = width,
    height = height,
    col = math.max(0, total_width - width - 2),
    row = math.max(0, total_height - height - 1),
    border = "rounded",
    zindex = 40,
  }
end

local function render_working_indicator()
  if not is_loaded_buf(state.working_buf) then
    return
  end

  local frame = working_frames[state.working_frame] or working_frames[1]
  pcall(vim.api.nvim_buf_set_lines, state.working_buf, 0, -1, false, { frame })
end

local function ensure_working_indicator()
  if is_valid_win(state.working_win) then
    pcall(vim.api.nvim_win_set_config, state.working_win, working_indicator_config())
    return true
  end

  if not is_loaded_buf(state.working_buf) then
    local buf_ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
    if not buf_ok or not is_loaded_buf(bufnr) then
      state.working_buf = nil
      return false
    end

    state.working_buf = bufnr
    pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = bufnr })
    pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = bufnr })
  end

  render_working_indicator()
  local win_ok, win = pcall(vim.api.nvim_open_win, state.working_buf, false, working_indicator_config())
  if not win_ok then
    state.working_win = nil
    return false
  end

  state.working_win = win
  pcall(vim.api.nvim_set_option_value, "winblend", 10, { win = win })
  pcall(vim.api.nvim_set_option_value, "wrap", false, { win = win })
  return true
end

local function start_working_timer()
  if state.working_timer then
    return
  end

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  state.working_timer = timer
  timer:start(0, 450, vim.schedule_wrap(function()
    if not is_valid_win(state.working_win) then
      stop_working_timer()
      return
    end

    state.working_frame = (state.working_frame % #working_frames) + 1
    render_working_indicator()
  end))
end

local function working_activity_is_stale()
  return state.last_working_activity == 0 or now_ms() - state.last_working_activity >= working_idle_ms()
end

update_working_indicator = function()
  if state.codex_working and working_activity_is_stale() then
    set_codex_working(false)
    return
  end

  if state.codex_working and terminal_running() and not valid_win() then
    if ensure_working_indicator() then
      start_working_timer()
    end
    return
  end

  close_working_indicator()
end

local function submit_terminal_prompt()
  if not terminal_running() then
    return false
  end

  local send_ok, sent = pcall(vim.fn.chansend, state.job_id, "\r")
  if send_ok and sent ~= 0 then
    if state.terminal_command_tail == "/plan" then
      toggle_mode_state()
    else
      set_codex_working(true)
    end
    reset_terminal_command_tail()
    return true
  end

  return false
end

local function interrupt_terminal_prompt()
  if not terminal_running() then
    return false
  end

  set_codex_working(false)
  reset_terminal_command_tail()
  local send_ok, sent = pcall(vim.fn.chansend, state.job_id, "\3")
  return send_ok and sent ~= 0
end

local function ensure_buffer()
  if valid_buf() then
    return true
  end

  clear_stale_buffer()

  local create_ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not create_ok or not is_loaded_buf(bufnr) then
    state.buf = nil
    notify("Failed to create Codux terminal buffer", vim.log.levels.ERROR)
    return false
  end

  state.buf = bufnr
  pcall(vim.api.nvim_set_option_value, "bufhidden", "hide", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "filetype", "codux", { buf = bufnr })
  pcall(vim.api.nvim_buf_set_name, bufnr, "codux://codex")
  pcall(vim.keymap.set, { "n", "t" }, "<C-q>", M.close, { buffer = bufnr, silent = true, desc = "Hide Codux Popup" })
  pcall(vim.keymap.set, "t", "<CR>", submit_terminal_prompt, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = "Submit Codux Prompt",
  })
  pcall(vim.keymap.set, { "n", "t" }, "<C-c>", interrupt_terminal_prompt, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = "Interrupt Codex",
  })
  if type(update_terminal_mode_mapping) == "function" then
    update_terminal_mode_mapping()
  end
  for _, key in ipairs({
    { "/", "/" },
    { "p", "p" },
    { "l", "l" },
    { "a", "a" },
    { "n", "n" },
  }) do
    pcall(vim.keymap.set, "t", key[1], terminal_tail_key(key[2]), {
      buffer = bufnr,
      nowait = true,
      silent = true,
      desc = "Type in Codux Prompt",
    })
  end
  pcall(vim.keymap.set, { "n", "t" }, "<S-Tab>", send_shift_tab_mode_toggle_to_codex, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = "Switch Codex Mode",
  })
  pcall(vim.keymap.set, "n", "<CR>", focus_terminal_prompt, {
    buffer = bufnr,
    silent = true,
    desc = "Return to Codux Prompt",
  })
  for _, key in ipairs(printable_prompt_keys()) do
    local lhs = key[1]
    local input = key[2]
    pcall(vim.keymap.set, "n", lhs, terminal_prompt_key(input), {
      buffer = bufnr,
      silent = true,
      desc = "Type in Codux Prompt",
    })
  end
  pcall(vim.keymap.set, "n", "q", M.close, { buffer = bufnr, silent = true, desc = "Hide Codux Popup" })

  pcall(vim.api.nvim_create_autocmd, { "BufUnload", "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      if state.buf == bufnr then
        state.buf = nil
        state.job_id = nil
        set_codex_working(false)
        set_mode("not running")
      end
    end,
  })

  attach_terminal_activity(bufnr)

  return true
end

local function open_window(focus)
  if not ensure_buffer() then
    return false
  end

  if valid_win() then
    local config_ok = pcall(vim.api.nvim_win_set_config, state.win, popup_config())
    if not config_ok then
      state.win = nil
      return open_window(focus)
    end
    close_working_indicator()
    if focus then
      focus_window()
    end
    return true
  end

  state.win = nil

  local win_ok, win = pcall(vim.api.nvim_open_win, state.buf, focus == true, popup_config())
  if not win_ok then
    state.buf = nil
    if not ensure_buffer() then
      return false
    end
    win_ok, win = pcall(vim.api.nvim_open_win, state.buf, focus == true, popup_config())
  end
  if not win_ok then
    notify("Failed to open Codux popup", vim.log.levels.ERROR)
    return false
  end

  state.win = win
  state.closing_popup = false
  close_working_indicator()
  pcall(vim.api.nvim_set_option_value, "number", false, { win = state.win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = state.win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = state.win })
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = state.win })

  local win_id = state.win
  if state.focus_lock_autocmd then
    pcall(vim.api.nvim_del_autocmd, state.focus_lock_autocmd)
    state.focus_lock_autocmd = nil
  end
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(win_id),
    once = true,
    callback = function()
      if state.win == win_id then
        state.win = nil
        if state.focus_lock_autocmd then
          pcall(vim.api.nvim_del_autocmd, state.focus_lock_autocmd)
          state.focus_lock_autocmd = nil
        end
        update_working_indicator()
      end
    end,
  })
  state.focus_lock_autocmd = vim.api.nvim_create_autocmd("WinLeave", {
    group = augroup,
    callback = function()
      if state.win == win_id then
        schedule_popup_focus_lock()
      end
    end,
  })

  vim.api.nvim_clear_autocmds({ group = augroup, event = "VimResized" })
  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
      if valid_win() then
        pcall(vim.api.nvim_win_set_config, state.win, popup_config())
      end
      update_working_indicator()
    end,
  })

  if focus then
    focus_window()
  end

  return true
end

local function command_with_prompt(command, prompt)
  if type(prompt) ~= "string" or prompt == "" then
    return command
  end

  if type(command) == "table" then
    local with_prompt = vim.list_extend({}, command)
    table.insert(with_prompt, prompt)
    return with_prompt
  end

  return command .. " " .. vim.fn.shellescape(prompt)
end

local function command_error(command)
  if type(command) == "string" then
    if command:match("^%s*$") then
      return "Codex command must not be empty"
    end
    return nil
  end

  if type(command) ~= "table" then
    return "Codex command must be a string or list"
  end

  if type(command[1]) ~= "string" or command[1]:match("^%s*$") then
    return "Codex command list must start with an executable"
  end

  return nil
end

local function command_executable(command)
  if type(command) == "table" then
    return command[1]
  end

  if type(command) == "string" then
    return command:match("^%s*(%S+)")
  end

  return nil
end

local function shell_command(command)
  if type(command) == "string" then
    return command
  end

  if type(command) ~= "table" then
    return tostring(command)
  end

  local parts = {}
  for _, part in ipairs(command) do
    local value = tostring(part)
    if value:find("%s") or value:find("[\"'\\$`;&|<>]") then
      value = vim.fn.shellescape(value)
    end
    table.insert(parts, value)
  end

  return table.concat(parts, " ")
end

local function token_monitor_config()
  if config.token_monitor == false then
    return { enabled = false }
  end

  if type(config.token_monitor) ~= "table" then
    return defaults.token_monitor
  end

  return config.token_monitor
end

local function token_monitor_enabled()
  return token_monitor_config().enabled ~= false
end

local function token_refresh_ms()
  local value = tonumber(token_monitor_config().refresh_ms)
  if value == nil or value < 10000 then
    return defaults.token_monitor.refresh_ms
  end

  return value
end

local function token_timeout_ms()
  local value = tonumber(token_monitor_config().timeout_ms)
  if value == nil or value < 1000 then
    return defaults.token_monitor.timeout_ms
  end

  return value
end

local function json_encode(value)
  if vim.json and type(vim.json.encode) == "function" then
    return vim.json.encode(value)
  end

  return vim.fn.json_encode(value)
end

local function json_decode(value)
  local ok, decoded
  if vim.json and type(vim.json.decode) == "function" then
    ok, decoded = pcall(vim.json.decode, value)
  else
    ok, decoded = pcall(vim.fn.json_decode, value)
  end

  if ok then
    return decoded
  end

  return nil
end

local function normalize_usage_percent(value)
  local percent = tonumber(value)
  if percent == nil then
    return nil
  end

  percent = math.floor(percent + 0.5)
  return math.min(100, math.max(0, percent))
end

local function parse_token_usage_window(window, usage)
  if type(window) ~= "table" then
    return
  end

  local duration = tonumber(window.windowDurationMins)
  local percent = normalize_usage_percent(window.usedPercent)
  if duration == nil or percent == nil then
    return
  end

  if duration == 300 then
    usage.five_hour_percent = percent
  elseif duration == 10080 then
    usage.weekly_percent = percent
  end
end

local function parse_token_usage_response(response)
  if type(response) ~= "table" then
    return nil
  end

  local result = type(response.result) == "table" and response.result or response
  local rate_limits = result.rateLimits
  if type(result.rateLimitsByLimitId) == "table" and type(result.rateLimitsByLimitId.codex) == "table" then
    rate_limits = result.rateLimitsByLimitId.codex
  end

  if type(rate_limits) ~= "table" then
    return nil
  end

  local usage = {
    five_hour_percent = nil,
    weekly_percent = nil,
  }

  parse_token_usage_window(rate_limits.primary, usage)
  parse_token_usage_window(rate_limits.secondary, usage)

  if usage.five_hour_percent == nil and usage.weekly_percent == nil then
    return nil
  end

  return usage
end

local function token_usage_label()
  if not token_monitor_enabled() or state.job_id == nil or state.mode == "not running" then
    return ""
  end

  local five_hour = state.token_usage.five_hour_percent
  local weekly = state.token_usage.weekly_percent
  local five_hour_label = five_hour ~= nil and (tostring(five_hour) .. "%") or "--%"
  local weekly_label = weekly ~= nil and (tostring(weekly) .. "%") or "--%"

  return "usage | 5hr " .. five_hour_label .. " | wk " .. weekly_label
end

local function stop_token_timeout_timer()
  local timer = state.token_usage.timeout_timer
  state.token_usage.timeout_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

local function clear_token_usage()
  state.token_usage.five_hour_percent = nil
  state.token_usage.weekly_percent = nil
  state.token_usage.last_error = nil
end

local function complete_token_usage_request(job_id, usage, error_message, stop_job)
  if state.token_usage.job_id ~= job_id then
    return
  end

  stop_token_timeout_timer()
  state.token_usage.job_id = nil
  state.token_usage.in_flight = false
  state.token_usage.stdout = ""
  state.token_usage.initialized = false

  if type(usage) == "table" then
    state.token_usage.five_hour_percent = usage.five_hour_percent
    state.token_usage.weekly_percent = usage.weekly_percent
    state.token_usage.last_error = nil
  elseif type(error_message) == "string" and error_message ~= "" then
    state.token_usage.last_error = error_message
  end

  if stop_job then
    pcall(vim.fn.jobstop, job_id)
  end

  if type(refresh_which_key_header) == "function" then
    refresh_which_key_header()
  end
end

local function send_token_usage_rpc(job_id, payload)
  local encoded = json_encode(payload)
  local ok, sent = pcall(vim.fn.chansend, job_id, encoded .. "\n")
  return ok and sent ~= 0
end

local function process_token_usage_message(job_id, message)
  if state.token_usage.job_id ~= job_id then
    return
  end

  if message.id == 1 and not state.token_usage.initialized then
    if type(message.result) ~= "table" then
      complete_token_usage_request(job_id, nil, "Codex app-server initialize failed", true)
      return
    end

    state.token_usage.initialized = true
    send_token_usage_rpc(job_id, {
      jsonrpc = "2.0",
      method = "initialized",
      params = {},
    })
    if not send_token_usage_rpc(job_id, {
      jsonrpc = "2.0",
      id = 2,
      method = "account/rateLimits/read",
      params = vim.NIL,
    }) then
      complete_token_usage_request(job_id, nil, "Failed to request Codex token usage", true)
    end
    return
  end

  if message.id ~= 2 then
    return
  end

  if type(message.error) == "table" then
    complete_token_usage_request(job_id, nil, tostring(message.error.message or "Codex token usage request failed"), true)
    return
  end

  local usage = parse_token_usage_response(message)
  if usage == nil then
    complete_token_usage_request(job_id, nil, "Codex token usage response was unavailable", true)
    return
  end

  complete_token_usage_request(job_id, usage, nil, true)
end

local function handle_token_usage_stdout(job_id, data)
  if state.token_usage.job_id ~= job_id or type(data) ~= "table" then
    return
  end

  local chunk = table.concat(data, "\n")
  if chunk == "" then
    return
  end

  state.token_usage.stdout = (state.token_usage.stdout or "") .. chunk

  while true do
    local newline = state.token_usage.stdout:find("\n", 1, true)
    if not newline then
      break
    end

    local line = state.token_usage.stdout:sub(1, newline - 1)
    state.token_usage.stdout = state.token_usage.stdout:sub(newline + 1)
    local message = json_decode(line)
    if type(message) == "table" then
      process_token_usage_message(job_id, message)
    end
  end
end

local function codex_app_server_command()
  local monitor = token_monitor_config()
  local executable = type(monitor.codex_cmd) == "string" and monitor.codex_cmd or command_executable(config.codex_cmd)
  if executable == nil or executable == "" then
    executable = "codex"
  end

  return { executable, "app-server", "--stdio" }, executable
end

refresh_token_usage = function(force)
  if not token_monitor_enabled() or state.job_id == nil then
    return false
  end

  if state.token_usage.in_flight then
    if not force then
      return false
    end
    complete_token_usage_request(state.token_usage.job_id, nil, "Codex token usage request was replaced", true)
  end

  local command, executable = codex_app_server_command()
  if vim.fn.executable(executable) ~= 1 then
    state.token_usage.last_error = "Codex CLI not found on PATH"
    if type(refresh_which_key_header) == "function" then
      refresh_which_key_header()
    end
    return false
  end

  state.token_usage.in_flight = true
  state.token_usage.stdout = ""
  state.token_usage.initialized = false
  state.token_usage.last_error = nil

  local job_id
  job_id = vim.fn.jobstart(command, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = vim.schedule_wrap(function(_, data)
      handle_token_usage_stdout(job_id, data)
    end),
    on_exit = vim.schedule_wrap(function(_, code)
      if state.token_usage.job_id == job_id then
        complete_token_usage_request(job_id, nil, "Codex token usage request exited with code " .. tostring(code), false)
      end
    end),
  })

  if type(job_id) ~= "number" or job_id <= 0 then
    state.token_usage.job_id = nil
    state.token_usage.in_flight = false
    state.token_usage.last_error = "Failed to start Codex app-server"
    if type(refresh_which_key_header) == "function" then
      refresh_which_key_header()
    end
    return false
  end

  state.token_usage.job_id = job_id

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if timer then
    state.token_usage.timeout_timer = timer
    timer:start(token_timeout_ms(), 0, vim.schedule_wrap(function()
      complete_token_usage_request(job_id, nil, "Codex token usage request timed out", true)
    end))
  end

  if not send_token_usage_rpc(job_id, {
    jsonrpc = "2.0",
    id = 1,
    method = "initialize",
    params = {
      clientInfo = {
        name = "codux.nvim",
        version = "0",
      },
      capabilities = {
        experimentalApi = true,
      },
    },
  }) then
    complete_token_usage_request(job_id, nil, "Failed to initialize Codex app-server", true)
    return false
  end

  return true
end

start_token_monitor_timer = function()
  if not token_monitor_enabled() or state.job_id == nil then
    return
  end

  if state.token_usage.refresh_timer then
    refresh_token_usage(true)
    return
  end

  refresh_token_usage(false)

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  state.token_usage.refresh_timer = timer
  timer:start(token_refresh_ms(), token_refresh_ms(), vim.schedule_wrap(function()
    refresh_token_usage(false)
  end))
end

stop_token_monitor_timer = function()
  local refresh_timer = state.token_usage.refresh_timer
  state.token_usage.refresh_timer = nil
  if refresh_timer then
    pcall(refresh_timer.stop, refresh_timer)
    pcall(refresh_timer.close, refresh_timer)
  end

  stop_token_timeout_timer()

  local job_id = state.token_usage.job_id
  state.token_usage.job_id = nil
  state.token_usage.in_flight = false
  state.token_usage.stdout = ""
  state.token_usage.initialized = false
  clear_token_usage()
  if job_id then
    pcall(vim.fn.jobstop, job_id)
  end
end

local function workspace_config()
  if config.workspaces == false then
    return { enabled = false }
  end

  if type(config.workspaces) ~= "table" then
    return defaults.workspaces
  end

  return config.workspaces
end

local function workspaces_enabled()
  return workspace_config().enabled ~= false
end

local function tmux_cmd()
  local value = workspace_config().tmux_cmd
  if type(value) == "string" and trim(value) ~= "" then
    return value
  end

  return defaults.workspaces.tmux_cmd
end

local function workspace_nvim_cmd()
  local value = workspace_config().nvim_cmd
  if type(value) == "string" and trim(value) ~= "" then
    return value
  end

  if type(vim.v.progpath) == "string" and vim.v.progpath ~= "" then
    return vim.v.progpath
  end

  return "nvim"
end

local function tmux_system(args)
  return system(vim.list_extend({ tmux_cmd() }, args))
end

local function path_directory(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:match("^term://") then
    return nil
  end

  if vim.fn.isdirectory(path) == 1 then
    return path
  end

  local directory = vim.fn.fnamemodify(path, ":h")
  if directory ~= "" then
    return directory
  end

  return nil
end

local function workspace_buffer_target(bufnr)
  if not is_loaded_buf(bufnr) then
    return nil
  end

  local ok, path = pcall(vim.api.nvim_buf_get_name, bufnr)
  if not ok or path_directory(path) == nil then
    return nil
  end

  return {
    path = path,
    type = vim.fn.isdirectory(path) == 1 and "directory" or "file",
    source = "buffer",
  }
end

local function workspace_fallback_buffer_target()
  local current = vim.api.nvim_get_current_buf()
  local alternate = vim.fn.bufnr("#")
  local alternate_target = workspace_buffer_target(alternate)
  if alternate_target and alternate ~= current then
    return alternate_target
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= current then
      local target = workspace_buffer_target(bufnr)
      if target then
        return target
      end
    end
  end

  return nil
end

local function workspace_target_context()
  local target = type(current_target) == "function" and current_target() or nil
  local path = target and target.path or current_buffer_name()
  if path_directory(path) == nil then
    target = workspace_fallback_buffer_target()
    path = target and target.path or nil
  end
  local directory = path_directory(path) or vim.fn.getcwd()
  local root = nil
  local branch = ""

  if type(git_root_for) == "function" then
    root = git_root_for(path or directory)
  end
  if type(git_branch_for) == "function" then
    branch = git_branch_for(path or directory)
  end

  return {
    target = target,
    path = path,
    directory = directory,
    root = root or directory,
    branch = branch,
  }
end

local function sanitize_workspace_name(name)
  local display_name = trim(name)
  if display_name == "" then
    return nil, "Workspace name is required"
  end

  local safe = display_name:lower():gsub("[^%w_.-]+", "-"):gsub("-+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if safe == "" then
    return nil, "Workspace name must contain letters, numbers, dots, dashes, or underscores"
  end

  return display_name, safe
end

local function current_tmux_session()
  if type(vim.env.TMUX) ~= "string" or vim.env.TMUX == "" then
    return nil
  end

  local output, code = tmux_system({ "display-message", "-p", "#S" })
  if code ~= 0 then
    return nil
  end

  local session = trim(output)
  if session == "" then
    return nil
  end

  return session
end

local function tmux_window_id(session, window_name)
  local output, code = tmux_system({ "list-windows", "-t", session, "-F", "#{window_id}\t#{window_name}" })
  if code ~= 0 then
    return nil
  end

  for line in output:gmatch("[^\r\n]+") do
    local id, name = line:match("^([^\t]+)\t(.+)$")
    if name == window_name then
      return id
    end
  end

  return nil
end

local function shell_env_assignment(name, value)
  return name .. "=" .. vim.fn.shellescape(tostring(value or ""))
end

local function lua_string(value)
  return string.format("%q", tostring(value or ""))
end

local function workspace_permission_profile()
  if terminal_running() then
    return state.permission_profile or "default"
  end

  return state.last_permission_profile or "default"
end

local function workspace_state_file()
  local value = workspace_config().state_file
  if type(value) == "string" and trim(value) ~= "" then
    return vim.fn.expand(value)
  end

  return vim.fn.stdpath("data") .. "/codux/workspaces.json"
end

local function empty_workspace_state()
  return {
    version = 1,
    projects = vim.empty_dict and vim.empty_dict() or {},
  }
end

local function normalize_workspace_state(state_data)
  if type(state_data) ~= "table" then
    return empty_workspace_state()
  end

  state_data.version = tonumber(state_data.version) or 1
  if type(state_data.projects) ~= "table" then
    state_data.projects = {}
  end

  return state_data
end

local function read_workspace_state()
  local path = workspace_state_file()
  if vim.fn.filereadable(path) ~= 1 then
    return empty_workspace_state(), nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return empty_workspace_state(), "Failed to read Codux workspace state"
  end

  local decoded = json_decode(table.concat(lines, "\n"))
  if type(decoded) ~= "table" then
    return empty_workspace_state(), "Failed to parse Codux workspace state"
  end

  return normalize_workspace_state(decoded), nil
end

local function write_workspace_state(state_data)
  local path = workspace_state_file()
  local directory = vim.fn.fnamemodify(path, ":h")
  if directory ~= "" then
    local mkdir_ok = pcall(vim.fn.mkdir, directory, "p")
    if not mkdir_ok then
      return false, "Failed to create Codux workspace state directory"
    end
  end

  local encoded = json_encode(normalize_workspace_state(state_data))
  local ok = pcall(vim.fn.writefile, { encoded }, path)
  if not ok then
    return false, "Failed to write Codux workspace state"
  end

  return true, nil
end

local function workspace_timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function workspace_project_state(state_data, root)
  state_data.projects[root] = type(state_data.projects[root]) == "table" and state_data.projects[root]
    or (vim.empty_dict and vim.empty_dict() or {})
  local project = state_data.projects[root]
  project.project_root = root
  project.workspaces = type(project.workspaces) == "table" and project.workspaces
    or (vim.empty_dict and vim.empty_dict() or {})
  return project
end

local function workspace_from_state(record, fallback)
  record = type(record) == "table" and record or {}
  fallback = type(fallback) == "table" and fallback or {}

  return {
    name = record.name or fallback.name,
    safe_name = record.safe_name or fallback.safe_name,
    project_root = record.project_root or fallback.project_root,
    target_path = record.target_path or fallback.target_path,
    target_type = record.target_type or fallback.target_type,
    git_branch = record.git_branch or fallback.git_branch or "",
    window_name = record.tmux_window or record.window_name or fallback.window_name,
    permission_profile = record.permission_profile or fallback.permission_profile or "default",
    created_at = record.created_at or fallback.created_at,
  }
end

local function workspace_state_record(workspace, existing)
  existing = type(existing) == "table" and existing or {}
  local now = workspace_timestamp()

  return {
    name = workspace.name,
    safe_name = workspace.safe_name,
    project_root = workspace.project_root,
    target_path = workspace.target_path,
    target_type = workspace.target_type,
    git_branch = workspace.git_branch or "",
    tmux_window = workspace.window_name,
    permission_profile = workspace.permission_profile or "default",
    created_at = existing.created_at or workspace.created_at or now,
    last_opened_at = now,
  }
end

local function workspace_entries_for_project(root)
  local state_data, state_error = read_workspace_state()
  if state_error then
    return {}, state_error
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  if type(workspaces) ~= "table" then
    return {}, nil
  end

  local session = current_tmux_session()
  local entries = {}
  for safe_name, record in pairs(workspaces) do
    if type(record) == "table" then
      local window_name = record.tmux_window or record.window_name or safe_name
      local window_id = session and tmux_window_id(session, window_name) or nil
      table.insert(entries, {
        name = record.name or safe_name,
        safe_name = record.safe_name or safe_name,
        project_root = record.project_root or root,
        target_path = record.target_path,
        target_type = record.target_type,
        git_branch = record.git_branch or "",
        window_name = window_name,
        window_id = window_id,
        active = window_id ~= nil,
      })
    end
  end

  table.sort(entries, function(left, right)
    return tostring(left.name):lower() < tostring(right.name):lower()
  end)

  return entries, nil
end

local function workspace_manager_project_root()
  return workspace_target_context().root
end

local function workspace_manager_config(line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local width = math.min(58, math.max(38, math.floor(total_width * 0.45)))
  local height = math.min(12, math.max(5, line_count or 1))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " current codux workspaces ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
  }
end

local function close_workspace_manager()
  local dashboard_filetypes = {
    ["codux-workspaces"] = true,
    ["codux-workspaces-footer"] = true,
  }

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = window_buffer(win)
    if is_loaded_buf(bufnr) and dashboard_filetypes[buffer_filetype(bufnr)] then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if is_loaded_buf(bufnr) and dashboard_filetypes[buffer_filetype(bufnr)] then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end

  state.workspace_manager_win = nil
  state.workspace_manager_buf = nil
  state.workspace_manager_footer_win = nil
  state.workspace_manager_footer_buf = nil
  state.workspace_manager_items = {}
  state.workspace_manager_project_root = nil
end

local function workspace_manager_line(entry)
  local status = entry.active and "active" or "inactive"
  local target = type(entry.target_path) == "string" and entry.target_path ~= "" and vim.fn.fnamemodify(entry.target_path, ":t") or ""
  local suffix = target ~= "" and "  " .. target or ""
  return string.format("%-28s %s%s", entry.name, status, suffix)
end

local function workspace_manager_header_line()
  return string.format("%-28s %s  %s", "workspace", "status", "target")
end

local function workspace_manager_window_height()
  if not is_valid_win(state.workspace_manager_win) then
    return nil
  end

  local ok, height = pcall(vim.api.nvim_win_get_height, state.workspace_manager_win)
  if ok and type(height) == "number" and height > 0 then
    return height
  end

  return nil
end

local function workspace_manager_footer_segments()
  return {
    { key = "enter", desc = "open" },
    { key = "r", desc = "rename" },
    { key = "d", desc = "delete" },
    { key = "<c-q>", desc = "close dashboard" },
  }
end

local function workspace_manager_footer_line()
  local parts = {}
  for index, segment in ipairs(workspace_manager_footer_segments()) do
    table.insert(parts, segment.key .. " " .. segment.desc)
    if index < #workspace_manager_footer_segments() then
      table.insert(parts, "  ")
    end
  end

  return table.concat(parts, "")
end

local function workspace_manager_window_width()
  if not is_valid_win(state.workspace_manager_win) then
    return nil
  end

  local ok, width = pcall(vim.api.nvim_win_get_width, state.workspace_manager_win)
  if ok and type(width) == "number" and width > 0 then
    return width
  end

  return nil
end

local function render_workspace_manager_footer()
  if not is_loaded_buf(state.workspace_manager_footer_buf) then
    return false
  end

  local width = workspace_manager_window_width() or 1
  local line = workspace_manager_footer_line()
  local padding = math.max(0, math.floor((width - #line) / 2))
  local text = string.rep(" ", padding) .. line

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = state.workspace_manager_footer_buf })
  pcall(vim.api.nvim_buf_set_lines, state.workspace_manager_footer_buf, 0, -1, false, { text })
  pcall(vim.api.nvim_buf_clear_namespace, state.workspace_manager_footer_buf, -1, 0, -1)

  local col = padding
  for index, segment in ipairs(workspace_manager_footer_segments()) do
    local key_end = col + #segment.key
    pcall(vim.api.nvim_buf_add_highlight, state.workspace_manager_footer_buf, -1, "WhichKey", 0, col, key_end)
    local desc_end = key_end + 1 + #segment.desc
    pcall(vim.api.nvim_buf_add_highlight, state.workspace_manager_footer_buf, -1, "WhichKeySeparator", 0, key_end, desc_end)
    col = desc_end
    if index < #workspace_manager_footer_segments() then
      col = col + 2
    end
  end

  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = state.workspace_manager_footer_buf })
  return true
end

local function open_workspace_manager_footer()
  if not is_valid_win(state.workspace_manager_win) then
    return false
  end

  local buf_ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not buf_ok or not is_loaded_buf(bufnr) then
    return false
  end

  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-workspaces-footer", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

  local height = workspace_manager_window_height() or 1
  local width = workspace_manager_window_width() or 1
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, false, {
    relative = "win",
    win = state.workspace_manager_win,
    col = 0,
    row = height - 1,
    width = width,
    height = 1,
    border = "none",
    style = "minimal",
    zindex = 51,
  })
  if not win_ok then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return false
  end

  state.workspace_manager_footer_buf = bufnr
  state.workspace_manager_footer_win = win
  render_workspace_manager_footer()
  return true
end

local function render_workspace_manager()
  if not is_loaded_buf(state.workspace_manager_buf) then
    return false
  end

  local root = state.workspace_manager_project_root or workspace_manager_project_root()
  local entries, error_message = workspace_entries_for_project(root)
  state.workspace_manager_items = entries

  local lines = { workspace_manager_header_line() }
  if error_message then
    table.insert(lines, error_message)
  elseif #entries == 0 then
    table.insert(lines, "No saved Codux workspaces")
  else
    for _, entry in ipairs(entries) do
      table.insert(lines, workspace_manager_line(entry))
    end
  end

  local footer_line = math.max(1, workspace_manager_window_height() or (#lines + 1))
  while #lines < footer_line do
    table.insert(lines, "")
  end

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = state.workspace_manager_buf })
  pcall(vim.api.nvim_buf_set_lines, state.workspace_manager_buf, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_add_highlight, state.workspace_manager_buf, -1, "WhichKeyDesc", 0, 0, -1)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = state.workspace_manager_buf })
  render_workspace_manager_footer()
  return true
end

local function selected_workspace_manager_item()
  if not is_valid_win(state.workspace_manager_win) then
    return nil
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, state.workspace_manager_win)
  if not ok then
    return nil
  end

  local index = cursor[1] - 1
  return state.workspace_manager_items[index]
end

local function rename_tmux_window(window_id, new_window_name)
  if not window_id then
    return true
  end

  local _, code = tmux_system({ "rename-window", "-t", window_id, new_window_name })
  return code == 0
end

local function kill_tmux_window(window_id)
  if not window_id then
    return true
  end

  local _, code = tmux_system({ "kill-window", "-t", window_id })
  return code == 0
end

local function kill_tmux_window_deferred(window_id, window_name)
  if not window_id then
    return
  end

  vim.defer_fn(function()
    if not kill_tmux_window(window_id) then
      notify("Failed to kill tmux window " .. tostring(window_name), vim.log.levels.WARN)
    end
  end, 100)
end

local function rename_saved_workspace(entry, new_name)
  local display_name, safe_name_or_error = sanitize_workspace_name(new_name)
  if not display_name then
    notify(safe_name_or_error, vim.log.levels.ERROR)
    return false
  end

  local root = state.workspace_manager_project_root or entry.project_root
  local state_data, state_error = read_workspace_state()
  if state_error then
    notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = workspace_project_state(state_data, root)
  local existing = project.workspaces[entry.safe_name]
  if type(existing) ~= "table" then
    notify("workspace not found", vim.log.levels.ERROR)
    return false
  end
  if safe_name_or_error ~= entry.safe_name and project.workspaces[safe_name_or_error] ~= nil then
    notify("workspace already exists", vim.log.levels.ERROR)
    return false
  end

  local new_window_name = safe_name_or_error
  if not rename_tmux_window(entry.window_id, new_window_name) then
    notify("Failed to rename tmux window " .. tostring(entry.window_name), vim.log.levels.ERROR)
    return false
  end

  project.workspaces[entry.safe_name] = nil
  existing.name = display_name
  existing.safe_name = safe_name_or_error
  existing.tmux_window = new_window_name
  existing.last_opened_at = workspace_timestamp()
  project.workspaces[safe_name_or_error] = existing
  project.updated_at = workspace_timestamp()

  local write_ok, write_error = write_workspace_state(state_data)
  if not write_ok then
    notify(write_error, vim.log.levels.ERROR)
    return false
  end

  notify("Renamed Codux workspace to " .. display_name)
  close_workspace_manager()
  return true
end

local function delete_saved_workspace(entry)
  local root = entry.project_root or state.workspace_manager_project_root
  local state_data, state_error = read_workspace_state()
  if state_error then
    notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = workspace_project_state(state_data, root)
  if type(project.workspaces[entry.safe_name]) ~= "table" then
    notify("workspace not found", vim.log.levels.ERROR)
    render_workspace_manager()
    return false
  end

  project.workspaces[entry.safe_name] = nil
  if next(project.workspaces) == nil and vim.empty_dict then
    project.workspaces = vim.empty_dict()
  end
  project.updated_at = workspace_timestamp()
  local write_ok, write_error = write_workspace_state(state_data)
  if not write_ok then
    notify(write_error, vim.log.levels.ERROR)
    return false
  end

  notify("Deleted Codux workspace " .. entry.name)
  close_workspace_manager()
  kill_tmux_window_deferred(entry.window_id, entry.window_name)
  return true
end

local function workspace_bootstrap_lua(workspace)
  local root = workspace.project_root or "."
  local target_path = workspace.target_path or ""
  local target_type = workspace.target_type or ""
  local profile = workspace.permission_profile or "default"

  return table.concat({
    "local root=" .. lua_string(root),
    "local target=" .. lua_string(target_path),
    "local target_type=" .. lua_string(target_type),
    "local profile=" .. lua_string(profile),
    "vim.defer_fn(function()",
    "pcall(vim.cmd,'cd '..vim.fn.fnameescape(root))",
    "local target_win=vim.api.nvim_get_current_win()",
    "if vim.fn.exists(':Neotree')==2 then",
    "local tree_dir=(target_type=='directory' and target~='' and target) or root",
    "local cmd='Neotree source=filesystem action=show position=left dir='..vim.fn.fnameescape(tree_dir)",
    "if target~='' and target_type~='directory' then cmd=cmd..' reveal_file='..vim.fn.fnameescape(target)..' reveal_force_cwd' end",
    "pcall(vim.cmd,cmd)",
    "end",
    "if target~='' and target_type~='directory' then if vim.api.nvim_win_is_valid(target_win) then pcall(vim.api.nvim_set_current_win,target_win) else pcall(vim.cmd,'edit '..vim.fn.fnameescape(target)) end end",
    "vim.defer_fn(function()",
    "local function open_hidden(fallback)",
    "local ok,codux=pcall(require,'codux')",
    "if ok and type(codux[fallback])=='function' then codux[fallback]() end",
    "end",
    "if profile=='auto' then open_hidden('open_workspace_auto_hidden') elseif profile=='danger' then open_hidden('open_danger_full_access_hidden') else open_hidden('open_hidden') end",
    "end,300)",
    "end,300)",
  }, " ")
end

local function workspace_nvim_command(workspace)
  local env = {
    shell_env_assignment("CODEX_CMD", shell_command(config.codex_cmd)),
    shell_env_assignment("CODEX_WORKSPACE_AUTO_CMD", shell_command(config.workspace_auto_cmd)),
    shell_env_assignment("CODEX_DANGER_FULL_ACCESS_CMD", shell_command(config.danger_full_access_cmd)),
  }
  local nvim_target = "."
  if
    workspace.target_type ~= "directory"
    and type(workspace.target_path) == "string"
    and workspace.target_path ~= ""
  then
    nvim_target = workspace.target_path
  end

  local parts = {
    "cd",
    vim.fn.shellescape(workspace.project_root or "."),
    "&&",
    "env",
    table.concat(env, " "),
    vim.fn.shellescape(workspace_nvim_cmd()),
    vim.fn.shellescape(nvim_target),
    "-c",
    vim.fn.shellescape("lua " .. workspace_bootstrap_lua(workspace)),
  }

  return table.concat(parts, " ")
end

local function ensure_tmux_window(session, root, window_name, command)
  local existing = tmux_window_id(session, window_name)
  if existing then
    return existing, false
  end

  local args = { "new-window", "-d", "-t", session .. ":", "-n", window_name, "-c", root }
  if type(command) == "string" and command ~= "" then
    table.insert(args, command)
  end

  local _, code = tmux_system(args)
  if code ~= 0 then
    return nil, false
  end

  return tmux_window_id(session, window_name), true
end

local function switch_tmux_window(window_id)
  local _, code = tmux_system({ "select-window", "-t", window_id })
  return code == 0
end

local function prepare_workspace(name, opts)
  opts = opts or {}
  if not workspaces_enabled() then
    return nil, "Codux workspaces are disabled"
  end

  if vim.fn.executable(tmux_cmd()) ~= 1 then
    return nil, "tmux not found on PATH"
  end

  local display_name, safe_name_or_error = sanitize_workspace_name(name)
  if not display_name then
    return nil, safe_name_or_error
  end

  local session = current_tmux_session()
  if not session then
    return nil, "no tmux session running"
  end

  local context = workspace_target_context()
  local root = opts.project_root or context.root
  local state_data, state_error = read_workspace_state()
  if state_error then
    notify(state_error .. "; starting with empty workspace state", vim.log.levels.WARN)
  end

  local project = workspace_project_state(state_data, root)
  local existing = project.workspaces[safe_name_or_error]
  if type(existing) == "table" and not opts.allow_existing then
    return nil, "workspace already exists"
  end
  if type(existing) == "table" and existing.name ~= display_name and not opts.allow_existing then
    return nil, "workspace already exists"
  end
  if opts.require_existing and type(existing) ~= "table" then
    return nil, "workspace not found"
  end

  local fallback = {
    name = display_name,
    safe_name = safe_name_or_error,
    project_root = root,
    target_path = context.path,
    target_type = context.target and context.target.type or nil,
    git_branch = context.branch,
    window_name = safe_name_or_error,
    permission_profile = workspace_permission_profile(),
  }
  local workspace = workspace_from_state(existing, fallback)
  workspace.session = session
  workspace.safe_name = workspace.safe_name or safe_name_or_error
  workspace.window_name = workspace.window_name or workspace.safe_name
  workspace.project_root = workspace.project_root or root

  local window_id = ensure_tmux_window(session, workspace.project_root, workspace.window_name, workspace_nvim_command(workspace))
  if not window_id then
    return nil, "Failed to create tmux window " .. workspace.window_name
  end

  workspace.window_id = window_id
  project.workspaces[workspace.safe_name] = workspace_state_record(workspace, existing)
  project.updated_at = workspace_timestamp()

  local write_ok, write_error = write_workspace_state(state_data)
  if not write_ok then
    return nil, write_error
  end

  return workspace
end

local function start_terminal(focus, initial_prompt, command, workspace, permission_profile, opts)
  opts = opts or {}
  local hidden = opts.hidden == true

  if terminal_running() then
    if focus and not hidden then
      focus_window()
    end
    return true
  end

  command = command or config.codex_cmd

  local error_message = command_error(command)
  if error_message then
    notify(error_message, vim.log.levels.ERROR)
    return false
  end

  local executable = command_executable(command)
  if type(executable) == "string" and executable == "codex" and vim.fn.executable(executable) ~= 1 then
    notify("Codex CLI not found on PATH", vim.log.levels.WARN)
  end

  local previous_win = vim.api.nvim_get_current_win()
  if hidden then
    if not ensure_buffer() then
      return false
    end
  else
    if not open_window(true) then
      return false
    end

    if not valid_win() then
      notify("Codux popup is not attached to a valid buffer", vim.log.levels.ERROR)
      return false
    end

    local current_win_ok, current_win = pcall(vim.api.nvim_get_current_win)
    if not current_win_ok or current_win ~= state.win then
      local set_ok = pcall(vim.api.nvim_set_current_win, state.win)
      if not set_ok then
        state.win = nil
        return false
      end
    end

    if window_buffer(state.win) ~= state.buf then
      state.win = nil
      return start_terminal(focus, initial_prompt, command, workspace, permission_profile, opts)
    end
  end

  local job_id
  local term_command = command_with_prompt(command, initial_prompt)
  local term_options = {
    on_exit = function(_, code)
      local expected_exit = state.exiting_jobs[job_id] == true
      local pending_delete_buffer = state.pending_delete_buffers[job_id]
      state.exiting_jobs[job_id] = nil
      state.pending_delete_buffers[job_id] = nil
      if state.job_id == job_id then
        state.job_id = nil
        state.permission_profile = "default"
        state.workspace = nil
        if type(stop_token_monitor_timer) == "function" then
          stop_token_monitor_timer()
        end
        set_codex_working(false)
        set_mode("not running")
      end
      if not expected_exit and code ~= 0 then
        notify("Codex exited with code " .. tostring(code), vim.log.levels.WARN)
      end
      if pending_delete_buffer ~= nil then
        delete_buffer_deferred(pending_delete_buffer)
      end
    end,
  }

  local term_ok
  if hidden then
    term_ok, job_id = pcall(vim.api.nvim_buf_call, state.buf, function()
      return vim.fn.termopen(term_command, term_options)
    end)
  else
    term_ok, job_id = pcall(vim.fn.termopen, term_command, term_options)
  end

  if not term_ok or type(job_id) ~= "number" or job_id <= 0 then
    state.job_id = nil
    notify("Failed to start Codex", vim.log.levels.ERROR)
    if is_valid_win(previous_win) then
      pcall(vim.api.nvim_set_current_win, previous_win)
    end
    return false
  end

  state.job_id = job_id
  state.permission_profile = permission_profile or "default"
  state.last_permission_profile = state.permission_profile
  state.workspace = workspace
  set_mode("execute")
  if type(start_token_monitor_timer) == "function" then
    start_token_monitor_timer()
  end
  set_codex_working(type(initial_prompt) == "string" and initial_prompt ~= "")

  if hidden then
    if is_valid_win(previous_win) then
      pcall(vim.api.nvim_set_current_win, previous_win)
    end
  elseif focus then
    pcall(vim.cmd, "startinsert")
  elseif is_valid_win(previous_win) then
    pcall(vim.api.nvim_set_current_win, previous_win)
  end

  return true
end

local function ensure_codex(focus, initial_prompt)
  if terminal_running() then
    return open_window(focus)
  end

  if not config.auto_open then
    notify("Codex popup is not open", vim.log.levels.WARN)
    return false
  end

  return start_terminal(focus, initial_prompt, nil, nil, "default")
end

function M.open(opts)
  opts = opts or {}
  local focus = opts.focus
  if focus == nil then
    focus = true
  end

  if not valid_win() then
    if not open_window(focus) then
      return false
    end
  elseif focus then
    focus_window()
  end

  return start_terminal(focus, nil, nil, nil, "default")
end

local function restart_with_command(command, focus, permission_profile)
  M.exit()
  return start_terminal(focus ~= false, nil, command, nil, permission_profile)
end

local function start_hidden_with_command(command, permission_profile)
  return start_terminal(false, nil, command, nil, permission_profile, { hidden = true })
end

function M.open_workspace_auto()
  notify("Starting Codex autopilot with approve-for-me permissions")
  return restart_with_command(config.workspace_auto_cmd, true, "auto")
end

function M.open_danger_full_access()
  notify("Starting Codex with no approvals and no sandbox", vim.log.levels.WARN)
  return restart_with_command(config.danger_full_access_cmd, true, "danger")
end

function M.open_hidden()
  return start_hidden_with_command(config.codex_cmd, "default")
end

function M.open_workspace_auto_hidden()
  return start_hidden_with_command(config.workspace_auto_cmd, "auto")
end

function M.open_danger_full_access_hidden()
  return start_hidden_with_command(config.danger_full_access_cmd, "danger")
end

function M.open_workspace(name)
  local workspace, error_message = prepare_workspace(name)
  if not workspace then
    notify(error_message or "Failed to prepare Codux workspace", vim.log.levels.ERROR)
    return false
  end

  if not switch_tmux_window(workspace.window_id) then
    notify("Failed to switch to Codux workspace " .. workspace.name, vim.log.levels.ERROR)
    return false
  end

  local branch = workspace.git_branch ~= "" and " on " .. workspace.git_branch or ""
  notify("Opened Codux workspace " .. workspace.name .. branch)
  return true
end

function M.open_saved_workspace(name, project_root)
  local workspace, error_message = prepare_workspace(name, {
    allow_existing = true,
    require_existing = true,
    project_root = project_root,
  })
  if not workspace then
    notify(error_message or "Failed to open Codux workspace", vim.log.levels.ERROR)
    return false
  end

  if not switch_tmux_window(workspace.window_id) then
    notify("Failed to switch to Codux workspace " .. workspace.name, vim.log.levels.ERROR)
    return false
  end

  local branch = workspace.git_branch ~= "" and " on " .. workspace.git_branch or ""
  notify("Opened Codux workspace " .. workspace.name .. branch)
  return true
end

function M.open_workspace_prompt()
  if not current_tmux_session() then
    notify("no tmux session running", vim.log.levels.ERROR)
    return false
  end

  vim.ui.input({ prompt = "Codux workspace: " }, function(input)
    local name = trim(input)
    if name == "" then
      return
    end

    M.open_workspace(name)
  end)
  return true
end

function M.open_workspaces()
  if not workspaces_enabled() then
    notify("Codux workspaces are disabled", vim.log.levels.ERROR)
    return false
  end

  close_workspace_manager()
  local buf_ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not buf_ok or not is_loaded_buf(bufnr) then
    notify("Failed to create Codux workspaces window", vim.log.levels.ERROR)
    return false
  end

  state.workspace_manager_buf = bufnr
  state.workspace_manager_project_root = workspace_manager_project_root()
  local preview_entries = workspace_entries_for_project(state.workspace_manager_project_root)
  local line_count = math.max(1, #preview_entries)
  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-workspaces", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, workspace_manager_config(line_count))
  if not win_ok then
    state.workspace_manager_buf = nil
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    notify("Failed to open Codux workspaces window", vim.log.levels.ERROR)
    return false
  end

  state.workspace_manager_win = win
  pcall(vim.api.nvim_set_option_value, "number", false, { win = win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = win })
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = win })
  pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = win })
  open_workspace_manager_footer()

  local function selected_or_notify()
    local item = selected_workspace_manager_item()
    if not item then
      notify("No Codux workspace selected", vim.log.levels.WARN)
      return nil
    end
    return item
  end

  pcall(vim.keymap.set, "n", "q", close_workspace_manager, { buffer = bufnr, silent = true, desc = "Close Codux Workspaces" })
  pcall(vim.keymap.set, "n", "<Esc>", close_workspace_manager, { buffer = bufnr, silent = true, desc = "Close Codux Workspaces" })
  pcall(vim.keymap.set, "n", "<C-q>", close_workspace_manager, { buffer = bufnr, silent = true, desc = "Close Codux Workspaces" })
  pcall(vim.keymap.set, "n", "<leader>z", function()
    close_workspace_manager()
    vim.schedule(function()
      local leader = tostring(vim.g.mapleader or "\\")
      local keys = vim.api.nvim_replace_termcodes(leader .. "z", true, false, true)
      vim.api.nvim_feedkeys(keys, "m", false)
    end)
  end, { buffer = bufnr, silent = true, nowait = true, desc = "Open Codux Menu" })
  pcall(vim.keymap.set, "n", "<CR>", function()
    local item = selected_or_notify()
    if not item then
      return false
    end
    local root = state.workspace_manager_project_root
    close_workspace_manager()
    return M.open_saved_workspace(item.name, root)
  end, { buffer = bufnr, silent = true, desc = "Open Codux Workspace" })
  pcall(vim.keymap.set, "n", "r", function()
    local item = selected_or_notify()
    if not item then
      return false
    end
    vim.ui.input({ prompt = "Rename Codux workspace: ", default = item.name }, function(input)
      local new_name = trim(input)
      if new_name == "" then
        return
      end
      rename_saved_workspace(item, new_name)
    end)
  end, { buffer = bufnr, silent = true, desc = "Rename Codux Workspace" })
  pcall(vim.keymap.set, "n", "d", function()
    local item = selected_or_notify()
    if not item then
      return false
    end
    local choice = vim.fn.confirm("Delete Codux workspace " .. item.name .. "?", "&Yes\n&No", 2)
    if choice == 1 then
      delete_saved_workspace(item)
    end
  end, { buffer = bufnr, silent = true, desc = "Delete Codux Workspace" })

  render_workspace_manager()
  if #state.workspace_manager_items > 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { 2, 0 })
  end
  return true
end

function M.close()
  if valid_win() then
    state.closing_popup = true
    pcall(vim.api.nvim_win_close, state.win, true)
    state.win = nil
    state.closing_popup = false
    update_working_indicator()
    if type(refresh_which_key) == "function" then
      refresh_which_key()
    end
    return true
  end

  return false
end

function M.toggle()
  if valid_win() then
    return M.close()
  end

  return M.open({ focus = true })
end

function M.exit()
  local job_id = state.job_id
  local bufnr = state.buf
  local running = terminal_running()

  if running and job_id ~= nil then
    state.exiting_jobs[job_id] = true
    if is_valid_buf(bufnr) then
      state.pending_delete_buffers[job_id] = bufnr
    end
    pcall(vim.fn.jobstop, job_id)
  end
  state.job_id = nil
  state.permission_profile = "default"
  state.workspace = nil
  if type(stop_token_monitor_timer) == "function" then
    stop_token_monitor_timer()
  end
  set_codex_working(false)
  set_mode("not running")

  if valid_win() then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil

  state.buf = nil
  if not running and is_valid_buf(bufnr) then
    delete_buffer_deferred(bufnr)
  end
  set_codex_working(false)

  return true
end

function M.toggle_plan_mode()
  return send_mode_toggle_to_codex()
end

local function send_to_codex(message)
  local running = terminal_running()
  if not ensure_codex(config.auto_focus, running and nil or message) then
    return false
  end

  if not running then
    return true
  end

  if not terminal_running() then
    notify("Codex terminal is not running", vim.log.levels.WARN)
    return false
  end

  local paste = "\27[200~" .. message .. "\27[201~\r"
  local send_ok, sent = pcall(vim.fn.chansend, state.job_id, paste)
  if not send_ok or sent == 0 then
    notify("Failed to send prompt to Codex", vim.log.levels.ERROR)
    return false
  end

  set_codex_working(true)
  return true
end

local function normalize_target(target, source)
  if type(target) ~= "table" or type(target.path) ~= "string" or target.path == "" then
    return nil
  end

  return {
    path = target.path,
    type = target.type == "directory" and "directory" or "file",
    source = target.source or source,
  }
end

local function explorer_enabled(name)
  return type(config.explorers) == "table" and config.explorers[name] ~= false
end

local function is_explorer_filetype(filetype)
  return filetype == "neo-tree" or filetype == "oil" or filetype == "NvimTree" or filetype == "minifiles"
end

local function neo_tree_target()
  if not explorer_enabled("neo_tree") or current_filetype() ~= "neo-tree" then
    return nil
  end

  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then
    return nil
  end

  local state_ok, state = pcall(manager.get_state_for_window)
  if not state_ok or not state or not state.tree then
    return nil
  end

  local node_ok, node = pcall(state.tree.get_node, state.tree)
  if not node_ok or not node then
    return nil
  end

  local path = node.path
  if (type(path) ~= "string" or path == "") and type(node.get_id) == "function" then
    local id_ok, id = pcall(node.get_id, node)
    if id_ok and type(id) == "string" and id ~= "" then
      path = id
    end
  end

  return normalize_target({
    path = path,
    type = node.type == "directory" and "directory" or "file",
  }, "neo-tree")
end

local function oil_target()
  if not explorer_enabled("oil") or current_filetype() ~= "oil" then
    return nil
  end

  local ok, oil = pcall(require, "oil")
  if not ok then
    return nil
  end

  local dir_ok, dir = pcall(oil.get_current_dir)
  local entry_ok, entry = pcall(oil.get_cursor_entry)
  if not dir_ok or not entry_ok or type(dir) ~= "string" or type(entry) ~= "table" or type(entry.name) ~= "string" then
    return nil
  end

  if not dir:match("/$") then
    dir = dir .. "/"
  end

  local path = dir .. entry.name
  return normalize_target({
    path = path,
    type = vim.fn.isdirectory(path) == 1 and "directory" or "file",
  }, "oil")
end

local function nvim_tree_target()
  if not explorer_enabled("nvim_tree") or current_filetype() ~= "NvimTree" then
    return nil
  end

  local ok, api = pcall(require, "nvim-tree.api")
  if not ok or not api.tree or type(api.tree.get_node_under_cursor) ~= "function" then
    return nil
  end

  local node_ok, node = pcall(api.tree.get_node_under_cursor)
  if not node_ok or type(node) ~= "table" then
    return nil
  end

  return normalize_target({
    path = node.absolute_path,
    type = node.type == "directory" and "directory" or "file",
  }, "nvim-tree")
end

local function mini_files_target()
  if not explorer_enabled("mini_files") or current_filetype() ~= "minifiles" then
    return nil
  end

  local ok, mini_files = pcall(require, "mini.files")
  if not ok or type(mini_files.get_fs_entry) ~= "function" then
    return nil
  end

  local entry_ok, entry = pcall(mini_files.get_fs_entry)
  if not entry_ok or type(entry) ~= "table" then
    return nil
  end

  return normalize_target({
    path = entry.path,
    type = vim.fn.isdirectory(entry.path or "") == 1 and "directory" or "file",
  }, "mini.files")
end

local function current_buffer_target()
  local path = current_buffer_name()
  if path == "" then
    return nil
  end

  return normalize_target({
    path = path,
    type = vim.fn.isdirectory(path) == 1 and "directory" or "file",
  }, "buffer")
end

current_target = function()
  local providers = type(config.target_providers) == "table" and config.target_providers or {}
  for _, provider in ipairs(providers) do
    if type(provider) == "function" then
      local ok, target = pcall(provider)
      if ok then
        target = normalize_target(target, "custom")
        if target then
          return target
        end
      end
    end
  end

  return neo_tree_target() or oil_target() or nvim_tree_target() or mini_files_target() or current_buffer_target()
end

local function target_label(target)
  if target.type == "directory" then
    return "directory"
  end

  return "file"
end

git_branch_for = function(path)
  local cwd = path
  if path and vim.fn.isdirectory(path) ~= 1 then
    cwd = vim.fn.fnamemodify(path, ":h")
  end

  if not cwd or cwd == "" then
    cwd = vim.fn.getcwd()
  end

  local output, code = system({ "git", "-C", cwd, "branch", "--show-current" })
  if code ~= 0 then
    return ""
  end

  return trim(output)
end

git_root_for = function(path)
  local cwd = path
  if cwd and cwd ~= "" and vim.fn.isdirectory(cwd) ~= 1 then
    cwd = vim.fn.fnamemodify(cwd, ":h")
  end

  if cwd == nil or cwd == "" then
    cwd = vim.fn.getcwd()
  end

  local output, code = system({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })
  if code ~= 0 then
    return nil
  end

  local root = trim(output)
  if root == "" then
    return nil
  end

  return root
end

local function git_output(root, ...)
  local args = { "git", "-C", root }
  vim.list_extend(args, { ... })
  local output, code = system(args)
  if code ~= 0 then
    return nil
  end

  return trim(output)
end

local function git_branch_or_head(root)
  local branch = git_output(root, "branch", "--show-current")
  if branch and branch ~= "" then
    return branch
  end

  local head = git_output(root, "rev-parse", "--short", "HEAD")
  if head and head ~= "" then
    return head
  end

  return "unknown"
end

local function git_diff_target_path()
  local target = current_target()
  if target and type(target.path) == "string" and target.path ~= "" then
    return target.path
  end

  local path = current_buffer_name()
  if path ~= "" then
    return path
  end

  return vim.fn.getcwd()
end

local function format_git_diff_context(root)
  local status = git_output(root, "status", "--short")
  if status == nil then
    return nil, "Failed to collect Git status"
  end

  if status == "" then
    return nil, "No Git changes found"
  end

  local staged = git_output(root, "diff", "--cached", "--no-ext-diff", "--")
  if staged == nil then
    return nil, "Failed to collect staged Git diff"
  end

  local unstaged = git_output(root, "diff", "--no-ext-diff", "--")
  if unstaged == nil then
    return nil, "Failed to collect unstaged Git diff"
  end

  local sections = {
    "## Git status\n" .. status,
    "## Staged diff\n" .. (staged ~= "" and staged or "(none)"),
    "## Unstaged diff\n" .. (unstaged ~= "" and unstaged or "(none)"),
  }

  return table.concat(sections, "\n\n"), nil
end

local severity_names = {
  [vim.diagnostic.severity.ERROR] = "ERROR",
  [vim.diagnostic.severity.WARN] = "WARN",
  [vim.diagnostic.severity.INFO] = "INFO",
  [vim.diagnostic.severity.HINT] = "HINT",
}

local function format_vim_diagnostics(bufnr)
  local ok, diagnostics = pcall(vim.diagnostic.get, bufnr or 0)
  if not ok then
    return nil
  end

  if vim.tbl_isempty(diagnostics) then
    return nil
  end

  local lines = {}
  for _, diagnostic in ipairs(diagnostics) do
    local source = diagnostic.source and (" [" .. diagnostic.source .. "]") or ""
    local code = diagnostic.code and (" (" .. diagnostic.code .. ")") or ""
    local severity = severity_names[diagnostic.severity] or "UNKNOWN"
    table.insert(
      lines,
      string.format(
        "%s %d:%d%s%s %s",
        severity,
        (diagnostic.lnum or 0) + 1,
        (diagnostic.col or 0) + 1,
        source,
        code,
        diagnostic.message or ""
      )
    )
  end

  return table.concat(lines, "\n")
end

local function format_list_diagnostics(items)
  if vim.tbl_isempty(items) then
    return nil
  end

  local lines = {}
  for _, item in ipairs(items) do
    local filename = item.filename and vim.fn.fnamemodify(item.filename, ":.") or ""
    local location = ""
    if filename ~= "" then
      location = filename .. ":"
    end

    local line = item.lnum or 0
    local col = item.col or 0
    local type_label = item.type and item.type ~= "" and item.type or "INFO"
    table.insert(lines, string.format("%s %s%d:%d %s", type_label, location, line, col, item.text or ""))
  end

  return table.concat(lines, "\n")
end

local function health_has_issues(text)
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    local lower = string.lower(line)
    if lower:match("^%s*health command exited with code") then
      return true
    end
    if lower:match("^%s*failed to collect :") or lower:match("^%s*failed to collect health output") then
      return true
    end
    if line:match("^%s*%- .*❌") or line:match("^%s*%- .*⚠") then
      return true
    end
    if lower:match("^%s*%- %s*error") or lower:match("^%s*%- %s*warn") or lower:match("^%s*%- %s*warning") then
      return true
    end
  end

  return false
end

local function collect_health_diagnostics()
  local nvim = vim.v.progpath ~= "" and vim.v.progpath or "nvim"
  local script = table.concat({
    'local commands = {}',
    'if vim.fn.exists(":LazyHealth") == 2 then table.insert(commands, "LazyHealth") end',
    'table.insert(commands, "checkhealth")',
    'local function capture_buffer()',
    'local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)',
    'return table.concat(lines, "\\n")',
    'end',
    'for _, command in ipairs(commands) do',
    'print("## :" .. command)',
    'local ok, err = pcall(vim.cmd, "silent " .. command)',
    'if ok then print(capture_buffer()) else print("Failed to collect :" .. command .. " output: " .. tostring(err)) end',
    'pcall(vim.cmd, "silent! bwipeout!")',
    'end',
    'vim.cmd("qa!")',
  }, "\n")

  local output, code = system_with_timeout({ nvim, "--headless", "-i", "NONE", "-c", "lua " .. script }, config.health_timeout_ms)
  local text = trim(output)
  if text == "" then
    text = "Failed to collect health output"
  end
  if code ~= 0 then
    text = text .. "\n\nHealth command exited with code " .. tostring(code)
  end

  return {
    source = ":LazyHealth/:checkhealth",
    text = text,
    has_issues = code ~= 0 or health_has_issues(text),
  }
end

local function collect_diagnostics(bufnr)
  local sections = {}
  local sources = {}
  local has_issues = false
  local formatted = format_vim_diagnostics(bufnr or 0)
  if formatted then
    has_issues = true
    table.insert(sources, "Neovim diagnostics")
    table.insert(sections, "## Neovim diagnostics\n" .. formatted)
  end

  formatted = format_list_diagnostics(vim.fn.getloclist(0))
  if formatted then
    has_issues = true
    table.insert(sources, "Location list")
    table.insert(sections, "## Location list\n" .. formatted)
  end

  formatted = format_list_diagnostics(vim.fn.getqflist())
  if formatted then
    has_issues = true
    table.insert(sources, "Quickfix list")
    table.insert(sections, "## Quickfix list\n" .. formatted)
  end

  local health = collect_health_diagnostics()
  if health and (has_issues or health.has_issues) then
    has_issues = has_issues or health.has_issues
    table.insert(sources, health.source)
    table.insert(sections, "## " .. health.source .. "\n" .. health.text)
  end

  if has_issues and not vim.tbl_isempty(sections) then
    return {
      source = table.concat(sources, ", "),
      text = table.concat(sections, "\n\n"),
    }
  end

  return nil
end

local function context_for_target(target, extra)
  extra = extra or {}
  local fallback_path = extra.fallback_path
  if fallback_path == nil then
    fallback_path = current_buffer_name()
  end
  local path = target and target.path or fallback_path
  local absolute_path = path ~= "" and vim.fn.fnamemodify(path, ":p") or ""
  local relative_path = path ~= "" and vim.fn.fnamemodify(path, ":.") or "current Neovim session"

  return vim.tbl_extend("force", {
    path = path,
    absolute_path = absolute_path,
    relative_path = relative_path,
    target_type = target and target_label(target) or "file",
    target_source = target and target.source or "buffer",
    filetype = current_filetype(),
    git_branch = git_branch_for(path),
    diagnostics = "",
    diagnostics_source = "",
    line_range = "",
    selection = "",
  }, extra)
end

local function render_prompt(template, context)
  if type(template) == "function" then
    local ok, value = pcall(template, context)
    if ok and type(value) == "string" then
      return value
    end

    notify("Prompt function failed", vim.log.levels.ERROR)
    return nil
  end

  return tostring(template):gsub("%%{([%w_]+)}", function(key)
    local value = context[key]
    if value == nil then
      return ""
    end
    return tostring(value)
  end)
end

local function send_prompt(prompt_key, context)
  local prompts = type(config.prompts) == "table" and config.prompts or {}
  local template = prompts[prompt_key]
  if template == nil then
    notify("Prompt is not configured: " .. prompt_key, vim.log.levels.WARN)
    return false
  end

  local prompt = render_prompt(template, context)
  if not prompt or prompt == "" then
    notify("Prompt is empty", vim.log.levels.WARN)
    return false
  end

  return send_to_codex(prompt)
end

function M.send_file_review()
  local target = current_target()
  if not target then
    notify("No file or file explorer node selected for review", vim.log.levels.WARN)
    return false
  end

  return send_prompt("file", context_for_target(target))
end

function M.send_file_fix()
  return M.send_file_review()
end

local function normalize_selection_positions(start_pos, end_pos)
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  if start_line == 0 or end_line == 0 then
    return nil
  end

  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  return start_line, start_col, end_line, end_col
end

local function selection_from_positions(start_pos, end_pos, mode)
  local bufnr = vim.api.nvim_get_current_buf()
  local start_line, start_col, end_line, end_col = normalize_selection_positions(start_pos, end_pos)
  if not start_line then
    return nil
  end

  local lines = buffer_lines(bufnr, start_line - 1, end_line)
  if not lines or vim.tbl_isempty(lines) then
    return nil
  end

  if mode ~= "V" and mode ~= "S" then
    if #lines == 1 then
      lines[1] = string.sub(lines[1], start_col, end_col)
    else
      lines[1] = string.sub(lines[1], start_col)
      lines[#lines] = string.sub(lines[#lines], 1, end_col)
    end
  end

  return table.concat(lines, "\n"), start_line, end_line
end

local function active_visual_mode()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "s" or mode == "S" or mode == "\22" or mode == "\19" then
    return mode
  end

  return nil
end

local function selection_from_active_visual()
  local mode = active_visual_mode()
  if not mode then
    return nil
  end

  return selection_from_positions(vim.fn.getpos("v"), vim.fn.getpos("."), mode)
end

local function selection_from_marks()
  return selection_from_positions(vim.fn.getpos("'<"), vim.fn.getpos("'>"), vim.fn.visualmode())
end

local function selection_from_range(opts)
  if type(opts) == "table" and opts.range == 0 then
    return nil
  end

  if type(opts) ~= "table" or not opts.line1 or not opts.line2 or opts.line1 == 0 or opts.line2 == 0 then
    local selected, start_line, end_line = selection_from_active_visual()
    if selected then
      return selected, start_line, end_line
    end
    return selection_from_marks()
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local start_line = math.min(opts.line1, opts.line2)
  local end_line = math.max(opts.line1, opts.line2)
  local lines = buffer_lines(bufnr, start_line - 1, end_line)
  if not lines or vim.tbl_isempty(lines) then
    return nil
  end

  return table.concat(lines, "\n"), start_line, end_line
end

function M.send_selection(opts)
  local selected, start_line, end_line = selection_from_range(opts)
  if not selected or selected == "" then
    notify("No selected code to send", vim.log.levels.WARN)
    return false
  end

  local target = current_buffer_target()
  if not target then
    notify("No file path for selected code", vim.log.levels.WARN)
    return false
  end

  return send_prompt(
    "review_selection",
    context_for_target(target, {
      selection = selected,
      line_range = string.format(":%d-%d", start_line, end_line),
    })
  )
end

function M.send_diagnostics()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = current_filetype()
  local target = current_target()
  local fallback_path = nil

  if target and target.source == "buffer" and is_explorer_filetype(filetype) then
    target = nil
    fallback_path = ""
  end

  local diagnostics = collect_diagnostics(bufnr)
  if not diagnostics then
    notify("No Issues Found", vim.log.levels.INFO)
    M.exit()
    return true
  end

  return send_prompt(
    "diagnostics",
    context_for_target(target, {
      fallback_path = fallback_path,
      diagnostics = diagnostics.text,
      diagnostics_source = diagnostics.source,
      filetype = filetype,
    })
  )
end

function M.send_git_diff()
  local root = git_root_for(git_diff_target_path())
  if not root then
    notify("Not inside a Git repository", vim.log.levels.WARN)
    return false
  end

  local diff, error_message = format_git_diff_context(root)
  if not diff then
    notify(error_message or "No Git changes found", vim.log.levels.INFO)
    return error_message == "No Git changes found"
  end

  return send_prompt(
    "git_diff",
    context_for_target({
      path = root,
      type = "directory",
      source = "git",
    }, {
      git_branch = git_branch_or_head(root),
      git_diff = diff,
    })
  )
end

function M.health()
  vim.cmd("checkhealth codux")
end

function M.health_info()
  return {
    config = config,
    popup_visible = valid_win(),
    terminal_running = terminal_running(),
    terminal_buffer = valid_buf() and state.buf or nil,
    terminal_job_id = state.job_id,
    mode = state.mode,
    permission_profile = state.permission_profile,
    last_permission_profile = state.last_permission_profile,
    codex_working = state.codex_working,
    working_indicator_visible = is_valid_win(state.working_win),
    token_usage = {
      five_hour_percent = state.token_usage.five_hour_percent,
      weekly_percent = state.token_usage.weekly_percent,
      in_flight = state.token_usage.in_flight,
      last_error = state.token_usage.last_error,
    },
    workspace = state.workspace,
    workspace_state_file = workspace_state_file(),
  }
end

local function create_commands()
  vim.api.nvim_create_user_command("Codux", function()
    M.open()
  end, { force = true, desc = "Open or focus the Codex popup" })

  vim.api.nvim_create_user_command("CoduxOpen", function()
    M.open()
  end, { force = true, desc = "Open or focus the Codex popup" })

  vim.api.nvim_create_user_command("CoduxOpenAuto", function()
    M.open_workspace_auto()
  end, { force = true, desc = "Open Codex autopilot with approve-for-me permissions" })

  vim.api.nvim_create_user_command("CoduxOpenDanger", function()
    M.open_danger_full_access()
  end, { force = true, desc = "Open Codex danger zone with no sandbox" })

  vim.api.nvim_create_user_command("CoduxWorkspace", function(opts)
    M.open_workspace(opts.args)
  end, { force = true, nargs = 1, desc = "Create a named Codux tmux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaces", function()
    M.open_workspaces()
  end, { force = true, desc = "Show current Codux workspaces" })

  vim.api.nvim_create_user_command("CoduxToggle", function()
    M.toggle()
  end, { force = true, desc = "Toggle the Codex popup" })

  vim.api.nvim_create_user_command("CoduxClose", function()
    M.close()
  end, { force = true, desc = "Hide the Codex popup without stopping Codex" })

  vim.api.nvim_create_user_command("CoduxExit", function()
    M.exit()
  end, { force = true, desc = "Stop Codex and close the popup" })

  vim.api.nvim_create_user_command("CoduxReview", function()
    M.send_file_review()
  end, { force = true, desc = "Send current file or explorer node to Codex for review" })

  vim.api.nvim_create_user_command("CoduxReviewSelection", function(opts)
    M.send_selection(opts)
  end, { force = true, range = true, desc = "Send selected code to Codex for review" })

  vim.api.nvim_create_user_command("CoduxDiagnostics", function()
    M.send_diagnostics()
  end, { force = true, desc = "Send diagnostics, lists, and headless health output to Codex" })

  vim.api.nvim_create_user_command("CoduxDiff", function()
    M.send_git_diff()
  end, { force = true, desc = "Send Git changes to Codex for review" })

  vim.api.nvim_create_user_command("CoduxTogglePlan", function()
    M.toggle_plan_mode()
  end, { force = true, desc = "Toggle Codex plan mode" })

  vim.api.nvim_create_user_command("CoduxHealth", function()
    M.health()
  end, { force = true, desc = "Run codux.nvim health checks" })
end

local function set_mapping(mode, lhs, rhs, desc)
  if type(lhs) == "string" and lhs ~= "" then
    vim.keymap.set(mode, lhs, rhs, { desc = desc })
  end
end

local function mode_status_label()
  return "codux"
end

local function mode_status_header_lines()
  local lines = { "codux status " .. (state.mode or "not running") }
  local usage = token_usage_label()
  if usage ~= "" then
    table.insert(lines, usage)
  end

  return lines
end

local function mode_status_hl()
  if state.mode == "execute" then
    return "CoduxWhichKeyExecute"
  end
  if state.mode == "plan" then
    return "CoduxWhichKeyPlan"
  end

  return "CoduxWhichKeyNotRunning"
end

local function apply_mode_status_hl()
  pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyExecute", { fg = "#3fb950" })
  pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyPlan", { fg = "#a371f7" })
  pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyNotRunning", { fg = "#f85149" })
  pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyUsage", { fg = "#8b949e" })
end

local function mode_status_icon()
  if state.mode == "execute" then
    return { icon = codux_icon, color = "green" }
  end
  if state.mode == "plan" then
    return { icon = codux_icon, color = "purple" }
  end

  return { icon = codux_icon, color = "red" }
end

local function mode_action_desc()
  if state.mode == "execute" then
    return "switch to plan mode"
  end
  if state.mode == "plan" then
    return "switch to execute mode"
  end

  return nil
end

local function clear_which_key_cache()
  local ok, which_key_buf = pcall(require, "which-key.buf")
  if ok and type(which_key_buf.clear) == "function" then
    pcall(which_key_buf.clear)
  end
end

local function active_which_key_node()
  local ok, which_key_state = pcall(require, "which-key.state")
  if not ok or type(which_key_state.state) ~= "table" or type(which_key_state.state.node) ~= "table" then
    return nil
  end

  return which_key_state.state.node
end

local function codux_which_key_prefix()
  local ok, which_key_util = pcall(require, "which-key.util")
  if ok and type(which_key_util.norm) == "function" then
    local norm_ok, value = pcall(which_key_util.norm, "<leader>z")
    if norm_ok and type(value) == "string" then
      return value
    end
  end

  return "<leader>z"
end

local function codux_menu_marker(value)
  if type(value) ~= "string" then
    return false
  end

  local text = value:lower()
  local markers = {
    "open codex",
    "codex autopilot",
    "codex danger zone",
    "send file/folder to codex",
    "send selection to codex",
    "send diagnostics to codex",
    "send git diff to codex",
    "create codux workspace",
    "current codux workspaces",
    "switch to execute mode",
    "switch to plan mode",
  }

  for _, marker in ipairs(markers) do
    if text:find(marker, 1, true) then
      return true
    end
  end

  return false
end

local function node_has_codux_menu_child(node)
  if type(node) ~= "table" or type(node.children) ~= "function" then
    return false
  end

  local ok, children = pcall(node.children, node)
  if not ok or type(children) ~= "table" then
    return false
  end

  for _, child in ipairs(children) do
    if codux_menu_marker(child.desc) then
      return true
    end
  end

  return false
end

local function codux_which_key_active()
  local node = active_which_key_node()
  if type(node) ~= "table" then
    return false
  end

  return node.keys == codux_which_key_prefix() or node_has_codux_menu_child(node)
end

local function which_key_view()
  local ok, view = pcall(require, "which-key.view")
  if not ok or type(view) ~= "table" or type(view.view) ~= "table" then
    return nil
  end

  return view
end

local function valid_which_key_window(view)
  if type(view) ~= "table" or type(view.view) ~= "table" then
    return nil, nil
  end

  local win = view.view.win
  local buf = view.view.buf
  if not is_valid_win(win) or not is_loaded_buf(buf) then
    return nil, nil
  end

  return win, buf
end

local function codux_which_key_title()
  local usage = token_usage_label()
  local title = { { " codux " .. (state.mode or "not running") .. " ", mode_status_hl() } }
  if usage ~= "" then
    local compact_usage = usage:gsub("^usage | ", "")
    table.insert(title, { "| " .. compact_usage .. " ", "CoduxWhichKeyUsage" })
  end

  return title
end

local function with_codux_which_key_chrome(callback)
  local ok, which_key_config = pcall(require, "which-key.config")
  if not ok or type(which_key_config.win) ~= "table" then
    return callback()
  end

  local win_config = which_key_config.win
  local original = {
    border = win_config.border,
    title = win_config.title,
    title_pos = win_config.title_pos,
    footer = win_config.footer,
    footer_pos = win_config.footer_pos,
    show_keys = which_key_config.show_keys,
  }

  local title = codux_which_key_title()
  win_config.title = title
  win_config.title_pos = "center"
  win_config.footer = ""
  win_config.footer_pos = "center"
  which_key_config.show_keys = false
  if win_config.border == nil or win_config.border == false or win_config.border == "none" then
    win_config.border = "rounded"
  end

  local ok_callback, results = pcall(function()
    return { callback() }
  end)

  win_config.border = original.border
  win_config.title = original.title
  win_config.title_pos = original.title_pos
  win_config.footer = original.footer
  win_config.footer_pos = original.footer_pos
  which_key_config.show_keys = original.show_keys

  if not ok_callback then
    error(results)
  end

  return unpack(results)
end

refresh_which_key_header = function()
  local view = which_key_view()
  local win = valid_which_key_window(view)
  if win and codux_which_key_active() and type(view.show) == "function" then
    pcall(view.show)
  end
end

local function install_which_key_header_hook()
  if which_key_header_hooked then
    return
  end

  local ok, view = pcall(require, "which-key.view")
  if not ok or type(view) ~= "table" or type(view.show) ~= "function" then
    return
  end

  if view._codux_header_hooked == "chrome" then
    which_key_header_hooked = true
    return
  end

  local original_show = view.show
  view.show = function(...)
    local args = { ... }
    if codux_which_key_active() then
      return with_codux_which_key_chrome(function()
        return original_show(unpack(args))
      end)
    end

    return original_show(unpack(args))
  end
  view._codux_header_hooked = "chrome"
  which_key_header_hooked = true
end

local function spec_has_owned_lhs(spec, owned)
  if type(spec) ~= "table" then
    return false
  end
  if type(spec.lhs) == "string" and owned[spec.lhs] then
    return true
  end
  if type(spec[1]) == "string" and owned[spec[1]] then
    return true
  end

  for _, child in pairs(spec) do
    if spec_has_owned_lhs(child, owned) then
      return true
    end
  end

  return false
end

local function remove_codux_which_key_specs(mappings)
  local owned = {}
  for _, lhs in pairs(mappings) do
    if type(lhs) == "string" and lhs ~= "" then
      owned[lhs] = true
    end
  end
  owned["<leader>z"] = true

  local ok_wk, which_key = pcall(require, "which-key")
  if ok_wk and type(which_key._queue) == "table" then
    for index = #which_key._queue, 1, -1 do
      local queued = which_key._queue[index]
      if type(queued) == "table" and spec_has_owned_lhs(queued.spec, owned) then
        table.remove(which_key._queue, index)
      end
    end
  end

  local ok, which_key_config = pcall(require, "which-key.config")
  if not ok or type(which_key_config.mappings) ~= "table" then
    return
  end

  for index = #which_key_config.mappings, 1, -1 do
    local mapping = which_key_config.mappings[index]
    if type(mapping) == "table" and owned[mapping.lhs] then
      table.remove(which_key_config.mappings, index)
    end
  end

  clear_which_key_cache()
end

update_terminal_mode_mapping = function()
  if not valid_buf() then
    return
  end

  local mappings = type(config.mappings) == "table" and config.mappings or {}
  local lhs = mappings.mode
  if type(lhs) ~= "string" or lhs == "" then
    return
  end

  local action_desc = mode_action_desc()
  if action_desc then
    pcall(vim.keymap.set, { "n", "t" }, lhs, M.toggle_plan_mode, {
      buffer = state.buf,
      nowait = true,
      silent = true,
      desc = action_desc,
    })
  else
    pcall(vim.keymap.del, "n", lhs, { buffer = state.buf })
    pcall(vim.keymap.del, "t", lhs, { buffer = state.buf })
  end
end

local function register_which_key_group(mappings)
  local ok, which_key = pcall(require, "which-key")
  if not ok then
    return
  end

  install_which_key_header_hook()
  remove_codux_which_key_specs(mappings)

  local normal_entries = {
    { lhs = mappings.open, desc = "open codex" },
    { lhs = mappings.open_auto, desc = "codex autopilot" },
    { lhs = mappings.open_danger, desc = "codex danger zone" },
    { lhs = mappings.review_file, desc = "send file/folder to codex" },
    { lhs = mappings.review_selection, desc = "send selection to codex" },
    { lhs = mappings.diagnostics, desc = "send diagnostics to codex" },
    { lhs = mappings.diff, desc = "send git diff to codex" },
    { lhs = mappings.workspace, desc = "create codux workspace" },
    { lhs = mappings.workspaces, desc = "current codux workspaces" },
  }
  if mode_action_desc() then
    table.insert(normal_entries, { lhs = mappings.mode, desc = mode_action_desc() })
  end

  local has_normal_prefix = false
  for _, entry in ipairs(normal_entries) do
    if type(entry.lhs) == "string" and entry.lhs:match("^<leader>z") then
      has_normal_prefix = true
      break
    end
  end
  local has_visual_prefix = type(mappings.review_selection) == "string" and mappings.review_selection:match("^<leader>z")

  if not has_normal_prefix and not has_visual_prefix then
    return
  end

  if type(which_key.add) == "function" then
    local specs = {}
    if has_normal_prefix then
      table.insert(specs, { "<leader>z", group = mode_status_label(), icon = mode_status_icon(), mode = "n" })
    end
    if has_visual_prefix then
      table.insert(specs, { "<leader>z", group = mode_status_label(), mode = "v" })
    end
    for _, entry in ipairs(normal_entries) do
      if type(entry.lhs) == "string" and entry.lhs:match("^<leader>z") then
        table.insert(specs, { entry.lhs, desc = entry.desc, mode = "n" })
      end
    end
    if has_visual_prefix then
      table.insert(specs, { mappings.review_selection, desc = "send selection to codex", mode = "v" })
    end
    pcall(which_key.add, specs)
  elseif type(which_key.register) == "function" then
    if has_normal_prefix then
      local normal_spec = { z = { name = codux_icon .. " " .. mode_status_label() } }
      for _, entry in ipairs(normal_entries) do
        if type(entry.lhs) == "string" and entry.lhs:match("^<leader>z.") then
          normal_spec.z[entry.lhs:sub(#"<leader>z" + 1)] = entry.desc
        end
      end
      pcall(which_key.register, normal_spec, { prefix = "<leader>", mode = "n" })
    end
    if has_visual_prefix then
      local visual_spec = { z = { name = mode_status_label() } }
      if mappings.review_selection:match("^<leader>z.") then
        visual_spec.z[mappings.review_selection:sub(#"<leader>z" + 1)] = "send selection to codex"
      end
      pcall(which_key.register, visual_spec, { prefix = "<leader>", mode = "v" })
    end
  end
end

refresh_which_key = function()
  local mappings = type(config.mappings) == "table" and config.mappings or {}
  apply_mode_status_hl()
  register_which_key_group(mappings)
  local action_desc = mode_action_desc()
  if action_desc then
    set_mapping("n", mappings.mode, M.toggle_plan_mode, action_desc)
  elseif type(mappings.mode) == "string" and mappings.mode ~= "" then
    pcall(vim.keymap.del, "n", mappings.mode)
  end
  update_terminal_mode_mapping()
end

function M.setup(opts)
  stop_token_monitor_timer()
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  create_commands()

  local mappings = type(config.mappings) == "table" and config.mappings or {}
  refresh_which_key()
  set_mapping("n", mappings.open, M.open, "open codex")
  set_mapping("n", mappings.open_auto, M.open_workspace_auto, "codex autopilot")
  set_mapping("n", mappings.open_danger, M.open_danger_full_access, "codex danger zone")
  set_mapping("n", mappings.review_file, M.send_file_review, "send file/folder to codex")
  set_mapping("n", mappings.review_selection, M.send_selection, "send selection to codex")
  set_mapping("v", mappings.review_selection, M.send_selection, "send selection to codex")
  set_mapping("n", mappings.diagnostics, M.send_diagnostics, "send diagnostics to codex")
  set_mapping("n", mappings.diff, M.send_git_diff, "send git diff to codex")
  set_mapping("n", mappings.workspace, M.open_workspace_prompt, "create codux workspace")
  set_mapping("n", mappings.workspaces, M.open_workspaces, "current codux workspaces")
  if mode_action_desc() then
    set_mapping("n", mappings.mode, M.toggle_plan_mode, mode_action_desc())
  end

  pcall(vim.api.nvim_clear_autocmds, { group = augroup, event = "VimLeavePre" })
  pcall(vim.api.nvim_create_autocmd, "VimLeavePre", {
    group = augroup,
    callback = function()
      stop_token_monitor_timer()
    end,
  })

  install_which_key_header_hook()
end

return M
