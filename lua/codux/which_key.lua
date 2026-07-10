local M = {}
M.__index = M

local codux_icon = "󰚩"

local markers = {
  "open codux",
  "codex autopilot",
  "codex danger zone",
  "send file/folder",
  "send selection",
  "send diagnostics",
  "send git diff",
  "create codux workspace",
  "current codux workspaces",
  "switch to execute mode",
  "switch to plan mode",
}

local function noop() end

local function mode_display_label(display_label, mode)
  if type(display_label) == "function" then
    return display_label(mode)
  end
  if mode == "execute" then
    return "exec"
  end
  return mode or "not running"
end

local function mode_action_desc_for(mode)
  if mode == "execute" then
    return "switch to plan mode"
  end
  if mode == "plan" then
    return "switch to execute mode"
  end

  return nil
end

local function mode_status_hl_for(mode)
  if mode == "execute" then
    return "CoduxWhichKeyExecute"
  end
  if mode == "plan" then
    return "CoduxWhichKeyPlan"
  end

  return "CoduxWhichKeyNotRunning"
end

function M.mode_action_desc(value)
  local mode = type(value) == "table" and value:mode() or value
  return mode_action_desc_for(mode)
end

function M.mode_status_hl(value)
  local mode = type(value) == "table" and value:mode() or value
  return mode_status_hl_for(mode)
end

function M.codux_menu_marker(value)
  if type(value) ~= "string" then
    return false
  end

  local text = value:lower()
  for _, marker in ipairs(markers) do
    if text:find(marker, 1, true) then
      return true
    end
  end

  return false
end

function M.spec_has_owned_lhs(spec, owned)
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
    if M.spec_has_owned_lhs(child, owned) then
      return true
    end
  end

  return false
end

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local controller = {
    get_mode = type(opts.get_mode) == "function" and opts.get_mode or function()
      return "not running"
    end,
    get_mappings = type(opts.get_mappings) == "function" and opts.get_mappings or function()
      return {}
    end,
    token_usage_label = type(opts.token_usage_label) == "function" and opts.token_usage_label or function()
      return ""
    end,
    mode_display_label = opts.mode_display_label,
    valid_terminal_buffer = type(opts.valid_terminal_buffer) == "function" and opts.valid_terminal_buffer or function()
      return false
    end,
    terminal_buffer = type(opts.terminal_buffer) == "function" and opts.terminal_buffer or function()
      return nil
    end,
    is_valid_win = type(opts.is_valid_win) == "function" and opts.is_valid_win or function()
      return false
    end,
    is_loaded_buf = type(opts.is_loaded_buf) == "function" and opts.is_loaded_buf or function()
      return false
    end,
    set_mapping = type(opts.set_mapping) == "function" and opts.set_mapping or noop,
    set_buffer_keymap = type(opts.set_buffer_keymap) == "function" and opts.set_buffer_keymap or noop,
    toggle_plan_mode = type(opts.toggle_plan_mode) == "function" and opts.toggle_plan_mode or noop,
    icon = type(opts.icon) == "string" and opts.icon or codux_icon,
    header_hooked = false,
  }

  return setmetatable(controller, M)
end

function M:mode()
  return self.get_mode()
end

function M:mode_status_label()
  return "codux"
end

function M:mode_status_header_lines()
  local lines = { "codux status " .. mode_display_label(self.mode_display_label, self:mode()) }
  local usage = self.token_usage_label()
  if usage ~= "" then
    table.insert(lines, usage)
  end

  return lines
end

function M:apply_mode_status_hl()
  pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyExecute", { fg = "#3fb950" })
  pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyPlan", { fg = "#a371f7" })
  pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyNotRunning", { fg = "#f85149" })
  pcall(vim.api.nvim_set_hl, 0, "CoduxWhichKeyUsage", { fg = "#8b949e" })
end

function M:mode_status_icon()
  local mode = self:mode()
  if mode == "execute" then
    return { icon = self.icon, color = "green" }
  end
  if mode == "plan" then
    return { icon = self.icon, color = "purple" }
  end

  return { icon = self.icon, color = "red" }
end

function M:clear_cache()
  local ok, which_key_buf = pcall(require, "which-key.buf")
  if ok and type(which_key_buf.clear) == "function" then
    pcall(which_key_buf.clear)
  end
end

function M:active_node()
  local ok, which_key_state = pcall(require, "which-key.state")
  if not ok or type(which_key_state.state) ~= "table" or type(which_key_state.state.node) ~= "table" then
    return nil
  end

  return which_key_state.state.node
end

function M:prefix()
  local ok, which_key_util = pcall(require, "which-key.util")
  if ok and type(which_key_util.norm) == "function" then
    local norm_ok, value = pcall(which_key_util.norm, "<leader>z")
    if norm_ok and type(value) == "string" then
      return value
    end
  end

  return "<leader>z"
end

function M:node_has_menu_child(node)
  if type(node) ~= "table" or type(node.children) ~= "function" then
    return false
  end

  local ok, children = pcall(node.children, node)
  if not ok or type(children) ~= "table" then
    return false
  end

  for _, child in ipairs(children) do
    if M.codux_menu_marker(child.desc) then
      return true
    end
  end

  return false
end

function M:active()
  local node = self:active_node()
  if type(node) ~= "table" then
    return false
  end

  return node.keys == self:prefix() or self:node_has_menu_child(node)
end

function M:view()
  local ok, view = pcall(require, "which-key.view")
  if not ok or type(view) ~= "table" or type(view.view) ~= "table" then
    return nil
  end

  return view
end

function M:valid_window(view)
  if type(view) ~= "table" or type(view.view) ~= "table" then
    return nil, nil
  end

  local win = view.view.win
  local buf = view.view.buf
  if not self.is_valid_win(win) or not self.is_loaded_buf(buf) then
    return nil, nil
  end

  return win, buf
end

function M:title()
  local usage = self.token_usage_label()
  local title = { { " codux " .. mode_display_label(self.mode_display_label, self:mode()) .. " ", self:mode_status_hl() } }
  if usage ~= "" then
    local compact_usage = usage:gsub("^usage | ", "")
    table.insert(title, { "| " .. compact_usage .. " ", "CoduxWhichKeyUsage" })
  end

  return title
end

function M:with_chrome(callback)
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

  win_config.title = self:title()
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

function M:refresh_header()
  local view = self:view()
  local win = self:valid_window(view)
  if win and self:active() and type(view.show) == "function" then
    pcall(view.show)
  end
end

function M:install_header_hook()
  if self.header_hooked then
    return
  end

  local ok, view = pcall(require, "which-key.view")
  if not ok or type(view) ~= "table" or type(view.show) ~= "function" then
    return
  end

  if view._codux_header_hooked == "chrome" then
    self.header_hooked = true
    return
  end

  local original_show = view.show
  view.show = function(...)
    local args = { ... }
    if self:active() then
      return self:with_chrome(function()
        return original_show(unpack(args))
      end)
    end

    return original_show(unpack(args))
  end
  view._codux_header_hooked = "chrome"
  self.header_hooked = true
end

function M:owned_lhs(mappings)
  local owned = {}
  for _, lhs in pairs(mappings or {}) do
    if type(lhs) == "string" and lhs ~= "" then
      owned[lhs] = true
    end
  end
  owned["<leader>z"] = true
  return owned
end

function M:remove_specs(mappings)
  local owned = self:owned_lhs(mappings)

  local ok_wk, which_key = pcall(require, "which-key")
  if ok_wk and type(which_key._queue) == "table" then
    for index = #which_key._queue, 1, -1 do
      local queued = which_key._queue[index]
      if type(queued) == "table" and M.spec_has_owned_lhs(queued.spec, owned) then
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

  self:clear_cache()
end

function M:update_terminal_mode_mapping()
  if not self.valid_terminal_buffer() then
    return
  end

  local mappings = self.get_mappings()
  local lhs = mappings.mode
  if type(lhs) ~= "string" or lhs == "" then
    return
  end

  local action_desc = self:mode_action_desc()
  local bufnr = self.terminal_buffer()
  if action_desc then
    self.set_buffer_keymap(bufnr, { "n", "t" }, lhs, self.toggle_plan_mode, action_desc, {
      nowait = true,
    })
  else
    pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
    pcall(vim.keymap.del, "t", lhs, { buffer = bufnr })
  end
end

function M:normal_entries(mappings)
  local candidates = {
    { lhs = mappings.open, desc = "open codux" },
    { lhs = mappings.review_file, desc = "send file/folder" },
    { lhs = mappings.review_selection, desc = "send selection" },
    { lhs = mappings.diagnostics, desc = "send diagnostics" },
    { lhs = mappings.diff, desc = "send git diff" },
    { lhs = mappings.missions, desc = "mission control" },
  }
  local entries = {}
  for _, entry in ipairs(candidates) do
    if type(entry.lhs) == "string" and entry.lhs ~= "" then
      table.insert(entries, entry)
    end
  end
  local action_desc = self:mode_action_desc()
  if action_desc and type(mappings.mode) == "string" and mappings.mode ~= "" then
    table.insert(entries, { lhs = mappings.mode, desc = action_desc })
  end

  return entries
end

function M:register_group(mappings)
  mappings = type(mappings) == "table" and mappings or {}
  local ok, which_key = pcall(require, "which-key")
  if not ok then
    return
  end

  self:install_header_hook()
  self:remove_specs(mappings)

  local normal_entries = self:normal_entries(mappings)
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
      table.insert(specs, { "<leader>z", group = self:mode_status_label(), icon = self:mode_status_icon(), mode = "n" })
    end
    if has_visual_prefix then
      table.insert(specs, { "<leader>z", group = self:mode_status_label(), mode = "v" })
    end
    for _, entry in ipairs(normal_entries) do
      if type(entry.lhs) == "string" and entry.lhs:match("^<leader>z") then
        table.insert(specs, { entry.lhs, desc = entry.desc, mode = "n" })
      end
    end
    if has_visual_prefix then
      table.insert(specs, { mappings.review_selection, desc = "send selection", mode = "v" })
    end
    pcall(which_key.add, specs)
  elseif type(which_key.register) == "function" then
    if has_normal_prefix then
      local normal_spec = { z = { name = self.icon .. " " .. self:mode_status_label() } }
      for _, entry in ipairs(normal_entries) do
        if type(entry.lhs) == "string" and entry.lhs:match("^<leader>z.") then
          normal_spec.z[entry.lhs:sub(#"<leader>z" + 1)] = entry.desc
        end
      end
      pcall(which_key.register, normal_spec, { prefix = "<leader>", mode = "n" })
    end
    if has_visual_prefix then
      local visual_spec = { z = { name = self:mode_status_label() } }
      if mappings.review_selection:match("^<leader>z.") then
        visual_spec.z[mappings.review_selection:sub(#"<leader>z" + 1)] = "send selection"
      end
      pcall(which_key.register, visual_spec, { prefix = "<leader>", mode = "v" })
    end
  end
end

function M:refresh(mappings)
  mappings = type(mappings) == "table" and mappings or self.get_mappings()
  self:apply_mode_status_hl()
  self:register_group(mappings)
  local action_desc = self:mode_action_desc()
  if action_desc then
    self.set_mapping("n", mappings.mode, self.toggle_plan_mode, action_desc)
  elseif type(mappings.mode) == "string" and mappings.mode ~= "" then
    pcall(vim.keymap.del, "n", mappings.mode)
  end
  self:update_terminal_mode_mapping()
end

return M
