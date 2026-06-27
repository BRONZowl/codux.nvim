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
    templates = {},
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
  last_prompt_line = nil,
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
  workspace_manager_search_buf = nil,
  workspace_manager_search_win = nil,
  workspace_manager_command_buf = nil,
  workspace_manager_command_win = nil,
  workspace_manager_items = {},
  workspace_manager_query = "",
  workspace_manager_best_match_index = nil,
  workspace_manager_selected_index = nil,
  workspace_manager_focus_match = false,
  workspace_manager_search_confirmed = false,
  workspace_manager_project_root = nil,
  workspace_manager_refresh_timer = nil,
  workspace_manager_ns = vim.api.nvim_create_namespace("codux.workspace_manager"),
  workspace_target_signature = nil,
  workspace_target_update_pending = false,
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
local render_workspace_manager
local read_workspace_state
local write_workspace_state
local codux_icon = "󰚩"
local which_key_header_hooked = false

M._v5 = {
  built_in_templates = {
    implementation = "You are working in an implementation workspace. Focus on making the requested change cleanly, following the existing codebase patterns, keeping scope tight, and verifying the result.",
    debug = "You are working in a debugging workspace. Focus on reproducing the issue, identifying the smallest relevant code path, proposing minimal fixes, and verifying the result before broad refactoring.",
    review = "You are working in a code review workspace. Focus on correctness, edge cases, maintainability, regressions, and whether the change matches the intended behavior.",
    planning = "You are working in a planning workspace. Focus on clarifying goals, constraints, tradeoffs, implementation order, risks, and concrete acceptance criteria before code changes.",
    docs = "You are working in a documentation workspace. Focus on accuracy, reader workflow, clear examples, concise wording, and keeping documentation aligned with the current behavior.",
  },
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "codux.nvim" })
end

local function set_mode(mode)
  if state.mode == mode then
    return
  end

  state.mode = mode
  if
    mode ~= "plan"
    and type(M._sync_workspace_activity) == "function"
    and state.workspace
    and state.workspace.codex_status == "question"
  then
    M._sync_workspace_activity("idle")
  end
  if type(refresh_which_key) == "function" then
    refresh_which_key()
  end
  if type(refresh_which_key_header) == "function" then
    refresh_which_key_header()
  end
end

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M._v5.output_looks_like_question(lines, first_index)
  if type(lines) ~= "table" then
    return false
  end

  first_index = math.max(1, tonumber(first_index) or 1)
  local start_index = math.max(first_index, #lines - 79)
  for index = #lines, start_index, -1 do
    local line = trim(tostring(lines[index] or ""):gsub("\27%[[0-?]*[ -/]*[@-~]", ""):gsub("\r", ""))
    if line ~= "" and line:match("%?[%]%)}\"'`%s]*$") then
      return true
    end
  end

  return false
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
    state.last_prompt_line = nil
    set_codex_working(false, { force_idle = true })
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
    state.last_prompt_line = nil
    set_codex_working(false, { force_idle = true })
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
    state.last_prompt_line = nil
    set_codex_working(false, { force_idle = true })
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
  state.last_prompt_line = nil
  set_codex_working(false, { force_idle = true })
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

function M._v5.set_buffer_keymap(bufnr, modes, lhs, rhs, desc, opts)
  opts = type(opts) == "table" and opts or {}
  return pcall(vim.keymap.set, modes, lhs, rhs, {
    buffer = bufnr,
    nowait = opts.nowait == true,
    silent = opts.silent ~= false,
    desc = desc,
  })
end

function M._v5.bind_close_keys(bufnr, close_fn, desc, modes, opts)
  modes = modes or "n"
  M._v5.set_buffer_keymap(bufnr, modes, "<C-q>", close_fn, desc, opts)
  if opts and opts.escape then
    M._v5.set_buffer_keymap(bufnr, modes, "<Esc>", close_fn, desc, opts)
  end
  if opts and opts.q then
    M._v5.set_buffer_keymap(bufnr, modes, "q", close_fn, desc, opts)
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

function M._v5.single_line_prompt(opts, callback)
  opts = type(opts) == "table" and opts or {}
  callback = type(callback) == "function" and callback or function() end
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
    if not is_loaded_buf(bufnr) then
      return false
    end

    pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = bufnr })
    pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, { value .. " " })
    pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })
    if is_valid_win(win) then
      pcall(vim.api.nvim_win_set_cursor, win, { 1, math.min(#value, math.max(0, width - 1)) })
    end
    return true
  end

  local function close_prompt(result)
    if closed then
      return false
    end
    closed = true
    if is_valid_win(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if is_loaded_buf(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
    callback(result)
    return true
  end

  local buf_ok, created_bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not buf_ok or not is_loaded_buf(created_bufnr) then
    notify("Failed to create Codux prompt", vim.log.levels.ERROR)
    return false
  end
  bufnr = created_bufnr

  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "buftype", "nofile", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "filetype", opts.filetype or "codux-prompt", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "swapfile", false, { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

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
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    notify("Failed to open Codux prompt", vim.log.levels.ERROR)
    return false
  end
  win = created_win

  pcall(vim.api.nvim_set_option_value, "number", false, { win = win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = win })
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = win })
  pcall(vim.api.nvim_set_option_value, "winhighlight", "FloatBorder:WhichKey,FloatTitle:WhichKey", { win = win })

  M._v5.bind_close_keys(bufnr, function()
    return close_prompt(nil)
  end, "Cancel Codux Prompt", "n", { escape = true })
  M._v5.set_buffer_keymap(bufnr, "n", "<CR>", function()
    return close_prompt(value)
  end, "Submit Codux Prompt")
  M._v5.set_buffer_keymap(bufnr, "n", "<BS>", function()
    local length = vim.fn.strchars(value)
    if length > 0 then
      value = vim.fn.strcharpart(value, 0, length - 1)
      return render()
    end
    return true
  end, "Delete Codux Prompt Character", { nowait = true })
  M._v5.set_buffer_keymap(bufnr, "n", "<C-h>", function()
    local length = vim.fn.strchars(value)
    if length > 0 then
      value = vim.fn.strcharpart(value, 0, length - 1)
      return render()
    end
    return true
  end, "Delete Codux Prompt Character", { nowait = true })
  M._v5.set_buffer_keymap(bufnr, "n", "<C-u>", function()
    value = ""
    return render()
  end, "Clear Codux Prompt", { nowait = true })
  for _, key in ipairs(printable_prompt_keys()) do
    local lhs = key[1]
    local input = key[2]
    M._v5.set_buffer_keymap(bufnr, "n", lhs, function()
      value = value .. input
      return render()
    end, "Type in Codux Prompt", { nowait = true })
  end

  render()
  return true
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
      set_codex_working(false, { force_idle = true })
      return
    end

    if now_ms() - state.last_working_activity >= working_idle_ms() then
      set_codex_working(false)
      return
    end

    update_working_indicator()
  end))
end

function M._v5.mark_terminal_prompt_submission()
  if not valid_buf() then
    state.last_prompt_line = nil
    return
  end

  state.last_prompt_line = vim.api.nvim_buf_line_count(state.buf)
end

function M._v5.plan_question_pending()
  if state.mode ~= "plan" or not valid_buf() or type(state.last_prompt_line) ~= "number" then
    return false
  end

  local line_count = vim.api.nvim_buf_line_count(state.buf)
  local start_line = math.max(0, math.min(state.last_prompt_line, line_count))
  local lines = buffer_lines(state.buf, start_line, line_count)
  return M._v5.output_looks_like_question(lines)
end

set_codex_working = function(working, opts)
  opts = opts or {}
  local was_working = state.codex_working == true
  state.codex_working = working == true
  if not state.codex_working then
    local codex_status = "idle"
    if was_working and opts.force_idle ~= true and M._v5.plan_question_pending() then
      codex_status = "question"
    end
    M._sync_workspace_activity(codex_status)
    state.last_working_activity = 0
    stop_working_idle_timer()
    close_working_indicator()
  else
    M._sync_workspace_activity("working")
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
      M._v5.mark_terminal_prompt_submission()
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

  set_codex_working(false, { force_idle = true })
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
  M._v5.set_buffer_keymap(bufnr, { "n", "t" }, "<C-q>", M.close, "Hide Codux Popup")
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
  M._v5.set_buffer_keymap(bufnr, "n", "q", M.close, "Hide Codux Popup")

  pcall(vim.api.nvim_create_autocmd, { "BufUnload", "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      if state.buf == bufnr then
        state.buf = nil
        state.job_id = nil
        state.last_prompt_line = nil
        set_codex_working(false, { force_idle = true })
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
    pcall(vim.api.nvim_set_option_value, "wrap", true, { win = state.win })
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
  pcall(vim.api.nvim_set_option_value, "wrap", true, { win = state.win })

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

function M._v5.templates()
  local templates = M._v5.all_templates()
  local state_data = type(read_workspace_state) == "function" and read_workspace_state() or nil
  local hidden = type(state_data) == "table" and state_data.hidden_templates or nil
  if type(hidden) == "table" then
    for name, value in pairs(hidden) do
      if type(name) == "string" and value == true then
        templates[name] = nil
      end
    end
  end

  return templates
end

function M._v5.all_templates()
  local templates = vim.deepcopy(M._v5.built_in_templates)
  if type(read_workspace_state) == "function" then
    local state_data = read_workspace_state()
    local saved = type(state_data) == "table" and state_data.templates or nil
    if type(saved) == "table" then
      for name, instruction in pairs(saved) do
        if type(name) == "string" and trim(name) ~= "" and type(instruction) == "string" and trim(instruction) ~= "" then
          templates[name] = instruction
        end
      end
    end
  end

  local configured = workspace_config().templates
  if type(configured) == "table" then
    for name, instruction in pairs(configured) do
      if type(name) == "string" and trim(name) ~= "" and type(instruction) == "string" and trim(instruction) ~= "" then
        templates[name] = instruction
      end
    end
  end

  return templates
end

function M._v5.template_source(name)
  if type(name) ~= "string" or trim(name) == "" then
    return nil
  end

  local configured = workspace_config().templates
  if
    type(configured) == "table"
    and type(configured[name]) == "string"
    and trim(configured[name]) ~= ""
  then
    return "configured"
  end

  if type(read_workspace_state) == "function" then
    local state_data = read_workspace_state()
    local saved = type(state_data) == "table" and state_data.templates or nil
    if type(saved) == "table" and type(saved[name]) == "string" and trim(saved[name]) ~= "" then
      return "saved"
    end
  end

  if type(M._v5.built_in_templates[name]) == "string" and trim(M._v5.built_in_templates[name]) ~= "" then
    return "built-in"
  end

  return nil
end

function M._v5.template_names()
  local names = {}
  for name, _ in pairs(M._v5.templates()) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M._v5.template_instruction(name)
  if type(name) ~= "string" or trim(name) == "" then
    return nil
  end

  return M._v5.templates()[name]
end

function M._v5.delete_template(name)
  name = type(name) == "string" and trim(name) or ""
  if name == "" then
    return false, "Workspace template name is required"
  end
  if name == "none" or name == "custom" then
    return false, "Cannot delete Codux workspace template: " .. name
  end
  if not M._v5.template_instruction(name) then
    return false, "unknown workspace template: " .. name
  end

  local state_data, state_error = read_workspace_state()
  if state_error then
    return false, state_error
  end

  state_data.templates = type(state_data.templates) == "table" and state_data.templates
    or (vim.empty_dict and vim.empty_dict() or {})
  state_data.hidden_templates = type(state_data.hidden_templates) == "table" and state_data.hidden_templates
    or (vim.empty_dict and vim.empty_dict() or {})

  local had_saved = type(state_data.templates[name]) == "string" and trim(state_data.templates[name]) ~= ""
  state_data.templates[name] = nil

  local configured = workspace_config().templates
  local has_configured = type(configured) == "table"
    and type(configured[name]) == "string"
    and trim(configured[name]) ~= ""
  local has_builtin = type(M._v5.built_in_templates[name]) == "string" and trim(M._v5.built_in_templates[name]) ~= ""
  if has_configured or has_builtin then
    state_data.hidden_templates[name] = true
  else
    state_data.hidden_templates[name] = nil
  end

  if next(state_data.templates) == nil and vim.empty_dict then
    state_data.templates = vim.empty_dict()
  end
  if next(state_data.hidden_templates) == nil and vim.empty_dict then
    state_data.hidden_templates = vim.empty_dict()
  end

  local ok, write_error = write_workspace_state(state_data)
  if not ok then
    return false, write_error
  end

  local source = M._v5.template_source(name)
  if had_saved and not source then
    source = "saved"
  end

  return true, nil, source
end

function M._v5.save_existing_template(name, instruction)
  name = type(name) == "string" and trim(name) or ""
  instruction = type(instruction) == "string" and trim(instruction) or ""
  if name == "" then
    return false, "Workspace template name is required"
  end
  if instruction == "" then
    return false, "Workspace instruction is required"
  end

  local state_data, state_error = read_workspace_state()
  if state_error then
    return false, state_error
  end

  local saved = type(state_data.templates) == "table" and state_data.templates or nil
  if type(saved) ~= "table" or type(saved[name]) ~= "string" or trim(saved[name]) == "" then
    return false, "workspace template is not editable: " .. name
  end

  saved[name] = instruction
  local ok, write_error = write_workspace_state(state_data)
  if not ok then
    return false, write_error
  end

  return true, nil
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

function M._v5.save_custom_template_for_workspace(name, instruction, existing_template)
  instruction = type(instruction) == "string" and trim(instruction) or ""
  if instruction == "" then
    return nil, "Workspace instruction is required"
  end

  local display_name, safe_name_or_error = sanitize_workspace_name(name)
  if not display_name then
    return nil, safe_name_or_error
  end

  local state_data, state_error = read_workspace_state()
  if state_error then
    return nil, state_error
  end

  state_data.templates = type(state_data.templates) == "table" and state_data.templates
    or (vim.empty_dict and vim.empty_dict() or {})

  if
    type(existing_template) == "string"
    and trim(existing_template) ~= ""
    and type(state_data.templates[existing_template]) == "string"
  then
    state_data.templates[existing_template] = instruction
    local ok, write_error = write_workspace_state(state_data)
    if not ok then
      return nil, write_error
    end
    return existing_template, nil
  end

  local existing = M._v5.all_templates()
  existing.none = existing.none or true
  existing.custom = existing.custom or true

  local base = safe_name_or_error
  local candidate = base
  local suffix = 2
  while existing[candidate] or state_data.templates[candidate] do
    candidate = base .. "-" .. tostring(suffix)
    suffix = suffix + 1
  end

  state_data.templates[candidate] = instruction
  local ok, write_error = write_workspace_state(state_data)
  if not ok then
    return nil, write_error
  end

  return candidate, nil
end

function M._v5.workspace_window_name(safe_name, _template)
  safe_name = tostring(safe_name or "")
  if safe_name == "" then
    return safe_name
  end
  return safe_name
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

function M._v5.tmux_window_command(window_id)
  if type(window_id) ~= "string" or window_id == "" then
    return nil
  end

  local output, code = tmux_system({ "list-panes", "-t", window_id, "-F", "#{pane_current_command}" })
  if code ~= 0 then
    return nil
  end

  for line in output:gmatch("[^\r\n]+") do
    local command = trim(line)
    if command ~= "" then
      return command
    end
  end

  return nil
end

function M._v5.status_for_window(window_id)
  if not window_id then
    return "missing"
  end

  local command = M._v5.tmux_window_command(window_id)
  local lower = type(command) == "string" and command:lower() or ""
  if lower == "nvim" or lower == "vim" or lower:find("nvim", 1, true) or lower:find("vim", 1, true) then
    return "active"
  end

  return "inactive"
end

function M._v5.dashboard_workspace_status(record, window_id)
  local window_status = M._v5.status_for_window(window_id)
  if window_status ~= "active" then
    return "inactive"
  end

  record = type(record) == "table" and record or {}
  if record.codex_status == "working" then
    return "active"
  end
  if record.codex_status == "question" then
    return "question"
  end
  return "idle"
end

function M._v5.tmux_target(session, window_name)
  if type(session) ~= "string" or session == "" or type(window_name) ~= "string" or window_name == "" then
    return nil
  end

  return session .. ":" .. window_name
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
    version = 2,
    templates = vim.empty_dict and vim.empty_dict() or {},
    hidden_templates = vim.empty_dict and vim.empty_dict() or {},
    projects = vim.empty_dict and vim.empty_dict() or {},
  }
end

function M._v5.normalize_record(record, safe_name, root)
  if type(record) ~= "table" then
    return nil
  end

  safe_name = type(record.safe_name) == "string" and record.safe_name ~= "" and record.safe_name or safe_name
  local name = type(record.name) == "string" and record.name ~= "" and record.name or safe_name
  local project_root = type(record.project_root) == "string" and record.project_root ~= "" and record.project_root or root
  local window_name = M._v5.workspace_window_name(safe_name, record.template)
  local status = record.status
  if status == "missing" then
    status = "inactive"
  elseif status ~= "active" and status ~= "question" and status ~= "idle" and status ~= "inactive" then
    status = "inactive"
  end
  local codex_status = record.codex_status == "working" and "working"
    or record.codex_status == "question" and "question"
    or "idle"

  return {
    name = name,
    safe_name = safe_name,
    project_root = project_root,
    target_path = record.target_path,
    target_type = record.target_type,
    git_branch = record.git_branch or "",
    tmux_window = window_name,
    tmux_target = record.tmux_target,
    template = record.template,
    custom_instruction = record.custom_instruction,
    resolved_instruction = record.resolved_instruction,
    permission_profile = record.permission_profile or "default",
    status = status,
    codex_status = codex_status,
    created_at = record.created_at,
    last_opened_at = record.last_opened_at,
    last_activity_at = record.last_activity_at,
    last_target_at = record.last_target_at,
    last_reconciled_at = record.last_reconciled_at,
  }
end

local function normalize_workspace_state(state_data)
  if type(state_data) ~= "table" then
    return empty_workspace_state()
  end

  if type(state_data.projects) ~= "table" and type(state_data.workspaces) == "table" then
    local migrated = empty_workspace_state()
    if type(state_data.templates) == "table" then
      for name, instruction in pairs(state_data.templates) do
        if type(name) == "string" and trim(name) ~= "" and type(instruction) == "string" and trim(instruction) ~= "" then
          migrated.templates[name] = instruction
        end
      end
    end
    if type(state_data.hidden_templates) == "table" then
      for name, hidden in pairs(state_data.hidden_templates) do
        if type(name) == "string" and trim(name) ~= "" and hidden == true then
          migrated.hidden_templates[name] = true
        end
      end
    end
    for safe_name, record in pairs(state_data.workspaces) do
      if type(record) == "table" and type(record.project_root) == "string" and record.project_root ~= "" then
        local project = migrated.projects[record.project_root]
        if type(project) ~= "table" then
          project = {
            project_root = record.project_root,
            workspaces = vim.empty_dict and vim.empty_dict() or {},
          }
          migrated.projects[record.project_root] = project
        end
        project.workspaces[safe_name] = M._v5.normalize_record(record, safe_name, record.project_root)
      end
    end
    return migrated
  end

  state_data.version = 2
  if type(state_data.templates) ~= "table" then
    state_data.templates = vim.empty_dict and vim.empty_dict() or {}
  else
    for name, instruction in pairs(state_data.templates) do
      if type(name) ~= "string" or trim(name) == "" or type(instruction) ~= "string" or trim(instruction) == "" then
        state_data.templates[name] = nil
      end
    end
  end
  if type(state_data.hidden_templates) ~= "table" then
    state_data.hidden_templates = vim.empty_dict and vim.empty_dict() or {}
  else
    for name, hidden in pairs(state_data.hidden_templates) do
      if type(name) ~= "string" or trim(name) == "" or hidden ~= true then
        state_data.hidden_templates[name] = nil
      end
    end
  end

  if type(state_data.projects) ~= "table" then
    state_data.projects = vim.empty_dict and vim.empty_dict() or {}
  end

  for root, project in pairs(state_data.projects) do
    if type(project) == "table" then
      project.project_root = type(project.project_root) == "string" and project.project_root ~= "" and project.project_root or root
      if type(project.workspaces) ~= "table" then
        project.workspaces = vim.empty_dict and vim.empty_dict() or {}
      else
        for safe_name, record in pairs(project.workspaces) do
          project.workspaces[safe_name] = M._v5.normalize_record(record, safe_name, project.project_root)
        end
      end
    else
      state_data.projects[root] = {
        project_root = root,
        workspaces = vim.empty_dict and vim.empty_dict() or {},
      }
    end
  end

  return state_data
end

read_workspace_state = function()
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

write_workspace_state = function(state_data)
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
    tmux_target = record.tmux_target or fallback.tmux_target,
    template = record.template or fallback.template,
    custom_instruction = record.custom_instruction or fallback.custom_instruction,
    resolved_instruction = record.resolved_instruction or fallback.resolved_instruction,
    permission_profile = record.permission_profile or fallback.permission_profile or "default",
    codex_status = record.codex_status or fallback.codex_status or "idle",
    status = record.status or fallback.status or "inactive",
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
    tmux_target = workspace.tmux_target,
    template = workspace.template,
    custom_instruction = workspace.custom_instruction,
    resolved_instruction = workspace.resolved_instruction,
    permission_profile = workspace.permission_profile or "default",
    status = workspace.status or existing.status or "idle",
    codex_status = workspace.codex_status or existing.codex_status or "idle",
    created_at = existing.created_at or workspace.created_at or now,
    last_opened_at = now,
    last_reconciled_at = existing.last_reconciled_at,
  }
end

M._sync_workspace_activity = function(codex_status)
  if codex_status ~= "working" and codex_status ~= "question" and codex_status ~= "idle" then
    return false
  end
  if type(state.workspace) ~= "table" then
    return false
  end

  local root = state.workspace.project_root
  local safe_name = state.workspace.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false
  end

  local state_data, state_error = read_workspace_state()
  if state_error then
    return false
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  local record = type(workspaces) == "table" and workspaces[safe_name] or nil
  if type(record) ~= "table" then
    return false
  end

  local workspace_status = codex_status == "working" and "active"
    or codex_status == "question" and "question"
    or "idle"
  if record.codex_status == codex_status and record.status == workspace_status then
    state.workspace.codex_status = codex_status
    state.workspace.status = workspace_status
    return true
  end

  record.codex_status = codex_status
  record.status = workspace_status
  record.last_activity_at = workspace_timestamp()
  project.updated_at = record.last_activity_at

  local write_ok = write_workspace_state(state_data)
  if not write_ok then
    return false
  end

  state.workspace.codex_status = codex_status
  state.workspace.status = record.status
  if state.workspace_manager_project_root == root and type(render_workspace_manager) == "function" then
    render_workspace_manager()
  end

  return true
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
      local status = M._v5.dashboard_workspace_status(record, window_id)
      table.insert(entries, {
        name = record.name or safe_name,
        safe_name = record.safe_name or safe_name,
        project_root = record.project_root or root,
        target_path = record.target_path,
        target_type = record.target_type,
        git_branch = record.git_branch or "",
        window_name = window_name,
        tmux_target = M._v5.tmux_target(session, window_name) or record.tmux_target,
        template = record.template,
        codex_status = record.codex_status or "idle",
        window_id = window_id,
        status = status,
      })
    end
  end

  table.sort(entries, function(left, right)
    return tostring(left.name):lower() < tostring(right.name):lower()
  end)

  return entries, nil
end

function M._v5.entry_for_name(root, name)
  local _, safe_name_or_error = sanitize_workspace_name(name)
  if type(safe_name_or_error) ~= "string" then
    return nil, safe_name_or_error
  end

  local entries, error_message = workspace_entries_for_project(root)
  if error_message then
    return nil, error_message
  end

  for _, entry in ipairs(entries) do
    if entry.safe_name == safe_name_or_error or entry.name == name then
      return entry, nil
    end
  end

  return nil, "workspace not found"
end

function M._v5.names_for_project(root)
  local state_data, state_error = read_workspace_state()
  if state_error then
    return {}
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  if type(workspaces) ~= "table" then
    return {}
  end

  local names = {}
  for safe_name, record in pairs(workspaces) do
    if type(record) == "table" then
      table.insert(names, record.name or safe_name)
    end
  end
  table.sort(names, function(left, right)
    return tostring(left):lower() < tostring(right):lower()
  end)
  return names
end

function M._v5.reconcile_project(root)
  local summary = {
    total = 0,
    active = 0,
    question = 0,
    idle = 0,
    inactive = 0,
    changed = 0,
  }

  local state_data, state_error = read_workspace_state()
  if state_error then
    return summary, state_error
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  if type(workspaces) ~= "table" then
    return summary, nil
  end

  local session = nil
  if vim.fn.executable(tmux_cmd()) == 1 then
    session = current_tmux_session()
  end

  local reconciled_at = workspace_timestamp()
  for safe_name, record in pairs(workspaces) do
    if type(record) == "table" then
      summary.total = summary.total + 1
      local window_name = record.tmux_window or record.window_name or safe_name
      local window_id = session and tmux_window_id(session, window_name) or nil
      local status = M._v5.dashboard_workspace_status(record, window_id)
      if status == "active" then
        summary.active = summary.active + 1
      elseif status == "question" then
        summary.question = summary.question + 1
      elseif status == "idle" then
        summary.idle = summary.idle + 1
      else
        summary.inactive = summary.inactive + 1
      end

      local stale_activity = status == "inactive" and (record.codex_status == "working" or record.codex_status == "question")
      if record.status ~= status or stale_activity then
        summary.changed = summary.changed + 1
      end
      record.status = status
      if status == "inactive" then
        record.codex_status = "idle"
      end
      record.tmux_window = window_name
      record.tmux_target = M._v5.tmux_target(session, window_name) or record.tmux_target
      record.last_reconciled_at = reconciled_at
    end
  end

  project.updated_at = reconciled_at
  local write_ok, write_error = write_workspace_state(state_data)
  if not write_ok then
    return summary, write_error
  end

  return summary, nil
end

local function workspace_manager_project_root()
  return workspace_target_context().root
end

M._stop_workspace_manager_refresh_timer = function()
  local timer = state.workspace_manager_refresh_timer
  state.workspace_manager_refresh_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

M._start_workspace_manager_refresh_timer = function()
  if state.workspace_manager_refresh_timer then
    return
  end

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  state.workspace_manager_refresh_timer = timer
  timer:start(1000, 1000, vim.schedule_wrap(function()
    if not is_valid_win(state.workspace_manager_win) or not is_loaded_buf(state.workspace_manager_buf) then
      M._stop_workspace_manager_refresh_timer()
      return
    end
    if type(render_workspace_manager) == "function" then
      render_workspace_manager()
    end
  end))
end

local function workspace_manager_config(line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local max_width = math.max(1, total_width - 4)
  local width = math.min(max_width, math.max(80, math.min(88, math.floor(total_width * 0.75))))
  local max_height = math.max(1, total_height - 2)
  local min_height = math.min(5, max_height)
  local height = math.min(max_height, math.max(min_height, line_count or 1))

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
  M._stop_workspace_manager_refresh_timer()

  local dashboard_filetypes = {
    ["codux-workspaces"] = true,
    ["codux-workspaces-footer"] = true,
    ["codux-workspaces-search"] = true,
    ["codux-workspaces-command"] = true,
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
  state.workspace_manager_search_win = nil
  state.workspace_manager_search_buf = nil
  state.workspace_manager_command_win = nil
  state.workspace_manager_command_buf = nil
  state.workspace_manager_items = {}
  state.workspace_manager_query = ""
  state.workspace_manager_best_match_index = nil
  state.workspace_manager_selected_index = nil
  state.workspace_manager_focus_match = false
  state.workspace_manager_search_confirmed = false
  state.workspace_manager_project_root = nil
end

local WORKSPACE_MANAGER_NAME_WIDTH = 28
local WORKSPACE_MANAGER_STATUS_WIDTH = 8
local WORKSPACE_MANAGER_GAP = "  "
local workspace_manager_window_width

local function display_width(text)
  local ok, width = pcall(vim.fn.strdisplaywidth, text or "")
  if ok and type(width) == "number" then
    return width
  end

  return #(text or "")
end

local function truncate_display_tail(text, max_width)
  text = tostring(text or "")

  if max_width <= 0 then
    return ""
  end

  if display_width(text) <= max_width then
    return text
  end

  if max_width <= 3 then
    return string.rep(".", max_width)
  end

  local suffix_width = max_width - 3
  local char_count = vim.fn.strchars(text)
  local suffix = ""

  for start = char_count - 1, 0, -1 do
    local candidate = vim.fn.strcharpart(text, start)
    if display_width(candidate) > suffix_width then
      break
    end
    suffix = candidate
  end

  return "..." .. suffix
end

local function pad_display_right(text, width)
  text = truncate_display_tail(text, width)
  return text .. string.rep(" ", math.max(0, width - display_width(text)))
end

local function workspace_manager_column_widths()
  local width = workspace_manager_window_width() or 58
  local gap_width = display_width(WORKSPACE_MANAGER_GAP)
  local available = math.max(1, width - WORKSPACE_MANAGER_STATUS_WIDTH - (gap_width * 2))
  local name_width = math.min(WORKSPACE_MANAGER_NAME_WIDTH, math.max(12, available - 8))
  local target_width = math.max(0, available - name_width)

  return name_width, target_width
end

local function workspace_manager_line(entry)
  local status = entry.status or "inactive"
  local target = type(entry.target_path) == "string" and entry.target_path ~= "" and vim.fn.fnamemodify(entry.target_path, ":t") or ""
  local name_width, target_width = workspace_manager_column_widths()

  return table.concat({
    pad_display_right(entry.name or "", name_width),
    WORKSPACE_MANAGER_GAP,
    pad_display_right(status, WORKSPACE_MANAGER_STATUS_WIDTH),
    WORKSPACE_MANAGER_GAP,
    truncate_display_tail(target, target_width),
  })
end

local function workspace_manager_header_line()
  local name_width = workspace_manager_column_widths()

  return table.concat({
    pad_display_right("workspace", name_width),
    WORKSPACE_MANAGER_GAP,
    pad_display_right("status", WORKSPACE_MANAGER_STATUS_WIDTH),
    WORKSPACE_MANAGER_GAP,
    "target",
  })
end

function M._v5.fuzzy_workspace_score(value, query)
  value = tostring(value or "")
  query = tostring(query or "")
  if query == "" then
    return 0
  end

  local lower_value = value:lower()
  local lower_query = query:lower()
  if #lower_query <= 2 then
    if lower_value:find(lower_query, 1, true) ~= 1 then
      return nil
    end
    return #value - #query
  end

  local positions = {}
  local from = 1

  for index = 1, #lower_query do
    local char = lower_query:sub(index, index)
    local found = lower_value:find(char, from, true)
    if not found then
      return nil
    end
    table.insert(positions, found)
    from = found + 1
  end

  local gaps = 0
  local consecutive = 0
  for index = 2, #positions do
    local gap = positions[index] - positions[index - 1] - 1
    gaps = gaps + gap
    if gap == 0 then
      consecutive = consecutive + 1
    end
  end

  return (positions[1] * 4) + (gaps * 10) + (#value - #query) - (consecutive * 2)
end

function M._v5.fuzzy_workspace_filter(entries, query)
  entries = type(entries) == "table" and entries or {}
  query = tostring(query or "")
  if query == "" then
    return entries
  end

  local scored = {}
  for _, entry in ipairs(entries) do
    local score = M._v5.fuzzy_workspace_score(entry.name, query)
    if score then
      table.insert(scored, { entry = entry, score = score })
    end
  end

  table.sort(scored, function(left, right)
    if left.score == right.score then
      return tostring(left.entry.name):lower() < tostring(right.entry.name):lower()
    end
    return left.score < right.score
  end)

  local matches = {}
  for _, item in ipairs(scored) do
    table.insert(matches, item.entry)
  end
  return matches
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
    { key = "s", desc = "search" },
    { key = "enter", desc = "open" },
    { key = "r", desc = "rename" },
    { key = "e", desc = "edit" },
    { key = "x", desc = "close" },
    { key = "d", desc = "delete" },
    { key = "h", desc = "doctor" },
    { key = "<c-q>", desc = "close" },
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

workspace_manager_window_width = function()
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
  pcall(vim.api.nvim_buf_clear_namespace, state.workspace_manager_footer_buf, state.workspace_manager_ns, 0, -1)

  local col = padding
  for index, segment in ipairs(workspace_manager_footer_segments()) do
    local key_end = col + #segment.key
    pcall(vim.api.nvim_buf_add_highlight, state.workspace_manager_footer_buf, state.workspace_manager_ns, "WhichKey", 0, col, key_end)
    local desc_end = key_end + 1 + #segment.desc
    pcall(vim.api.nvim_buf_add_highlight, state.workspace_manager_footer_buf, state.workspace_manager_ns, "WhichKeySeparator", 0, key_end, desc_end)
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

render_workspace_manager = function()
  if not is_loaded_buf(state.workspace_manager_buf) then
    return false
  end

  local root = state.workspace_manager_project_root or workspace_manager_project_root()
  local all_entries, error_message = workspace_entries_for_project(root)
  local query = tostring(state.workspace_manager_query or "")
  local entries = error_message and all_entries or M._v5.fuzzy_workspace_filter(all_entries, query)
  state.workspace_manager_items = entries
  state.workspace_manager_best_match_index = query ~= "" and #entries > 0 and 1 or nil

  local lines = { workspace_manager_header_line() }
  if error_message then
    table.insert(lines, error_message)
  elseif #all_entries == 0 then
    table.insert(lines, "No saved Codux workspaces")
  elseif query ~= "" and #entries == 0 then
    table.insert(lines, "No matching Codux workspaces")
  else
    for _, entry in ipairs(entries) do
      table.insert(lines, workspace_manager_line(entry))
    end
  end

  table.insert(lines, "")
  local footer_line = math.max(1, workspace_manager_window_height() or (#lines + 1))
  while #lines < footer_line do
    table.insert(lines, "")
  end

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = state.workspace_manager_buf })
  pcall(vim.api.nvim_buf_set_lines, state.workspace_manager_buf, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_clear_namespace, state.workspace_manager_buf, state.workspace_manager_ns, 0, -1)
  pcall(
    vim.api.nvim_buf_add_highlight,
    state.workspace_manager_buf,
    state.workspace_manager_ns,
    "WhichKeyDesc",
    0,
    0,
    -1
  )
  if state.workspace_manager_best_match_index then
    local best_row = 2 + state.workspace_manager_best_match_index - 1
    local match_highlight = state.workspace_manager_search_confirmed and "IncSearch" or "Visual"
    local full_line_ok = pcall(
      vim.api.nvim_buf_set_extmark,
      state.workspace_manager_buf,
      state.workspace_manager_ns,
      best_row - 1,
      0,
      { line_hl_group = match_highlight }
    )
    if not full_line_ok then
      pcall(
        vim.api.nvim_buf_add_highlight,
        state.workspace_manager_buf,
        state.workspace_manager_ns,
        match_highlight,
        best_row - 1,
        0,
        -1
      )
    end
  end
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = state.workspace_manager_buf })
  if state.workspace_manager_focus_match and is_valid_win(state.workspace_manager_win) then
    local row = 1
    if #state.workspace_manager_items > 0 then
      row = 2 + (state.workspace_manager_best_match_index or 1) - 1
    end
    pcall(vim.api.nvim_win_set_cursor, state.workspace_manager_win, { row, 0 })
    state.workspace_manager_focus_match = false
  end
  render_workspace_manager_footer()
  return true
end

local function selected_workspace_manager_item()
  if not is_valid_win(state.workspace_manager_win) then
    return nil
  end

  if state.workspace_manager_search_confirmed and state.workspace_manager_selected_index then
    return state.workspace_manager_items[state.workspace_manager_selected_index]
  end

  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, state.workspace_manager_win)
  if not ok then
    return nil
  end

  local index = cursor[1] - 1
  return state.workspace_manager_items[index]
end

function M._v5.render_workspace_manager_search()
  if not is_loaded_buf(state.workspace_manager_search_buf) then
    return false
  end

  local query = tostring(state.workspace_manager_query or "")
  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = state.workspace_manager_search_buf })
  pcall(
    vim.api.nvim_buf_set_lines,
    state.workspace_manager_search_buf,
    0,
    -1,
    false,
    { query .. " " }
  )
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = state.workspace_manager_search_buf })

  if is_valid_win(state.workspace_manager_search_win) then
    local width = workspace_manager_window_width() or 1
    pcall(vim.api.nvim_win_set_cursor, state.workspace_manager_search_win, { 1, math.min(#query, math.max(0, width - 1)) })
  end

  return true
end

function M._v5.update_workspace_manager_query(query)
  state.workspace_manager_query = tostring(query or "")
  state.workspace_manager_selected_index = nil
  state.workspace_manager_focus_match = true
  state.workspace_manager_search_confirmed = false
  render_workspace_manager()
  M._v5.render_workspace_manager_search()
  return true
end

function M._v5.append_workspace_manager_query(input)
  return M._v5.update_workspace_manager_query(tostring(state.workspace_manager_query or "") .. tostring(input or ""))
end

function M._v5.delete_workspace_manager_query_char()
  local query = tostring(state.workspace_manager_query or "")
  if query == "" then
    return true
  end

  local length = vim.fn.strchars(query)
  return M._v5.update_workspace_manager_query(vim.fn.strcharpart(query, 0, math.max(0, length - 1)))
end

function M._v5.clear_workspace_manager_query()
  if state.workspace_manager_query == "" then
    return true
  end

  return M._v5.update_workspace_manager_query("")
end

function M._v5.open_workspace_manager_search_input()
  if not is_valid_win(state.workspace_manager_win) then
    return false
  end

  if is_valid_win(state.workspace_manager_search_win) then
    pcall(vim.api.nvim_set_current_win, state.workspace_manager_search_win)
    return true
  end

  local buf_ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not buf_ok or not is_loaded_buf(bufnr) then
    notify("Failed to create Codux workspace search", vim.log.levels.ERROR)
    return false
  end

  local dashboard_config = vim.api.nvim_win_get_config(state.workspace_manager_win)
  local dashboard_width = workspace_manager_window_width() or 58
  local width = math.max(20, dashboard_width)
  local col = type(dashboard_config.col) == "number" and dashboard_config.col or 0
  local row = math.max(0, (type(dashboard_config.row) == "number" and dashboard_config.row or 0) - 3)

  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-workspaces-search", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "buftype", "nofile", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "swapfile", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Codux workspace: ",
    title_pos = "center",
    width = width,
    height = 1,
    col = col,
    row = row,
    zindex = 60,
  })
  if not win_ok then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    notify("Failed to open Codux workspace search", vim.log.levels.ERROR)
    return false
  end

  state.workspace_manager_search_buf = bufnr
  state.workspace_manager_search_win = win
  pcall(vim.api.nvim_set_option_value, "number", false, { win = win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = win })
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = win })
  pcall(vim.api.nvim_set_option_value, "winhighlight", "FloatBorder:WhichKey,FloatTitle:WhichKey", { win = win })
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })
  M._v5.render_workspace_manager_search()

  local group = vim.api.nvim_create_augroup("codux-workspace-search-" .. tostring(bufnr), { clear = true })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if state.workspace_manager_search_buf == bufnr then
        state.workspace_manager_search_buf = nil
        state.workspace_manager_search_win = nil
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  M._v5.bind_close_keys(bufnr, close_workspace_manager, "Close Codux Workspaces", "n", { escape = true })
  pcall(vim.keymap.set, "n", "<CR>", function()
    if not state.workspace_manager_best_match_index then
      notify("No Codux workspace selected", vim.log.levels.WARN)
      return false
    end

    state.workspace_manager_search_confirmed = true
    state.workspace_manager_selected_index = state.workspace_manager_best_match_index
    state.workspace_manager_focus_match = false
    render_workspace_manager()
    if is_valid_win(state.workspace_manager_command_win) then
      pcall(vim.api.nvim_set_current_win, state.workspace_manager_command_win)
    elseif is_valid_win(state.workspace_manager_win) then
      pcall(vim.api.nvim_set_current_win, state.workspace_manager_win)
    end
    return true
  end, { buffer = bufnr, silent = true, desc = "Select Codux Workspace" })
  pcall(vim.keymap.set, "n", "<BS>", M._v5.delete_workspace_manager_query_char, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = "Delete Codux Workspace Search Character",
  })
  pcall(vim.keymap.set, "n", "<C-h>", M._v5.delete_workspace_manager_query_char, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = "Delete Codux Workspace Search Character",
  })
  pcall(vim.keymap.set, "n", "<C-u>", M._v5.clear_workspace_manager_query, {
    buffer = bufnr,
    nowait = true,
    silent = true,
    desc = "Clear Codux Workspace Search",
  })
  for _, key in ipairs(printable_prompt_keys()) do
    local lhs = key[1]
    local input = key[2]
    pcall(vim.keymap.set, "n", lhs, function()
      return M._v5.append_workspace_manager_query(input)
    end, {
      buffer = bufnr,
      nowait = true,
      silent = true,
      desc = "Search Codux Workspaces",
    })
  end

  M._v5.render_workspace_manager_search()
  return true
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

  local new_window_name = M._v5.workspace_window_name(safe_name_or_error, existing.template)
  if not rename_tmux_window(entry.window_id, new_window_name) then
    notify("Failed to rename tmux window " .. tostring(entry.window_name), vim.log.levels.ERROR)
    return false
  end

  project.workspaces[entry.safe_name] = nil
  existing.name = display_name
  existing.safe_name = safe_name_or_error
  existing.tmux_window = new_window_name
  existing.tmux_target = M._v5.tmux_target(current_tmux_session(), new_window_name) or existing.tmux_target
  existing.status = M._v5.dashboard_workspace_status(existing, entry.window_id)
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

function M._v5.close_saved_workspace_window(entry)
  local root = entry.project_root or state.workspace_manager_project_root
  local state_data, state_error = read_workspace_state()
  if state_error then
    notify(state_error, vim.log.levels.ERROR)
    return false
  end

  local project = workspace_project_state(state_data, root)
  local existing = project.workspaces[entry.safe_name]
  if type(existing) ~= "table" then
    notify("workspace not found", vim.log.levels.ERROR)
    render_workspace_manager()
    return false
  end

  local session = current_tmux_session()
  local window_name = existing.tmux_window or existing.window_name or entry.window_name or entry.safe_name
  local window_id = entry.window_id or (session and tmux_window_id(session, window_name)) or nil
  if window_id and not kill_tmux_window(window_id) then
    notify("Failed to close tmux window " .. tostring(window_name), vim.log.levels.ERROR)
    return false
  end

  existing.status = "inactive"
  existing.codex_status = "idle"
  existing.tmux_window = window_name
  existing.tmux_target = nil
  existing.last_reconciled_at = workspace_timestamp()
  project.updated_at = existing.last_reconciled_at

  local write_ok, write_error = write_workspace_state(state_data)
  if not write_ok then
    notify(write_error, vim.log.levels.ERROR)
    return false
  end

  notify("Closed Codux workspace " .. tostring(existing.name or entry.name or entry.safe_name))
  render_workspace_manager()
  return true
end

local function workspace_bootstrap_lua(workspace)
  local root = workspace.project_root or "."
  local target_path = workspace.target_path or ""
  local target_type = workspace.target_type or ""
  local profile = workspace.permission_profile or "default"
  local name = workspace.name or workspace.safe_name or ""
  local safe_name = workspace.safe_name or ""
  local branch = workspace.git_branch or ""
  local window_name = workspace.window_name or ""
  local template = workspace.template or ""
  local custom_instruction = workspace.custom_instruction or ""
  local resolved_instruction = workspace.resolved_instruction or ""
  local initial_prompt = workspace.initial_prompt or ""
  local codex_status = initial_prompt ~= "" and "working" or "idle"
  local status = initial_prompt ~= "" and "active" or "idle"
  local show_codux = initial_prompt ~= ""

  return table.concat({
    "local root=" .. lua_string(root),
    "local target=" .. lua_string(target_path),
    "local target_type=" .. lua_string(target_type),
    "local profile=" .. lua_string(profile),
    "local prompt=" .. lua_string(initial_prompt),
    "local show_codux=" .. tostring(show_codux),
    "local workspace={name=" .. lua_string(name) .. ",safe_name=" .. lua_string(safe_name) .. ",project_root=root,target_path=target,target_type=target_type,git_branch=" .. lua_string(branch) .. ",window_name=" .. lua_string(window_name) .. ",template=" .. lua_string(template) .. ",custom_instruction=" .. lua_string(custom_instruction) .. ",resolved_instruction=" .. lua_string(resolved_instruction) .. ",permission_profile=profile,codex_status=" .. lua_string(codex_status) .. ",status=" .. lua_string(status) .. "}",
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
    "local ok_attach,codux_attach=pcall(require,'codux')",
    "if ok_attach and type(codux_attach.attach_workspace)=='function' then codux_attach.attach_workspace(workspace) end",
    "vim.defer_fn(function()",
    "local ok,codux=pcall(require,'codux')",
    "if ok and type(codux.open_workspace_session)=='function' then codux.open_workspace_session(workspace,prompt,{visible=show_codux}) end",
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
  local template = opts.template
  if type(template) == "string" and template ~= "" and not M._v5.template_instruction(template) then
    return nil, "unknown workspace template: " .. template
  end
  local custom_instruction = type(opts.custom_instruction) == "string" and trim(opts.custom_instruction) or nil
  if custom_instruction == "" then
    custom_instruction = nil
  end
  local resolved_instruction = type(opts.resolved_instruction) == "string" and trim(opts.resolved_instruction) or nil
  if resolved_instruction == "" then
    resolved_instruction = nil
  end

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
    window_name = M._v5.workspace_window_name(safe_name_or_error, template),
    template = template,
    custom_instruction = custom_instruction,
    resolved_instruction = resolved_instruction,
    permission_profile = workspace_permission_profile(),
    codex_status = "idle",
    status = "idle",
  }
  local workspace = workspace_from_state(existing, fallback)
  if type(template) == "string" and template ~= "" then
    workspace.template = template
  end
  if custom_instruction then
    workspace.custom_instruction = custom_instruction
  end
  workspace.session = session
  workspace.safe_name = workspace.safe_name or safe_name_or_error
  workspace.window_name = M._v5.workspace_window_name(workspace.safe_name, workspace.template)
  workspace.project_root = workspace.project_root or root
  workspace.tmux_target = M._v5.tmux_target(session, workspace.window_name)

  if not resolved_instruction and type(workspace.resolved_instruction) == "string" and trim(workspace.resolved_instruction) ~= "" then
    resolved_instruction = workspace.resolved_instruction
  end
  local template_prompt = M._v5.template_instruction(workspace.template)
  if not resolved_instruction and type(template_prompt) == "string" and template_prompt ~= "" then
    resolved_instruction = template_prompt
  end
  if resolved_instruction then
    workspace.resolved_instruction = resolved_instruction
    workspace.initial_prompt = resolved_instruction
  end

  local window_id, created = ensure_tmux_window(session, workspace.project_root, workspace.window_name, workspace_nvim_command(workspace))
  if not window_id then
    return nil, "Failed to create tmux window " .. workspace.window_name
  end

  workspace.window_id = window_id
  if created and not workspace.initial_prompt then
    workspace.codex_status = "idle"
  end
  workspace.status = M._v5.dashboard_workspace_status(workspace, window_id)
  if created and workspace.initial_prompt then
    workspace.status = "active"
    workspace.codex_status = "working"
  elseif workspace.status ~= "active" then
    if workspace.status == "question" then
      workspace.codex_status = "question"
    else
      workspace.codex_status = "idle"
    end
  end
  workspace.initial_prompt = nil
  project.workspaces[workspace.safe_name] = workspace_state_record(workspace, existing)
  project.updated_at = workspace_timestamp()

  local write_ok, write_error = write_workspace_state(state_data)
  if not write_ok then
    return nil, write_error
  end

  return workspace, nil
end

function M._v5.parse_create_args(args)
  args = type(args) == "table" and args or {}
  local name = args[1]
  if type(name) ~= "string" or trim(name) == "" then
    return nil, nil, false, "Workspace name is required"
  end
  if name:match("^%-%-") then
    return nil, nil, false, "Workspace name is required"
  end

  local template = nil
  local custom_requested = false
  local index = 2
  while index <= #args do
    local arg = args[index]
    if arg == "--template" then
      template = args[index + 1]
      if type(template) ~= "string" or trim(template) == "" then
        return nil, nil, false, "--template requires a template name"
      end
      index = index + 2
    elseif arg == "--custom" then
      custom_requested = true
      index = index + 1
    else
      local inline_template = type(arg) == "string" and arg:match("^%-%-template=(.+)$") or nil
      if inline_template then
        template = inline_template
        index = index + 1
      else
        return nil, nil, false, "unknown workspace option: " .. tostring(arg)
      end
    end
  end

  if custom_requested and type(template) == "string" and trim(template) ~= "" then
    return nil, nil, false, "--custom cannot be combined with --template"
  end

  return name, template, custom_requested, nil
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
        M._sync_workspace_activity("idle")
        state.last_prompt_line = nil
        state.workspace = nil
        state.workspace_target_signature = nil
        state.workspace_target_update_pending = false
        if type(stop_token_monitor_timer) == "function" then
          stop_token_monitor_timer()
        end
        set_codex_working(false, { force_idle = true })
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
  state.last_prompt_line = nil
  state.permission_profile = permission_profile or "default"
  state.last_permission_profile = state.permission_profile
  if workspace ~= nil then
    state.workspace = workspace
  end
  if valid_win() then
    pcall(vim.api.nvim_set_option_value, "wrap", true, { win = state.win })
  end
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

  return start_terminal(focus, opts.initial_prompt, nil, nil, "default")
end

local function restart_with_command(command, focus, permission_profile, initial_prompt)
  M.exit()
  return start_terminal(focus ~= false, initial_prompt, command, nil, permission_profile)
end

local function start_hidden_with_command(command, permission_profile, initial_prompt)
  return start_terminal(false, initial_prompt, command, nil, permission_profile, { hidden = true })
end

function M.open_workspace_auto(initial_prompt)
  notify("Starting Codex autopilot with approve-for-me permissions")
  return restart_with_command(config.workspace_auto_cmd, true, "auto", initial_prompt)
end

function M.open_danger_full_access(initial_prompt)
  notify("Starting Codex with no approvals and no sandbox", vim.log.levels.WARN)
  return restart_with_command(config.danger_full_access_cmd, true, "danger", initial_prompt)
end

function M.open_workspace_session(workspace, initial_prompt, opts)
  opts = opts or {}
  workspace = type(workspace) == "table" and workspace or nil
  local profile = workspace and workspace.permission_profile or opts.permission_profile or "default"
  local command = config.codex_cmd
  if profile == "auto" then
    command = config.workspace_auto_cmd
  elseif profile == "danger" then
    command = config.danger_full_access_cmd
  else
    profile = "default"
  end

  local visible = opts.visible == true
  return start_terminal(visible, initial_prompt, command, workspace, profile, { hidden = not visible })
end

function M.open_hidden(initial_prompt)
  return start_hidden_with_command(config.codex_cmd, "default", initial_prompt)
end

function M.open_workspace_auto_hidden(initial_prompt)
  return start_hidden_with_command(config.workspace_auto_cmd, "auto", initial_prompt)
end

function M.open_danger_full_access_hidden(initial_prompt)
  return start_hidden_with_command(config.danger_full_access_cmd, "danger", initial_prompt)
end

function M.open_workspace_auto_hidden_with_notice()
  notify("Starting Codex autopilot with approve-for-me permissions")
  return M.open_workspace_auto_hidden()
end

function M.open_danger_full_access_hidden_with_notice()
  notify("Starting Codex with no approvals and no sandbox", vim.log.levels.WARN)
  return M.open_danger_full_access_hidden()
end

function M.create_workspace(name, opts)
  opts = opts or {}
  local workspace, error_message = prepare_workspace(name, {
    template = opts.template,
    custom_instruction = opts.custom_instruction,
    resolved_instruction = opts.resolved_instruction,
  })
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

function M.open_workspace(name)
  return M.create_workspace(name)
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

function M.select_workspace(name)
  return M.open_saved_workspace(name, workspace_manager_project_root())
end

function M.rename_workspace(old_name, new_name)
  local root = workspace_manager_project_root()
  local entry, error_message = M._v5.entry_for_name(root, old_name)
  if not entry then
    notify(error_message or "workspace not found", vim.log.levels.ERROR)
    return false
  end

  return rename_saved_workspace(entry, new_name)
end

function M.delete_workspace(name)
  local root = workspace_manager_project_root()
  local entry, error_message = M._v5.entry_for_name(root, name)
  if not entry then
    notify(error_message or "workspace not found", vim.log.levels.ERROR)
    return false
  end

  return delete_saved_workspace(entry)
end

function M.restore_workspaces(opts)
  opts = opts or {}
  local root = opts.project_root or workspace_manager_project_root()
  local summary, error_message = M._v5.reconcile_project(root)
  if error_message then
    notify(error_message, vim.log.levels.WARN)
    return false
  end

  if not opts.silent then
    notify(
      "Restored Codux workspaces: "
        .. tostring(summary.total)
        .. " total, "
        .. tostring(summary.active)
        .. " active, "
        .. tostring(summary.question)
        .. " question, "
        .. tostring(summary.idle)
        .. " idle, "
        .. tostring(summary.inactive)
        .. " inactive"
    )
  end

  if state.workspace_manager_project_root == root and type(render_workspace_manager) == "function" then
    render_workspace_manager()
  end

  return true
end

function M.workspace_template_list()
  local names = M._v5.template_names()
  notify("Codux workspace templates:\n" .. table.concat(names, "\n"))
  return names
end

function M.workspace_template_preview(name)
  local instruction = M._v5.template_instruction(name)
  if not instruction then
    notify("unknown workspace template: " .. tostring(name), vim.log.levels.ERROR)
    return false
  end

  notify(tostring(name) .. ":\n" .. instruction)
  return true
end

function M.workspace_template_delete(name)
  local ok, error_message = M._v5.delete_template(name)
  if not ok then
    notify(error_message or "Failed to delete Codux workspace template", vim.log.levels.ERROR)
    return false
  end

  notify("Deleted Codux workspace template " .. tostring(name))
  return true
end

function M._v5.workspace_create_template_label(request)
  if type(request.template) == "string" and request.template ~= "" then
    return request.template
  end
  if type(request.resolved_instruction) == "string" and trim(request.resolved_instruction) ~= "" then
    return "custom"
  end
  return "none"
end

function M._v5.workspace_create_preview_lines(request)
  local lines = {
    "Create Codux workspace?",
    "",
    "Name: " .. tostring(request.name or ""),
    "Template: " .. M._v5.workspace_create_template_label(request),
    "",
    "Instruction:",
  }
  local instruction = type(request.resolved_instruction) == "string" and trim(request.resolved_instruction) or ""
  if instruction == "" then
    table.insert(lines, "(none)")
  else
    for _, line in ipairs(vim.split(instruction, "\n", { plain = true })) do
      table.insert(lines, line)
    end
  end
  table.insert(lines, "")
  return lines
end

function M._v5.workspace_create_preview_config(line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local width = math.min(82, math.max(50, math.floor(total_width * 0.62)))
  local height = math.min(math.max(10, (line_count or 1) + 1), math.max(6, total_height - 4))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " create codux workspace ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
  }
end

function M._v5.workspace_create_footer_segments()
  return {
    { key = "enter", desc = "create" },
    { key = "e", desc = "edit instruction" },
    { key = "<c-q>", desc = "cancel" },
  }
end

function M._v5.workspace_create_footer_line()
  local parts = {}
  local segments = M._v5.workspace_create_footer_segments()
  for index, segment in ipairs(segments) do
    table.insert(parts, segment.key .. " " .. segment.desc)
    if index < #segments then
      table.insert(parts, "  ")
    end
  end

  return table.concat(parts, "")
end

function M._v5.render_workspace_create_footer(bufnr, width)
  if not is_loaded_buf(bufnr) then
    return false
  end

  width = type(width) == "number" and width > 0 and width or 1
  local line = M._v5.workspace_create_footer_line()
  local padding = math.max(0, math.floor((width - #line) / 2))
  local text = string.rep(" ", padding) .. line

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = bufnr })
  pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, { text })
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.workspace_manager_ns, 0, -1)

  local col = padding
  local segments = M._v5.workspace_create_footer_segments()
  for index, segment in ipairs(segments) do
    local key_end = col + #segment.key
    pcall(vim.api.nvim_buf_add_highlight, bufnr, state.workspace_manager_ns, "WhichKey", 0, col, key_end)
    local desc_end = key_end + 1 + #segment.desc
    pcall(vim.api.nvim_buf_add_highlight, bufnr, state.workspace_manager_ns, "WhichKeySeparator", 0, key_end, desc_end)
    col = desc_end
    if index < #segments then
      col = col + 2
    end
  end

  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })
  return true
end

function M._v5.open_workspace_create_footer(win)
  if not is_valid_win(win) then
    return nil, nil
  end

  local buf_ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not buf_ok or not is_loaded_buf(bufnr) then
    return nil, nil
  end

  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-workspace-create-footer", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

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
    zindex = 51,
  })
  if not win_ok then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return nil, nil
  end

  M._v5.render_workspace_create_footer(bufnr, width)
  return bufnr, footer_win
end

function M._v5.workspace_instruction_editor_config(line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local width = math.min(96, math.max(58, math.floor(total_width * 0.72)))
  local height = math.min(math.max(11, (line_count or 1) + 1), math.max(8, total_height - 4))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " workspace instruction · vim-mode ",
    title_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
  }
end

function M._v5.workspace_instruction_footer_segments()
  return {
    { key = ":w", desc = "save" },
    { key = "<c-q>", desc = "cancel" },
  }
end

function M._v5.workspace_instruction_footer_line()
  local parts = {}
  local segments = M._v5.workspace_instruction_footer_segments()
  for index, segment in ipairs(segments) do
    table.insert(parts, segment.key .. " " .. segment.desc)
    if index < #segments then
      table.insert(parts, "  ")
    end
  end

  return table.concat(parts, "")
end

function M._v5.render_workspace_instruction_footer(bufnr, width)
  if not is_loaded_buf(bufnr) then
    return false
  end

  width = type(width) == "number" and width > 0 and width or 1
  local line = M._v5.workspace_instruction_footer_line()
  local padding = math.max(0, math.floor((width - #line) / 2))
  local text = string.rep(" ", padding) .. line

  pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = bufnr })
  pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, { text })
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.workspace_manager_ns, 0, -1)

  local col = padding
  local segments = M._v5.workspace_instruction_footer_segments()
  for index, segment in ipairs(segments) do
    local key_end = col + #segment.key
    pcall(vim.api.nvim_buf_add_highlight, bufnr, state.workspace_manager_ns, "WhichKey", 0, col, key_end)
    local desc_end = key_end + 1 + #segment.desc
    pcall(vim.api.nvim_buf_add_highlight, bufnr, state.workspace_manager_ns, "WhichKeySeparator", 0, key_end, desc_end)
    col = desc_end
    if index < #segments then
      col = col + 2
    end
  end

  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })
  return true
end

function M._v5.open_workspace_instruction_footer(win)
  if not is_valid_win(win) then
    return nil, nil
  end

  local buf_ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not buf_ok or not is_loaded_buf(bufnr) then
    return nil, nil
  end

  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-workspace-instruction-footer", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

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
    zindex = 51,
  })
  if not win_ok then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return nil, nil
  end

  M._v5.render_workspace_instruction_footer(bufnr, width)
  return bufnr, footer_win
end

function M._v5.open_workspace_instruction_editor(request, opts)
  request = type(request) == "table" and request or {}
  opts = type(opts) == "table" and opts or {}
  local instruction = type(request.resolved_instruction) == "string" and request.resolved_instruction or ""
  local lines = vim.split(instruction, "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end

  local buf_ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not buf_ok or not is_loaded_buf(bufnr) then
    notify("Failed to create Codux workspace instruction editor", vim.log.levels.ERROR)
    return false
  end

  pcall(vim.api.nvim_set_option_value, "buftype", "acwrite", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "swapfile", false, { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-workspace-instruction", { buf = bufnr })
  pcall(vim.api.nvim_buf_set_name, bufnr, "codux://workspace-instruction/" .. tostring(bufnr))
  pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, lines)
  pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, M._v5.workspace_instruction_editor_config(#lines + 2))
  if not win_ok then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    notify("Failed to open Codux workspace instruction editor", vim.log.levels.ERROR)
    return false
  end

  pcall(vim.api.nvim_set_option_value, "wrap", true, { win = win })
  pcall(vim.api.nvim_set_option_value, "linebreak", true, { win = win })
  local footer_buf, footer_win = M._v5.open_workspace_instruction_footer(win)
  local closed = false
  local saved = false
  local autocmd_group = vim.api.nvim_create_augroup("codux-workspace-instruction-" .. tostring(bufnr), { clear = true })

  local function close_editor()
    closed = true
    if is_valid_win(footer_win) then
      pcall(vim.api.nvim_win_close, footer_win, true)
    end
    if is_loaded_buf(footer_buf) then
      pcall(vim.api.nvim_buf_delete, footer_buf, { force = true })
    end
    if is_valid_win(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if is_loaded_buf(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
    pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
  end

  local function cancel_editor()
    close_editor()
    if type(opts.on_cancel) == "function" then
      opts.on_cancel(request)
    end
  end

  local function save_editor()
    pcall(vim.cmd, "stopinsert")
    if not is_loaded_buf(bufnr) then
      return
    end

    local saved_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local saved_instruction = trim(table.concat(saved_lines, "\n"))
    if saved_instruction == "" then
      notify("Workspace instruction is required", vim.log.levels.WARN)
      if is_valid_win(win) then
        pcall(vim.api.nvim_set_current_win, win)
      end
      return
    end

    request.resolved_instruction = saved_instruction
    if
      not request.template_edit
      and (
        type(request.template) ~= "string"
        or request.template == ""
        or type(request.custom_template_name) == "string"
      )
    then
      local template_name, template_error =
        M._v5.save_custom_template_for_workspace(request.name, saved_instruction, request.custom_template_name)
      if not template_name then
        notify(template_error or "Failed to save Codux workspace template", vim.log.levels.ERROR)
        if is_valid_win(win) then
          pcall(vim.api.nvim_set_current_win, win)
        end
        return
      end

      request.template = template_name
      request.custom_template_name = template_name
      request.custom_instruction = saved_instruction
    end

    saved = true
    close_editor()
    if type(opts.on_save) == "function" then
      opts.on_save(request)
    else
      M._v5.open_workspace_create_preview(request)
    end
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = autocmd_group,
    buffer = bufnr,
    callback = save_editor,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = autocmd_group,
    buffer = bufnr,
    callback = function()
      if is_loaded_buf(bufnr) then
        pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = autocmd_group,
    pattern = tostring(win),
    callback = function()
      if is_valid_win(footer_win) then
        pcall(vim.api.nvim_win_close, footer_win, true)
      end
      if is_loaded_buf(footer_buf) then
        pcall(vim.api.nvim_buf_delete, footer_buf, { force = true })
      end
      if not closed and not saved and type(opts.on_cancel) == "function" then
        vim.schedule(function()
          opts.on_cancel(request)
        end)
      end
      pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
    end,
  })

  pcall(vim.keymap.set, "n", "<C-s>", save_editor, { buffer = bufnr, silent = true, desc = "Save Codux Workspace Instruction" })
  pcall(vim.keymap.set, "i", "<C-s>", save_editor, { buffer = bufnr, silent = true, desc = "Save Codux Workspace Instruction" })
  M._v5.bind_close_keys(bufnr, cancel_editor, "Cancel Codux Workspace Instruction", { "n", "i" })
  pcall(vim.cmd, "startinsert")
  return true
end

function M._v5.open_workspace_create_preview(request)
  request = type(request) == "table" and request or {}
  local lines = M._v5.workspace_create_preview_lines(request)
  local buf_ok, bufnr = pcall(vim.api.nvim_create_buf, false, true)
  if not buf_ok or not is_loaded_buf(bufnr) then
    notify("Failed to create Codux workspace preview", vim.log.levels.ERROR)
    return false
  end

  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = bufnr })
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-workspace-create", { buf = bufnr })
  pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, M._v5.workspace_create_preview_config(#lines))
  if not win_ok then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    notify("Failed to open Codux workspace preview", vim.log.levels.ERROR)
    return false
  end
  pcall(vim.api.nvim_set_option_value, "wrap", true, { win = win })
  pcall(vim.api.nvim_set_option_value, "linebreak", true, { win = win })
  local footer_buf, footer_win = M._v5.open_workspace_create_footer(win)

  local function close_preview()
    if is_valid_win(footer_win) then
      pcall(vim.api.nvim_win_close, footer_win, true)
    end
    if is_loaded_buf(footer_buf) then
      pcall(vim.api.nvim_buf_delete, footer_buf, { force = true })
    end
    if is_valid_win(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if is_loaded_buf(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end

  local function create_workspace_from_preview()
    close_preview()
    M.create_workspace(request.name, {
      template = request.template,
      custom_instruction = request.custom_instruction,
      resolved_instruction = request.resolved_instruction,
    })
  end

  local function edit_instruction_from_preview()
    close_preview()
    M._v5.open_workspace_instruction_editor(request, {
      on_cancel = M._v5.open_workspace_create_preview,
      on_save = M._v5.open_workspace_create_preview,
    })
  end

  pcall(vim.keymap.set, "n", "<CR>", create_workspace_from_preview, { buffer = bufnr, silent = true, desc = "Create Codux Workspace" })
  pcall(vim.keymap.set, "n", "e", edit_instruction_from_preview, { buffer = bufnr, silent = true, desc = "Edit Codux Workspace Instruction" })
  M._v5.bind_close_keys(bufnr, close_preview, "Cancel Codux Workspace Create", "n", { escape = true, q = true })
  return true
end

function M._v5.open_custom_workspace_instruction_prompt(name)
  if not current_tmux_session() then
    notify("no tmux session running", vim.log.levels.ERROR)
    return false
  end

  return M._v5.open_workspace_instruction_editor({
    name = name,
  }, {
    on_save = M._v5.open_workspace_create_preview,
  })
end

function M.open_workspace_prompt()
  if not current_tmux_session() then
    notify("no tmux session running", vim.log.levels.ERROR)
    return false
  end

  M._v5.single_line_prompt({ prompt = "Codux workspace: " }, function(input)
    local name = trim(input)
    if name == "" then
      return
    end

    M._v5.open_custom_workspace_instruction_prompt(name)
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
  M.restore_workspaces({ project_root = state.workspace_manager_project_root, silent = true })
  local preview_entries = workspace_entries_for_project(state.workspace_manager_project_root)
  local line_count = 1 + math.max(1, #preview_entries) + 1
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

  local function open_selected_workspace()
    local item = selected_or_notify()
    if not item then
      return false
    end
    local root = state.workspace_manager_project_root
    close_workspace_manager()
    return M.open_saved_workspace(item.name, root)
  end

  local function rename_selected_workspace()
    local item = selected_or_notify()
    if not item then
      return false
    end
    M._v5.single_line_prompt({ prompt = "Rename Codux workspace: ", default = item.name }, function(input)
      local new_name = trim(input)
      if new_name == "" then
        return
      end
      rename_saved_workspace(item, new_name)
    end)
  end

  local function edit_selected_workspace_template()
    local item = selected_or_notify()
    if not item then
      return false
    end

    local template_name = type(item.template) == "string" and trim(item.template) or ""
    if template_name == "" then
      notify("Codux workspace has no template to edit", vim.log.levels.WARN)
      return false
    end
    if M._v5.template_source(template_name) ~= "saved" then
      notify("Codux workspace template is not editable: " .. template_name, vim.log.levels.WARN)
      return false
    end

    local instruction = M._v5.template_instruction(template_name)
    if type(instruction) ~= "string" or trim(instruction) == "" then
      notify("unknown workspace template: " .. template_name, vim.log.levels.ERROR)
      return false
    end

    close_workspace_manager()
    return M._v5.open_workspace_instruction_editor({
      name = item.name,
      template = template_name,
      template_edit = true,
      resolved_instruction = instruction,
    }, {
      on_cancel = M.open_workspaces,
      on_save = function(request)
        local ok, error_message = M._v5.save_existing_template(template_name, request.resolved_instruction)
        if not ok then
          notify(error_message or "Failed to save Codux workspace template", vim.log.levels.ERROR)
          return M.open_workspaces()
        end

        notify("Saved Codux workspace template " .. template_name)
        return M.open_workspaces()
      end,
    })
  end

  local function delete_selected_workspace()
    local item = selected_or_notify()
    if not item then
      return false
    end
    local choice = vim.fn.confirm("Delete Codux workspace " .. item.name .. "?", "&Yes\n&No", 2)
    if choice == 1 then
      delete_saved_workspace(item)
    end
  end

  local function close_selected_workspace_window()
    local item = selected_or_notify()
    if not item then
      return false
    end
    return M._v5.close_saved_workspace_window(item)
  end

  local function open_codux_menu()
    close_workspace_manager()
    vim.schedule(function()
      local leader = tostring(vim.g.mapleader or "\\")
      local keys = vim.api.nvim_replace_termcodes(leader .. "z", true, false, true)
      vim.api.nvim_feedkeys(keys, "m", false)
    end)
  end

  local function bind_workspace_manager_commands(target_bufnr)
    M._v5.bind_close_keys(target_bufnr, close_workspace_manager, "Close Codux Workspaces", "n", { escape = true, q = true })
    pcall(vim.keymap.set, "n", "<leader>z", open_codux_menu, {
      buffer = target_bufnr,
      silent = true,
      nowait = true,
      desc = "Open Codux Menu",
    })
    pcall(vim.keymap.set, "n", "s", M._v5.open_workspace_manager_search_input, {
      buffer = target_bufnr,
      silent = true,
      desc = "Search Codux Workspaces",
    })
    pcall(vim.keymap.set, "n", "<CR>", open_selected_workspace, {
      buffer = target_bufnr,
      silent = true,
      desc = "Open Codux Workspace",
    })
    pcall(vim.keymap.set, "n", "r", rename_selected_workspace, {
      buffer = target_bufnr,
      silent = true,
      desc = "Rename Codux Workspace",
    })
    pcall(vim.keymap.set, "n", "e", edit_selected_workspace_template, {
      buffer = target_bufnr,
      silent = true,
      desc = "Edit Codux Workspace Template",
    })
    pcall(vim.keymap.set, "n", "x", close_selected_workspace_window, {
      buffer = target_bufnr,
      silent = true,
      desc = "Close Codux Workspace Window",
    })
    pcall(vim.keymap.set, "n", "d", delete_selected_workspace, {
      buffer = target_bufnr,
      silent = true,
      desc = "Delete Codux Workspace",
    })
    pcall(vim.keymap.set, "n", "h", function()
      return M.doctor()
    end, { buffer = target_bufnr, silent = true, desc = "Run Codux Doctor" })
  end

  local function open_workspace_manager_command_sink()
    local sink_buf_ok, sink_bufnr = pcall(vim.api.nvim_create_buf, false, true)
    if not sink_buf_ok or not is_loaded_buf(sink_bufnr) then
      return false
    end

    pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = sink_bufnr })
    pcall(vim.api.nvim_set_option_value, "filetype", "codux-workspaces-command", { buf = sink_bufnr })
    pcall(vim.api.nvim_set_option_value, "buftype", "nofile", { buf = sink_bufnr })
    pcall(vim.api.nvim_set_option_value, "swapfile", false, { buf = sink_bufnr })
    pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = sink_bufnr })

    local sink_win_ok, sink_win = pcall(vim.api.nvim_open_win, sink_bufnr, false, {
      relative = "editor",
      style = "minimal",
      border = "none",
      width = 1,
      height = 1,
      col = vim.o.columns + 1,
      row = vim.o.lines + 1,
      zindex = 1,
    })
    if not sink_win_ok then
      pcall(vim.api.nvim_buf_delete, sink_bufnr, { force = true })
      return false
    end

    state.workspace_manager_command_buf = sink_bufnr
    state.workspace_manager_command_win = sink_win
    pcall(vim.api.nvim_set_option_value, "number", false, { win = sink_win })
    pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = sink_win })
    pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = sink_win })
    pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = sink_win })
    bind_workspace_manager_commands(sink_bufnr)
    return true
  end

  bind_workspace_manager_commands(bufnr)
  open_workspace_manager_command_sink()

  render_workspace_manager()
  M._start_workspace_manager_refresh_timer()
  if #state.workspace_manager_items > 0 then
    pcall(vim.api.nvim_win_set_cursor, win, { 2, 0 })
  end
  vim.schedule(function()
    if is_valid_win(state.workspace_manager_win) and is_loaded_buf(state.workspace_manager_buf) then
      M._v5.open_workspace_manager_search_input()
    end
  end)
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
  M._sync_workspace_activity("idle")
  state.last_prompt_line = nil
  state.workspace = nil
  state.workspace_target_signature = nil
  state.workspace_target_update_pending = false
  if type(stop_token_monitor_timer) == "function" then
    stop_token_monitor_timer()
  end
  set_codex_working(false, { force_idle = true })
  set_mode("not running")

  if valid_win() then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil

  state.buf = nil
  if not running and is_valid_buf(bufnr) then
    delete_buffer_deferred(bufnr)
  end
  set_codex_working(false, { force_idle = true })

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

  M._v5.mark_terminal_prompt_submission()
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

M._workspace_target_signature = function(path, target_type, branch)
  return table.concat({
    tostring(path or ""),
    tostring(target_type or ""),
    tostring(branch or ""),
  }, "\0")
end

M._workspace_target_sync_allowed = function(event)
  if type(state.workspace) ~= "table" or type(state.workspace.safe_name) ~= "string" then
    return false
  end

  local filetype = current_filetype()
  if
    filetype == "codux"
    or filetype == "codux-workspaces"
    or filetype == "codux-workspaces-footer"
    or filetype == "codux-workspace-create"
    or filetype == "codux-workspace-create-footer"
    or filetype == "codux-workspace-instruction"
    or filetype == "codux-workspace-instruction-footer"
  then
    return false
  end

  if event == "CursorMoved" and not is_explorer_filetype(filetype) then
    return false
  end

  return true
end

M._sync_workspace_target = function(event)
  if not M._workspace_target_sync_allowed(event) then
    return false
  end

  local workspace = state.workspace
  local root = workspace.project_root
  local safe_name = workspace.safe_name
  if type(root) ~= "string" or root == "" or type(safe_name) ~= "string" or safe_name == "" then
    return false
  end

  local context = workspace_target_context()
  local path = context.path
  if type(path) ~= "string" or path == "" or path:match("^term://") or path:match("^codux://") then
    return false
  end

  local target_type = context.target and context.target.type or (vim.fn.isdirectory(path) == 1 and "directory" or "file")
  local branch = context.branch or ""
  local signature = M._workspace_target_signature(path, target_type, branch)
  if signature == state.workspace_target_signature then
    return true
  end

  local state_data, state_error = read_workspace_state()
  if state_error then
    return false
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  local record = type(workspaces) == "table" and workspaces[safe_name] or nil
  if type(record) ~= "table" then
    return false
  end

  record.target_path = path
  record.target_type = target_type
  record.git_branch = branch
  record.last_target_at = workspace_timestamp()
  project.updated_at = record.last_target_at

  local write_ok = write_workspace_state(state_data)
  if not write_ok then
    return false
  end

  workspace.target_path = path
  workspace.target_type = target_type
  workspace.git_branch = branch
  state.workspace_target_signature = signature

  if state.workspace_manager_project_root == root and type(render_workspace_manager) == "function" then
    render_workspace_manager()
  end

  return true
end

M._schedule_workspace_target_sync = function(event)
  if state.workspace_target_update_pending then
    return
  end

  state.workspace_target_update_pending = true
  vim.defer_fn(function()
    state.workspace_target_update_pending = false
    M._sync_workspace_target(event)
  end, 150)
end

function M.attach_workspace(workspace)
  if type(workspace) ~= "table" then
    return false
  end

  local attached = workspace_from_state(workspace, workspace)
  if type(attached.safe_name) ~= "string" or attached.safe_name == "" then
    return false
  end
  if type(attached.project_root) ~= "string" or attached.project_root == "" then
    return false
  end

  state.workspace = attached
  state.workspace_target_signature =
    M._workspace_target_signature(attached.target_path, attached.target_type, attached.git_branch)
  M._schedule_workspace_target_sync("attach")
  return true
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

function M.doctor()
  local lines = { "codux.nvim doctor", "" }
  local function add(status, message)
    table.insert(lines, status .. " " .. message)
  end

  local tmux = tmux_cmd()
  if vim.fn.executable(tmux) == 1 then
    add("[ok]", "tmux found: " .. tmux)
  else
    add("[warn]", "tmux not found: " .. tmux)
  end

  local session = current_tmux_session()
  if session then
    add("[ok]", "tmux server reachable: " .. session)
  else
    add("[warn]", "tmux server not reachable or Neovim is outside tmux")
  end

  local codex_executable = command_executable(config.codex_cmd) or "codex"
  if vim.fn.executable(codex_executable) == 1 then
    add("[ok]", "codex found: " .. codex_executable)
  else
    add("[warn]", "codex command not found: " .. tostring(codex_executable))
  end

  local state_file = workspace_state_file()
  local state_dir = vim.fn.fnamemodify(state_file, ":h")
  if vim.fn.filereadable(state_file) == 1 then
    add("[ok]", "workspace state readable")
  elseif vim.fn.isdirectory(state_dir) == 1 then
    add("[ok]", "workspace state will be created on first use")
  else
    add("[warn]", "workspace state directory missing: " .. state_dir)
  end

  if vim.fn.filewritable(state_file) == 1 or vim.fn.filewritable(state_dir) == 2 then
    add("[ok]", "workspace state writable")
  else
    add("[warn]", "workspace state not writable: " .. state_file)
  end

  local root = workspace_manager_project_root()
  if type(root) == "string" and root ~= "" then
    add("[ok]", "project root detected: " .. root)
  else
    add("[warn]", "project root not detected")
  end

  local state_data, state_error = read_workspace_state()
  if state_error then
    add("[warn]", state_error)
  end

  local project = type(state_data.projects) == "table" and state_data.projects[root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  local workspace_count = 0
  local invalid_count = 0
  if type(workspaces) == "table" then
    for safe_name, record in pairs(workspaces) do
      if type(record) == "table" and type(record.name) == "string" and type(record.project_root) == "string" then
        workspace_count = workspace_count + 1
      else
        invalid_count = invalid_count + 1
        if type(safe_name) == "string" then
          workspace_count = workspace_count + 1
        end
      end
    end
  end
  add("[ok]", tostring(workspace_count) .. " workspaces loaded")
  if invalid_count > 0 then
    add("[warn]", tostring(invalid_count) .. " workspace records invalid")
  end

  local entries, entries_error = workspace_entries_for_project(root)
  if entries_error then
    add("[warn]", "dashboard target resolution failed: " .. entries_error)
  else
    add("[ok]", "dashboard can resolve targets")
    local inactive = 0
    for _, entry in ipairs(entries) do
      if entry.status == "inactive" then
        inactive = inactive + 1
      end
    end
    if inactive > 0 then
      add("[warn]", tostring(inactive) .. " workspace windows inactive")
    else
      add("[ok]", "no workspace windows inactive")
    end
  end

  notify(table.concat(lines, "\n"))
  return lines
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

function M._v5.filter_completion(values, arglead)
  local matches = {}
  arglead = arglead or ""
  for _, value in ipairs(values) do
    if arglead == "" or tostring(value):find(arglead, 1, true) == 1 then
      table.insert(matches, value)
    end
  end
  return matches
end

function M._v5.complete_workspace_names(arglead)
  return M._v5.filter_completion(M._v5.names_for_project(workspace_manager_project_root()), arglead)
end

function M._v5.complete_template_names(arglead)
  return M._v5.filter_completion(M._v5.template_names(), arglead)
end

function M._v5.complete_create(arglead, cmdline, cursorpos)
  local before_cursor = cmdline:sub(1, math.max(0, cursorpos or #cmdline))
  if before_cursor:match("%-%-template%s+[^%s]*$") then
    return M._v5.complete_template_names(arglead)
  end

  local inline = arglead:match("^%-%-template=(.*)$")
  if inline ~= nil then
    local matches = {}
    for _, name in ipairs(M._v5.complete_template_names(inline)) do
      table.insert(matches, "--template=" .. name)
    end
    return matches
  end

  return M._v5.filter_completion({ "--custom", "--template" }, arglead)
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
    if #opts.fargs == 0 then
      M.open_workspace_prompt()
      return
    end

    local name, template, custom_requested, error_message = M._v5.parse_create_args(opts.fargs)
    if error_message then
      notify(error_message, vim.log.levels.ERROR)
      return
    end
    if custom_requested or type(template) ~= "string" or trim(template) == "" then
      M._v5.open_custom_workspace_instruction_prompt(name)
      return
    end
    M.create_workspace(name, { template = template })
  end, { force = true, nargs = "*", complete = M._v5.complete_create, desc = "Create a named Codux tmux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceCreate", function(opts)
    if #opts.fargs == 0 then
      M.open_workspace_prompt()
      return
    end

    local name, template, custom_requested, error_message = M._v5.parse_create_args(opts.fargs)
    if error_message then
      notify(error_message, vim.log.levels.ERROR)
      return
    end
    if custom_requested or type(template) ~= "string" or trim(template) == "" then
      M._v5.open_custom_workspace_instruction_prompt(name)
      return
    end
    M.create_workspace(name, { template = template })
  end, { force = true, nargs = "*", complete = M._v5.complete_create, desc = "Create a named Codux tmux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceOpen", function(opts)
    M.open_saved_workspace(opts.args, workspace_manager_project_root())
  end, { force = true, nargs = 1, complete = M._v5.complete_workspace_names, desc = "Open a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceSelect", function(opts)
    M.select_workspace(opts.args)
  end, { force = true, nargs = 1, complete = M._v5.complete_workspace_names, desc = "Select a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceDelete", function(opts)
    M.delete_workspace(opts.args)
  end, { force = true, nargs = 1, complete = M._v5.complete_workspace_names, desc = "Delete a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceRename", function(opts)
    local old_name = opts.fargs[1]
    local new_name = opts.fargs[2]
    if type(old_name) ~= "string" or old_name == "" or type(new_name) ~= "string" or new_name == "" then
      notify("Usage: CoduxWorkspaceRename <old> <new>", vim.log.levels.ERROR)
      return
    end
    M.rename_workspace(old_name, new_name)
  end, { force = true, nargs = "+", complete = M._v5.complete_workspace_names, desc = "Rename a saved Codux workspace" })

  vim.api.nvim_create_user_command("CoduxWorkspaceRestore", function()
    M.restore_workspaces()
  end, { force = true, desc = "Restore Codux workspace status from tmux" })

  vim.api.nvim_create_user_command("CoduxWorkspaceTemplateList", function()
    M.workspace_template_list()
  end, { force = true, desc = "List Codux workspace templates" })

  vim.api.nvim_create_user_command("CoduxWorkspaceTemplatePreview", function(opts)
    M.workspace_template_preview(opts.args)
  end, { force = true, nargs = 1, complete = M._v5.complete_template_names, desc = "Preview a Codux workspace template" })

  vim.api.nvim_create_user_command("CoduxWorkspaceTemplateDelete", function(opts)
    M.workspace_template_delete(opts.args)
  end, { force = true, nargs = 1, complete = M._v5.complete_template_names, desc = "Delete a Codux workspace template" })

  vim.api.nvim_create_user_command("CoduxTemplateList", function()
    M.workspace_template_list()
  end, { force = true, desc = "List Codux workspace templates" })

  vim.api.nvim_create_user_command("CoduxTemplatePreview", function(opts)
    M.workspace_template_preview(opts.args)
  end, { force = true, nargs = 1, complete = M._v5.complete_template_names, desc = "Preview a Codux workspace template" })

  vim.api.nvim_create_user_command("CoduxTemplateDelete", function(opts)
    M.workspace_template_delete(opts.args)
  end, { force = true, nargs = 1, complete = M._v5.complete_template_names, desc = "Delete a Codux workspace template" })

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

  vim.api.nvim_create_user_command("CoduxDoctor", function()
    M.doctor()
  end, { force = true, desc = "Run codux.nvim troubleshooting checks" })
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

M._install_workspace_target_autocmds = function()
  pcall(vim.api.nvim_clear_autocmds, {
    group = augroup,
    event = { "BufEnter", "BufWinEnter", "WinEnter", "DirChanged", "CursorMoved" },
  })
  pcall(vim.api.nvim_create_autocmd, { "BufEnter", "BufWinEnter", "WinEnter", "DirChanged" }, {
    group = augroup,
    callback = function(args)
      M._schedule_workspace_target_sync(args.event)
    end,
  })
  pcall(vim.api.nvim_create_autocmd, "CursorMoved", {
    group = augroup,
    callback = function(args)
      if is_explorer_filetype(current_filetype()) then
        M._schedule_workspace_target_sync(args.event)
      end
    end,
  })
end

function M.setup(opts)
  stop_token_monitor_timer()
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  create_commands()

  local mappings = type(config.mappings) == "table" and config.mappings or {}
  refresh_which_key()
  set_mapping("n", mappings.open, M.open, "open codex")
  set_mapping("n", mappings.open_auto, M.open_workspace_auto_hidden_with_notice, "codex autopilot")
  set_mapping("n", mappings.open_danger, M.open_danger_full_access_hidden_with_notice, "codex danger zone")
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
  M._install_workspace_target_autocmds()

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
