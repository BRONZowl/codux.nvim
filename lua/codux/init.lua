local M = {}

local function tmux_target()
  return vim.g.codux_tmux_window or "CODEX"
end

local function send_to_codex(message)
  vim.fn.system({ "tmux", "send-keys", "-t", tmux_target(), message, "Enter" })
end

function M.open()
  vim.fn.system("codux")
end

function M.send_file_review()
  local file = vim.fn.expand("%:p")
  send_to_codex("Review this file: " .. file)
end

function M.send_file_fix()
  local file = vim.fn.expand("%:p")
  send_to_codex("Find and fix issues in this file: " .. file)
end

function M.send_selection()
  vim.cmd('normal! "zy')
  local selected = vim.fn.getreg("z")
  send_to_codex("Review this selected code:\n\n" .. selected)
end

function M.setup(opts)
  opts = opts or {}
  vim.g.codux_tmux_window = opts.tmux_window or "CODEX"

  vim.keymap.set("n", "<leader>cc", M.open, { desc = "Open Codex Window" })
  vim.keymap.set("n", "<leader>cf", M.send_file_review, { desc = "Send Current File To Codex" })
  vim.keymap.set("n", "<leader>cx", M.send_file_fix, { desc = "Ask Codex To Fix Current File" })
  vim.keymap.set("v", "<leader>cs", M.send_selection, { desc = "Send Selection To Codex" })
end

return M
