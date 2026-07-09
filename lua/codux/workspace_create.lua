local M = {}
M.__index = M

local confirmation_footer = require("codux.confirmation_footer")
local mission_mod = require("codux.mission")
local text_util = require("codux.text")

local function default_trim(value)
  return text_util.trim(value)
end

local function noop() end

local function mission_context(opts)
  opts = type(opts) == "table" and opts or {}
  local context = type(opts.mission_context) == "table" and opts.mission_context or opts
  if type(context.mission_id) ~= "string" or context.mission_id == "" then
    return nil
  end
  return {
    mission_id = context.mission_id,
    mission_name = context.mission_name or context.mission_id,
    mission_objective = context.mission_objective,
    mission_focus_packet = context.mission_focus_packet,
    agent_provider = context.agent_provider,
  }
end

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local controller = {
    notify = type(opts.notify) == "function" and opts.notify or function(message, level)
      vim.notify(message, level or vim.log.levels.INFO, { title = "codux.nvim" })
    end,
    trim = type(opts.trim) == "function" and opts.trim or default_trim,
    ui = type(opts.ui) == "table" and opts.ui or require("codux.ui"),
    workspace_ui = type(opts.workspace_ui) == "table" and opts.workspace_ui or require("codux.workspace_ui"),
    is_loaded_buf = type(opts.is_loaded_buf) == "function" and opts.is_loaded_buf or function()
      return false
    end,
    is_valid_win = type(opts.is_valid_win) == "function" and opts.is_valid_win or function()
      return false
    end,
    set_buffer_keymap = type(opts.set_buffer_keymap) == "function" and opts.set_buffer_keymap or noop,
    bind_close_keys = type(opts.bind_close_keys) == "function" and opts.bind_close_keys or noop,
    single_line_prompt = type(opts.single_line_prompt) == "function" and opts.single_line_prompt or noop,
    has_tmux_session = type(opts.has_tmux_session) == "function" and opts.has_tmux_session or function()
      return false
    end,
    create_workspace = type(opts.create_workspace) == "function" and opts.create_workspace or noop,
    namespace = opts.namespace or vim.api.nvim_create_namespace("codux.workspace_create"),
  }

  return setmetatable(controller, M)
end

function M:preview_lines(request)
  request = type(request) == "table" and request or {}
  local lines = {
    "Create Codux workspace?",
    "",
    "Name: " .. tostring(request.name or ""),
  }
  if type(request.mission_id) == "string" and request.mission_id ~= "" then
    table.insert(lines, "Mission: " .. tostring(request.mission_name or request.mission_id))
  end
  if type(request.agent_provider) == "string" and request.agent_provider ~= "" then
    table.insert(lines, "Agent: " .. tostring(request.agent_provider))
  end
  table.insert(lines, "")
  table.insert(lines, "Instruction:")
  local instruction = type(request.resolved_instruction) == "string" and self.trim(request.resolved_instruction) or ""
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

function M:create_preview_config(line_count)
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

function M:create_footer_segments()
  return self.workspace_ui.create_footer_segments()
end

function M:create_footer_line()
  return confirmation_footer.line(self, {
    segments = self:create_footer_segments(),
  })
end

function M:render_create_footer(bufnr, width)
  return confirmation_footer.render(self, bufnr, {
    width = width,
    segments = self:create_footer_segments(),
  })
end

function M:open_create_footer(win)
  return confirmation_footer.open(self, win, {
    filetype = "codux-workspace-create-footer",
    zindex = 51,
    segments = self:create_footer_segments(),
  })
end

function M:instruction_editor_config(line_count)
  local total_width = math.max(1, vim.o.columns)
  local total_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local width = math.min(96, math.max(58, math.floor(total_width * 0.72)))
  local height = math.min(math.max(11, line_count or 1), math.max(8, total_height - 4))

  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Workspace Instruction ",
    title_pos = "center",
    footer = " NORMAL ",
    footer_pos = "center",
    width = width,
    height = height,
    col = math.max(0, math.floor((total_width - width) / 2)),
    row = math.max(0, math.floor((total_height - height) / 2)),
  }
end

function M.instruction_mode_label(mode)
  if type(mode) ~= "string" or mode == "" then
    local ok, current_mode = pcall(vim.api.nvim_get_mode)
    mode = ok and type(current_mode) == "table" and current_mode.mode or "n"
  end

  if mode:sub(1, 1) == "i" then
    return " INSERT "
  end
  if mode:sub(1, 1) == "R" then
    return " REPLACE "
  end
  if mode == "v" or mode == "V" or mode == "\22" then
    return " VISUAL "
  end
  if mode == "s" or mode == "S" or mode == "\19" then
    return " SELECT "
  end
  if mode:sub(1, 1) == "c" then
    return " COMMAND "
  end
  if mode:sub(1, 1) == "t" then
    return " TERMINAL "
  end

  return " NORMAL "
end

function M:update_instruction_mode_footer(win)
  if not self.is_valid_win(win) then
    return false
  end

  local config_ok, win_config = pcall(vim.api.nvim_win_get_config, win)
  if not config_ok or type(win_config) ~= "table" then
    return false
  end

  win_config.footer = M.instruction_mode_label()
  win_config.footer_pos = "center"
  local set_ok = pcall(vim.api.nvim_win_set_config, win, win_config)
  return set_ok
end

function M:disable_instruction_completion(bufnr)
  local disable_buffer_completion = type(self.ui) == "table" and self.ui.disable_buffer_completion
    or require("codux.ui").disable_buffer_completion
  return disable_buffer_completion(bufnr, { is_loaded_buf = self.is_loaded_buf })
end

function M:open_instruction_editor(request, opts)
  request = type(request) == "table" and request or {}
  opts = type(opts) == "table" and opts or {}
  local instruction = type(request.resolved_instruction) == "string" and request.resolved_instruction or ""
  local lines = vim.split(instruction, "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end

  local bufnr = self.ui.create_scratch_buffer({
    buftype = "acwrite",
    bufhidden = "wipe",
    swapfile = false,
    filetype = "codux-workspace-instruction",
  })
  if not bufnr then
    self.notify("Failed to create Codux workspace instruction editor", vim.log.levels.ERROR)
    return false
  end

  pcall(vim.api.nvim_buf_set_name, bufnr, "codux://workspace-instruction/" .. tostring(bufnr))
  self.ui.set_lines(bufnr, lines)
  pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
  self:disable_instruction_completion(bufnr)

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:instruction_editor_config(#lines))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux workspace instruction editor", vim.log.levels.ERROR)
    return false
  end

  self.ui.set_window_options(win, {
    number = true,
    relativenumber = false,
    cursorline = true,
    signcolumn = "yes",
    winfixbuf = true,
    wrap = true,
    linebreak = true,
  })
  pcall(vim.cmd, "stopinsert")
  self:update_instruction_mode_footer(win)
  local closed = false
  local saved = false
  local autocmd_group = vim.api.nvim_create_augroup("codux-workspace-instruction-" .. tostring(bufnr), { clear = true })

  local function close_editor()
    closed = true
    self.ui.close_window(win)
    self.ui.delete_buffer(bufnr)
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
    if not self.is_loaded_buf(bufnr) then
      return
    end

    local saved_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local saved_instruction = self.trim(table.concat(saved_lines, "\n"))
    if saved_instruction == "" then
      self.notify("Workspace instruction is required", vim.log.levels.WARN)
      if self.is_valid_win(win) then
        pcall(vim.api.nvim_set_current_win, win)
      end
      return
    end

    request.resolved_instruction = saved_instruction
    request.custom_instruction = saved_instruction

    saved = true
    close_editor()
    if type(opts.on_save) == "function" then
      opts.on_save(request)
    else
      self:open_create_preview(request)
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
      if self.is_loaded_buf(bufnr) then
        pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "ModeChanged", "InsertEnter", "InsertLeave" }, {
    group = autocmd_group,
    callback = function()
      self:update_instruction_mode_footer(win)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = autocmd_group,
    pattern = tostring(win),
    callback = function()
      if not closed and not saved and type(opts.on_cancel) == "function" then
        vim.schedule(function()
          opts.on_cancel(request)
        end)
      end
      pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
    end,
  })

  self.set_buffer_keymap(bufnr, "n", "<C-s>", save_editor, "Save Codux Workspace Instruction")
  self.set_buffer_keymap(bufnr, "i", "<C-s>", save_editor, "Save Codux Workspace Instruction")
  self.bind_close_keys(bufnr, cancel_editor, "Cancel Codux Workspace Instruction", { "n", "i" })
  return true
end

function M:open_create_preview(request)
  request = type(request) == "table" and request or {}
  local lines = self:preview_lines(request)
  local bufnr = self.ui.create_scratch_buffer({
    bufhidden = "wipe",
    filetype = "codux-workspace-create",
  })
  if not bufnr then
    self.notify("Failed to create Codux workspace preview", vim.log.levels.ERROR)
    return false
  end

  self.ui.set_lines(bufnr, lines)
  pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = bufnr })

  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, self:create_preview_config(#lines))
  if not win_ok then
    self.ui.delete_buffer(bufnr)
    self.notify("Failed to open Codux workspace preview", vim.log.levels.ERROR)
    return false
  end
  self.ui.set_window_options(win, {
    wrap = true,
    linebreak = true,
  })
  local footer_buf, footer_win = self:open_create_footer(win)

  local function close_preview()
    self.ui.close_window(footer_win)
    self.ui.delete_buffer(footer_buf)
    self.ui.close_window(win)
    self.ui.delete_buffer(bufnr)
  end

  local function create_workspace_from_preview()
    close_preview()
    local custom_instruction = request.custom_instruction
    local resolved_instruction = request.resolved_instruction
    local mission_role = nil
    if type(request.mission_id) == "string" and request.mission_id ~= "" then
      mission_role = request.name
      local role = mission_mod.role_from_entry({
        name = request.name,
        mission_role = request.name,
        resolved_instruction = resolved_instruction,
        custom_instruction = custom_instruction,
      })
      role.focus = self.trim(custom_instruction or resolved_instruction or role.focus)
      resolved_instruction = mission_mod.role_instruction(request.mission_name, request.mission_objective, role)
      custom_instruction = resolved_instruction
    end
    self.create_workspace(request.name, {
      custom_instruction = custom_instruction,
      resolved_instruction = resolved_instruction,
      agent_provider = request.agent_provider,
      mission_id = request.mission_id,
      mission_name = request.mission_name,
      mission_role = mission_role,
      mission_objective = request.mission_objective,
      mission_focus_packet = request.mission_focus_packet,
    })
  end

  local function edit_instruction_from_preview()
    close_preview()
    self:open_instruction_editor(request, {
      on_cancel = function(next_request)
        self:open_create_preview(next_request)
      end,
      on_save = function(next_request)
        self:open_create_preview(next_request)
      end,
    })
  end

  self.set_buffer_keymap(bufnr, "n", "<CR>", create_workspace_from_preview, "Create Codux Workspace")
  self.set_buffer_keymap(bufnr, "n", "e", edit_instruction_from_preview, "Edit Codux Workspace Instruction")
  self.bind_close_keys(bufnr, close_preview, "Cancel Codux Workspace Create", "n", { escape = true, q = true })
  return true
end

function M:open_custom_instruction_prompt(name, opts)
  if not self.has_tmux_session() then
    self.notify("no tmux session running", vim.log.levels.ERROR)
    return false
  end

  local context = mission_context(opts)
  local request = {
    name = name,
  }
  if context then
    request.mission_id = context.mission_id
    request.mission_name = context.mission_name
    request.mission_objective = context.mission_objective
    request.mission_focus_packet = context.mission_focus_packet
    request.agent_provider = context.agent_provider
  end
  if type(opts.agent_provider) == "string" and opts.agent_provider ~= "" then
    request.agent_provider = opts.agent_provider
  end

  return self:open_instruction_editor(request, {
    on_save = function(request)
      self:open_create_preview(request)
    end,
  })
end

function M:open_prompt(opts)
  if not self.has_tmux_session() then
    self.notify("no tmux session running", vim.log.levels.ERROR)
    return false
  end

  local context = mission_context(opts)
  self.single_line_prompt({ prompt = "Codux workspace: " }, function(input)
    local name = self.trim(input)
    if name == "" then
      return
    end

    self:open_custom_instruction_prompt(name, context)
  end)
  return true
end

return M
