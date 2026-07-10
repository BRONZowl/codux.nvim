local ui = require("codux.ui")

local M = {}

function M.bind_prompt_controls(controller, bufnr, opts)
  opts = type(opts) == "table" and opts or {}
  local close = type(opts.close) == "function" and opts.close or nil
  local close_desc = opts.close_desc or "Hide Codux Popup"
  local bind_q = opts.bind_q ~= false
  local omit_normal_prompt_keys = type(opts.omit_normal_prompt_keys) == "table" and opts.omit_normal_prompt_keys or {}
  local set_keymap = type(controller.ui) == "table" and controller.ui.set_keymap or ui.set_keymap
  local printable_prompt_keys = type(controller.ui) == "table" and controller.ui.printable_prompt_keys
      or ui.printable_prompt_keys

  if close then
    set_keymap(bufnr, { "n", "t" }, "<C-q>", close, close_desc)
  end
  set_keymap(bufnr, "t", "<CR>", function()
    return controller:submit_terminal_prompt()
  end, "Submit Codux Prompt", {
    nowait = true,
  })
  set_keymap(bufnr, { "n", "t" }, "<C-c>", function()
    return controller:interrupt_terminal_prompt()
  end, "Interrupt Agent", {
    nowait = true,
  })
  controller.update_terminal_mode_mapping()
  for _, key in ipairs(printable_prompt_keys()) do
    set_keymap(bufnr, "t", key[1], controller:terminal_input_key(key[2]), "Type in Codux Prompt", {
      nowait = true,
    })
  end
  set_keymap(
    bufnr,
    "t",
    "<BS>",
    controller:terminal_input_key("\b", { delete_previous = true }),
    "Delete Codux Prompt Character",
    {
      nowait = true,
    }
  )
  set_keymap(
    bufnr,
    "t",
    "<C-h>",
    controller:terminal_input_key("\b", { delete_previous = true }),
    "Delete Codux Prompt Character",
    {
      nowait = true,
    }
  )
  set_keymap(bufnr, { "n", "t" }, "<S-Tab>", function()
    return controller:send_shift_tab_mode_toggle()
  end, "Switch Agent Mode", {
    nowait = true,
  })
  set_keymap(bufnr, "n", "<CR>", function()
    return controller:focus_terminal_prompt()
  end, "Return to Codux Prompt")
  for _, key in ipairs(printable_prompt_keys()) do
    local lhs = key[1]
    local input = key[2]
    if omit_normal_prompt_keys[lhs] ~= true then
      set_keymap(bufnr, "n", lhs, controller:terminal_prompt_key(input), "Type in Codux Prompt")
    end
  end
  if close and bind_q then
    set_keymap(bufnr, "n", "q", close, close_desc)
  end
end

return M
