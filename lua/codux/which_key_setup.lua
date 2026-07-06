local which_key_mod = require("codux.which_key")

local M = {}

function M.new(opts)
  opts = type(opts) == "table" and opts or {}

  return which_key_mod.new({
    get_mode = opts.get_mode,
    get_mappings = opts.get_mappings,
    token_usage_label = opts.token_usage_label,
    mode_display_label = opts.mode_display_label,
    valid_terminal_buffer = opts.valid_terminal_buffer,
    terminal_buffer = opts.terminal_buffer,
    is_valid_win = opts.is_valid_win,
    is_loaded_buf = opts.is_loaded_buf,
    set_mapping = opts.set_mapping,
    set_buffer_keymap = opts.set_buffer_keymap,
    toggle_plan_mode = opts.toggle_plan_mode,
  })
end

return M
