local M = {}

local defaults = {
  codex_cmd = vim.env.CODEX_CMD or "codex -s workspace-write -a on-request",
  auto_open = true,
  auto_focus = true,
  popup = {
    width = 0.85,
    height = 0.85,
    border = "rounded",
  },
  health_timeout_ms = 10000,
  mappings = {
    open = "<leader>zc",
    review_file = "<leader>zf",
    review_selection = "<leader>zs",
    diagnostics = "<leader>zd",
  },
  prompts = {
    file = "Review this %{target_type}, identify issues, and suggest or make fixes where appropriate: %{path}",
    review_selection = "Review this selected code from %{relative_path}%{line_range} (%{filetype}):\n\n%{selection}",
    diagnostics = "Explain these %{diagnostics_source} issues for %{relative_path}, identify the likely causes, and suggest fixes:\n\n%{diagnostics}",
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
  exiting_jobs = {},
  pending_delete_buffers = {},
}

local augroup = vim.api.nvim_create_augroup("codux.nvim", { clear = true })

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "codux.nvim" })
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
    return false
  end

  if not valid_buf() then
    pcall(vim.fn.jobstop, state.job_id)
    state.exiting_jobs[state.job_id] = nil
    state.job_id = nil
    return false
  end

  local wait_ok, statuses = pcall(vim.fn.jobwait, { state.job_id }, 0)
  if not wait_ok or type(statuses) ~= "table" then
    state.exiting_jobs[state.job_id] = nil
    state.job_id = nil
    return false
  end

  local status = statuses[1]
  if status == -1 then
    return true
  end

  state.job_id = nil
  return false
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
    vim.cmd("startinsert")
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

  return {
    relative = "editor",
    style = "minimal",
    border = popup.border or "rounded",
    width = width,
    height = height,
    col = math.floor((total_width - width) / 2),
    row = math.floor((total_height - height) / 2),
  }
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
  pcall(vim.keymap.set, "n", "q", M.close, { buffer = bufnr, silent = true, desc = "Hide Codux Popup" })

  pcall(vim.api.nvim_create_autocmd, { "BufUnload", "BufDelete", "BufWipeout" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      if state.buf == bufnr then
        state.buf = nil
        state.job_id = nil
      end
    end,
  })

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
  pcall(vim.api.nvim_set_option_value, "number", false, { win = state.win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = state.win })
  pcall(vim.api.nvim_set_option_value, "signcolumn", "no", { win = state.win })
  pcall(vim.api.nvim_set_option_value, "winfixbuf", true, { win = state.win })

  local win_id = state.win
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(win_id),
    once = true,
    callback = function()
      if state.win == win_id then
        state.win = nil
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

local function codex_command_error(command)
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

local function start_terminal(focus, initial_prompt)
  if terminal_running() then
    if focus then
      focus_window()
    end
    return true
  end

  local command_error = codex_command_error(config.codex_cmd)
  if command_error then
    notify(command_error, vim.log.levels.ERROR)
    return false
  end

  if
    type(config.codex_cmd) == "string"
    and vim.fn.executable("codex") ~= 1
    and config.codex_cmd:match("^%s*codex[%s$]")
  then
    notify("Codex CLI not found on PATH", vim.log.levels.WARN)
  end

  local previous_win = vim.api.nvim_get_current_win()
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
    return start_terminal(focus, initial_prompt)
  end

  local job_id
  local term_ok
  term_ok, job_id = pcall(vim.fn.termopen, command_with_prompt(config.codex_cmd, initial_prompt), {
    on_exit = function(_, code)
      local expected_exit = state.exiting_jobs[job_id] == true
      local pending_delete_buffer = state.pending_delete_buffers[job_id]
      state.exiting_jobs[job_id] = nil
      state.pending_delete_buffers[job_id] = nil
      if state.job_id == job_id then
        state.job_id = nil
      end
      if not expected_exit and code ~= 0 then
        notify("Codex exited with code " .. tostring(code), vim.log.levels.WARN)
      end
      if pending_delete_buffer ~= nil then
        delete_buffer_deferred(pending_delete_buffer)
      end
    end,
  })

  if not term_ok or type(job_id) ~= "number" or job_id <= 0 then
    state.job_id = nil
    notify("Failed to start Codex", vim.log.levels.ERROR)
    if is_valid_win(previous_win) then
      pcall(vim.api.nvim_set_current_win, previous_win)
    end
    return false
  end

  state.job_id = job_id

  if focus then
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

  return start_terminal(focus, initial_prompt)
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

  return start_terminal(focus)
end

function M.close()
  if valid_win() then
    pcall(vim.api.nvim_win_close, state.win, true)
    state.win = nil
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

  if valid_win() then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil

  state.buf = nil
  if not running and is_valid_buf(bufnr) then
    delete_buffer_deferred(bufnr)
  end

  return true
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

local function current_target()
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

local function git_branch_for(path)
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

local function selection_from_marks()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
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

  local lines = buffer_lines(bufnr, start_line - 1, end_line)
  if not lines or vim.tbl_isempty(lines) then
    return nil
  end

  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  return table.concat(lines, "\n"), start_line, end_line
end

local function selection_from_range(opts)
  if type(opts) == "table" and opts.range == 0 then
    return nil
  end

  if type(opts) ~= "table" or not opts.line1 or not opts.line2 or opts.line1 == 0 or opts.line2 == 0 then
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
  }
end

local function create_commands()
  vim.api.nvim_create_user_command("CoduxOpen", function()
    M.open()
  end, { force = true, desc = "Open or focus the Codex popup" })

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

  vim.api.nvim_create_user_command("CoduxHealth", function()
    M.health()
  end, { force = true, desc = "Run codux.nvim health checks" })
end

local function set_mapping(mode, lhs, rhs, desc)
  if type(lhs) == "string" and lhs ~= "" then
    vim.keymap.set(mode, lhs, rhs, { desc = desc })
  end
end

local function register_which_key_group(mappings)
  local ok, which_key = pcall(require, "which-key")
  if not ok then
    return
  end
  local group_label = "codux"
  local group_icon = "󰚩"

  local has_codux_prefix = false
  for _, lhs in pairs(mappings) do
    if type(lhs) == "string" and lhs:match("^<leader>z") then
      has_codux_prefix = true
      break
    end
  end

  if not has_codux_prefix then
    return
  end

  if type(which_key.add) == "function" then
    pcall(which_key.add, { { "<leader>z", group = group_label, icon = group_icon } })
  elseif type(which_key.register) == "function" then
    pcall(which_key.register, { z = { name = group_icon .. " " .. group_label } }, { prefix = "<leader>" })
  end
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  create_commands()

  local mappings = type(config.mappings) == "table" and config.mappings or {}
  register_which_key_group(mappings)
  set_mapping("n", mappings.open, M.open, "open codex")
  set_mapping("n", mappings.review_file, M.send_file_review, "send file/folder to codex")
  set_mapping("v", mappings.review_selection, M.send_selection, "Codux: send selection")
  set_mapping("n", mappings.diagnostics, M.send_diagnostics, "send diagnostics to codex")
end

return M
