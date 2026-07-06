local prompt_actions_mod = require("codux.prompt_actions")

local M = {}

function M.new(opts)
  opts = type(opts) == "table" and opts or {}

  return prompt_actions_mod.new({
    get_config = opts.get_config,
    notify = opts.notify,
    send_to_codex = opts.send_to_codex,
    exit = opts.exit,
    context = opts.context,
    current_filetype = opts.current_filetype,
    current_buffer = opts.current_buffer,
    buffer_lines = opts.buffer_lines,
    mode = opts.mode,
    getpos = opts.getpos,
    visualmode = opts.visualmode,
  })
end

return M
