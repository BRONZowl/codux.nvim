local terminal_mod = require("codux.terminal")
local terminal_keymaps = require("codux.terminal_keymaps")
local output_mouse = require("codux.mission_output_mouse")
local ui = require("codux.ui")
local util = require("codux.util")

local M = {}

local noop = util.noop

local function output_terminal_state(parent)
  local state = parent.state.mission_dashboard.output_terminal_state
  if type(state) ~= "table" then
    state = {
      mode = "not running",
      agent_working = false,
      last_prompt_line = nil,
      terminal_prompt_input = "",
      terminal_prompt_tracking_valid = true,
      terminal_mode_sync_pending = false,
    }
    parent.state.mission_dashboard.output_terminal_state = state
  end

  state.buf = parent.state.mission_dashboard.output_buf
  state.win = parent.state.mission_dashboard.output_win
  state.job_id = parent.state.mission_dashboard.output_job
  return state
end

local function adapter_ui(parent)
  local base = type(parent.ui) == "table" and parent.ui or ui
  return setmetatable({
    set_keymap = function(bufnr, modes, lhs, rhs, desc, opts)
      return parent.set_buffer_keymap(bufnr, modes, lhs, rhs, desc, opts)
    end,
    printable_prompt_keys = type(base.printable_prompt_keys) == "function" and base.printable_prompt_keys
      or ui.printable_prompt_keys,
  }, {
    __index = base,
  })
end

function M.output_terminal_controller(self)
  local controller = self.state.mission_dashboard.output_terminal_controller
  if type(controller) == "table" then
    controller.state = output_terminal_state(self)
    return controller
  end

  local parent = self
  controller = terminal_mod.new({
    state = output_terminal_state(parent),
    notify = parent.notify,
    ui = adapter_ui(parent),
    sync_workspace_activity = noop,
    sync_workspace_mode = noop,
    refresh_which_key = noop,
    refresh_which_key_header = noop,
    update_terminal_mode_mapping = noop,
    start_token_monitor_timer = noop,
    stop_token_monitor_timer = noop,
  })

  function controller:sync_output_terminal_state()
    self.state = output_terminal_state(parent)
    return self.state
  end

  function controller:valid_buf()
    local state = self:sync_output_terminal_state()
    return parent.is_loaded_buf(state.buf)
  end

  function controller:valid_win()
    local state = self:sync_output_terminal_state()
    return parent.is_valid_win(state.win)
  end

  function controller:terminal_running()
    self:sync_output_terminal_state()
    return parent:output_preview_running()
  end

  function controller:focus_terminal_prompt(input)
    local state = self:sync_output_terminal_state()
    if not self:valid_win() then
      return false
    end
    if not parent.set_current_win(state.win) then
      return false
    end

    local ok, line_count = pcall(vim.api.nvim_buf_line_count, state.buf)
    if ok and type(line_count) == "number" then
      pcall(vim.api.nvim_win_set_cursor, state.win, { line_count, 0 })
    end
    pcall(vim.cmd, "startinsert")

    if type(input) == "string" and input ~= "" and self:terminal_running() then
      self:invalidate_terminal_prompt_tracking()
      pcall(vim.fn.chansend, state.job_id, input)
    end
    return true
  end

  function controller:terminal_screen_height()
    local state = self:sync_output_terminal_state()
    local height = parent.get_window_height(state.win)
    if type(height) == "number" and height > 0 then
      return height
    end
    local lines = tonumber(vim.o.lines) or 24
    local cmdheight = tonumber(vim.o.cmdheight) or 0
    return math.max(1, lines - cmdheight)
  end

  function controller:set_agent_working(working)
    self.state.agent_working = working == true
  end

  function controller:update_working_indicator()
    return true
  end

  function controller:close_working_indicator()
    return true
  end

  parent.state.mission_dashboard.output_terminal_controller = controller
  return controller
end

function M.clear_output_terminal_state(self)
  local controller = self.state.mission_dashboard.output_terminal_controller
  if type(controller) == "table" then
    controller:reset_terminal_prompt_input()
    controller.state.job_id = nil
    controller.state.last_prompt_line = nil
    controller.state.agent_working = false
    controller:set_mode("not running")
  end
end

function M.bind_output_terminal_commands(self, bufnr)
  local controller = self:output_terminal_controller()
  terminal_keymaps.bind_prompt_controls(controller, bufnr, {
    close = function()
      return self:close_dashboard()
    end,
    close_desc = "Close Codux Missions",
    bind_q = false,
    omit_normal_prompt_keys = {
      q = true,
    },
  })
  self.set_buffer_keymap(bufnr, { "n", "t" }, "<C-o>", function()
    if self.state.mission_dashboard.output_control then
      return self:exit_output_control()
    end
    return self:focus_mission_list()
  end, "Return to Codux Missions", {
    nowait = true,
  })

  for key, button in pairs(output_mouse.scroll_buttons) do
    self.set_buffer_keymap(bufnr, { "n", "t" }, key, function()
      return self:send_output_terminal_mouse(button)
    end, "Scroll Codux Output", {
      nowait = true,
    })
  end
end

function M.sync_output_terminal_state(self)
  local controller = self:output_terminal_controller()
  controller:sync_output_terminal_state()
  return true
end

function M.attach_output_terminal_activity(self)
  local controller = self:output_terminal_controller()
  local state = controller:sync_output_terminal_state()
  if not self.is_loaded_buf(state.buf) then
    return false
  end
  controller:attach_terminal_activity(state.buf)
  return true
end

function M.output_terminal_mouse_sequence(self, button)
  return output_mouse.sequence(self, button)
end

function M.send_output_terminal_mouse(self, button)
  return output_mouse.send(self, self:output_terminal_controller(), button)
end

return M
