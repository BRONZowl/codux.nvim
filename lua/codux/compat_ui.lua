local ui = require("codux.ui")

local M = {}

function M.install_ui(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local ui_mod = type(deps.ui) == "table" and deps.ui or ui
  local notify = type(deps.notify) == "function" and deps.notify or function() end

  function api.set_buffer_keymap(bufnr, modes, lhs, rhs, desc, opts)
    return ui_mod.set_keymap(bufnr, modes, lhs, rhs, desc, opts)
  end

  function api.bind_close_keys(bufnr, close_fn, desc, modes, opts)
    return ui_mod.bind_close_keys(bufnr, close_fn, desc, modes, opts)
  end

  function api.single_line_prompt(opts, callback)
    return ui_mod.single_line_prompt(opts, callback, {
      notify = notify,
      set_buffer_keymap = api.set_buffer_keymap,
      bind_close_keys = api.bind_close_keys,
    })
  end

  return api
end

return M
