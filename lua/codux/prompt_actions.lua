local M = {}
M.__index = M

local function noop() end

function M.normalize_selection_positions(start_pos, end_pos)
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

function M.selection_from_lines(lines, start_col, end_col, mode)
  if type(lines) ~= "table" or vim.tbl_isempty(lines) then
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

  return table.concat(lines, "\n")
end

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local actions = {
    get_config = type(opts.get_config) == "function" and opts.get_config or function()
      return {}
    end,
    notify = type(opts.notify) == "function" and opts.notify or function(message, level)
      vim.notify(message, level or vim.log.levels.INFO, { title = "codux.nvim" })
    end,
    send_to_codex = type(opts.send_to_codex) == "function" and opts.send_to_codex or function()
      return false
    end,
    exit = type(opts.exit) == "function" and opts.exit or noop,
    context = opts.context,
    current_filetype = type(opts.current_filetype) == "function" and opts.current_filetype or function()
      return "unknown"
    end,
    current_buffer = type(opts.current_buffer) == "function" and opts.current_buffer or function()
      return vim.api.nvim_get_current_buf()
    end,
    buffer_lines = type(opts.buffer_lines) == "function" and opts.buffer_lines or function(bufnr, start_line, end_line)
      local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, end_line, false)
      return ok and lines or nil
    end,
    mode = type(opts.mode) == "function" and opts.mode or function()
      return vim.fn.mode()
    end,
    getpos = type(opts.getpos) == "function" and opts.getpos or function(mark)
      return vim.fn.getpos(mark)
    end,
    visualmode = type(opts.visualmode) == "function" and opts.visualmode or function()
      return vim.fn.visualmode()
    end,
  }

  return setmetatable(actions, M)
end

function M:config()
  local config = self.get_config()
  return type(config) == "table" and config or {}
end

function M:send_prompt(prompt_key, prompt_context)
  local prompts = type(self:config().prompts) == "table" and self:config().prompts or {}
  local template = prompts[prompt_key]
  if template == nil then
    self.notify("Prompt is not configured: " .. prompt_key, vim.log.levels.WARN)
    return false
  end

  local prompt = self.context.render_prompt(template, prompt_context)
  if not prompt or prompt == "" then
    self.notify("Prompt is empty", vim.log.levels.WARN)
    return false
  end

  return self.send_to_codex(prompt)
end

function M:send_file_review()
  local target = self.context.current_target()
  if not target then
    self.notify("No file or file explorer node selected for review", vim.log.levels.WARN)
    return false
  end

  return self:send_prompt("file", self.context.context_for_target(target))
end

function M:send_file_fix()
  return self:send_file_review()
end

function M:selection_from_positions(start_pos, end_pos, mode)
  local bufnr = self.current_buffer()
  local start_line, start_col, end_line, end_col = M.normalize_selection_positions(start_pos, end_pos)
  if not start_line then
    return nil
  end

  local lines = self.buffer_lines(bufnr, start_line - 1, end_line)
  local selected = M.selection_from_lines(lines, start_col, end_col, mode)
  if not selected then
    return nil
  end

  return selected, start_line, end_line
end

function M:active_visual_mode()
  local mode = self.mode()
  if mode == "v" or mode == "V" or mode == "s" or mode == "S" or mode == "\22" or mode == "\19" then
    return mode
  end

  return nil
end

function M:selection_from_active_visual()
  local mode = self:active_visual_mode()
  if not mode then
    return nil
  end

  return self:selection_from_positions(self.getpos("v"), self.getpos("."), mode)
end

function M:selection_from_marks()
  return self:selection_from_positions(self.getpos("'<"), self.getpos("'>"), self.visualmode())
end

function M:selection_from_range(opts)
  if type(opts) == "table" and opts.range == 0 then
    return nil
  end

  if type(opts) ~= "table" or not opts.line1 or not opts.line2 or opts.line1 == 0 or opts.line2 == 0 then
    local selected, start_line, end_line = self:selection_from_active_visual()
    if selected then
      return selected, start_line, end_line
    end
    return self:selection_from_marks()
  end

  local bufnr = self.current_buffer()
  local start_line = math.min(opts.line1, opts.line2)
  local end_line = math.max(opts.line1, opts.line2)
  local lines = self.buffer_lines(bufnr, start_line - 1, end_line)
  if not lines or vim.tbl_isempty(lines) then
    return nil
  end

  return table.concat(lines, "\n"), start_line, end_line
end

function M:send_selection(opts)
  local selected, start_line, end_line = self:selection_from_range(opts)
  if not selected or selected == "" then
    self.notify("No selected code to send", vim.log.levels.WARN)
    return false
  end

  local target = self.context.current_buffer_target()
  if not target then
    self.notify("No file path for selected code", vim.log.levels.WARN)
    return false
  end

  return self:send_prompt(
    "review_selection",
    self.context.context_for_target(target, {
      selection = selected,
      line_range = string.format(":%d-%d", start_line, end_line),
    })
  )
end

function M:send_diagnostics()
  local bufnr = self.current_buffer()
  local filetype = self.current_filetype()
  local target = self.context.current_target()
  local fallback_path = nil

  if target and target.source == "buffer" and self.context.is_explorer_filetype(filetype) then
    target = nil
    fallback_path = ""
  end

  local diagnostics = self.context.collect_diagnostics(bufnr)
  if not diagnostics then
    self.notify("No Issues Found", vim.log.levels.INFO)
    self.exit()
    return true
  end

  return self:send_prompt(
    "diagnostics",
    self.context.context_for_target(target, {
      fallback_path = fallback_path,
      diagnostics = diagnostics.text,
      diagnostics_source = diagnostics.source,
      filetype = filetype,
    })
  )
end

function M:send_git_diff()
  local root = self.context.git_root_for(self.context.git_diff_target_path())
  if not root then
    self.notify("Not inside a Git repository", vim.log.levels.WARN)
    return false
  end

  local diff, error_message = self.context.format_git_diff_context(root)
  if not diff then
    self.notify(error_message or "No Git changes found", vim.log.levels.INFO)
    return error_message == "No Git changes found"
  end

  return self:send_prompt(
    "git_diff",
    self.context.context_for_target({
      path = root,
      type = "directory",
      source = "git",
    }, {
      git_branch = self.context.git_branch_or_head(root),
      git_diff = diff,
    })
  )
end

return M
