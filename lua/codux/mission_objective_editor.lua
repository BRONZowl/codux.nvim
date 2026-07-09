local text_util = require("codux.text")
local ui = require("codux.ui")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.open(controller, name, default_objective, opts)
  opts = type(opts) == "table" and opts or {}
  local mission_name, name_error = controller.mission.sanitize_mission_name(name)
  if not mission_name then
    controller.notify(name_error, vim.log.levels.ERROR)
    return false
  end

  local bufnr = controller.ui.create_scratch_buffer({
    buftype = "acwrite",
    bufhidden = "wipe",
    swapfile = false,
    filetype = "codux-mission-objective",
  })
  if not bufnr then
    controller.notify("Failed to create Codux mission editor", vim.log.levels.ERROR)
    return false
  end

  pcall(vim.api.nvim_buf_set_name, bufnr, "codux://mission-objective/" .. tostring(bufnr))
  local objective_lines = vim.split(tostring(default_objective or ""), "\n", { plain = true })
  if #objective_lines == 0 then
    objective_lines = { "" }
  end
  controller.ui.set_lines(bufnr, objective_lines)
  pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
  local win_ok, win = pcall(vim.api.nvim_open_win, bufnr, true, controller:objective_editor_config(#objective_lines, opts))
  if not win_ok then
    controller.ui.delete_buffer(bufnr)
    controller.notify("Failed to open Codux mission editor", vim.log.levels.ERROR)
    return false
  end
  controller.ui.set_window_options(win, {
    number = true,
    relativenumber = false,
    cursorline = true,
    signcolumn = "yes",
    winfixbuf = true,
    wrap = true,
    linebreak = true,
    winhighlight = "FloatBorder:WhichKey,FloatTitle:WhichKey",
  })
  ui.disable_buffer_completion(bufnr, { is_loaded_buf = controller.is_loaded_buf })
  pcall(vim.cmd, "stopinsert")

  local closed = false
  local saved = false
  local autocmd_group = vim.api.nvim_create_augroup("codux-mission-objective-" .. tostring(bufnr), { clear = true })

  local function close_editor()
    closed = true
    controller.ui.close_window(win)
    controller.ui.delete_buffer(bufnr)
    pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
  end

  local function save_editor()
    local objective = trim(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"))
    if objective == "" then
      controller.notify("Mission objective is required", vim.log.levels.WARN)
      return
    end

    if type(opts.on_save) == "function" then
      local ok = opts.on_save(mission_name, objective)
      if ok == false then
        return
      end

      saved = true
      pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
      close_editor()
      return
    end

    local mission, plan_error = controller.mission.plan(mission_name, objective)
    if not mission then
      controller.notify(plan_error, vim.log.levels.ERROR)
      return
    end
    if type(opts.agent_provider) == "string" and opts.agent_provider ~= "" then
      mission.agent_provider = opts.agent_provider
    end
    if type(opts.permission_profile) == "string" and opts.permission_profile ~= "" then
      mission.permission_profile = opts.permission_profile
    end

    saved = true
    pcall(vim.api.nvim_set_option_value, "modified", false, { buf = bufnr })
    close_editor()
    controller:open_preview(mission)
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = autocmd_group,
    buffer = bufnr,
    callback = save_editor,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = autocmd_group,
    pattern = tostring(win),
    callback = function()
      if not closed and not saved then
        pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
      end
    end,
  })

  controller.set_buffer_keymap(bufnr, "n", "<C-s>", save_editor, "Preview Codux Mission")
  controller.set_buffer_keymap(bufnr, "i", "<C-s>", save_editor, "Preview Codux Mission")
  controller.bind_close_keys(bufnr, close_editor, "Cancel Codux Mission", { "n", "i" })
  return true
end

return M
