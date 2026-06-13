local M = {}

local defaults = {
  tmux_window = "CODEX",
  mappings = {
    open = "<leader>zc",
    review_file = "<leader>zf",
    fix_file = "<leader>zx",
    review_selection = "<leader>zs",
  },
}

local config = vim.deepcopy(defaults)

local function tmux_target()
  return vim.g.codux_tmux_window or config.tmux_window
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "codux.nvim" })
end

local function send_to_codex(message)
  vim.fn.system({ "tmux", "send-keys", "-t", tmux_target(), message, "Enter" })
end

function M.open()
  vim.fn.system("codux")
end

local function neo_tree_target()
  if vim.bo.filetype ~= "neo-tree" then
    return nil
  end

  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then
    return nil
  end

  local state_ok, state = pcall(manager.get_state_for_window)
  if not state_ok or not state or not state.tree then
    return nil
  end

  local node_ok, node = pcall(state.tree.get_node, state.tree)
  if not node_ok or not node then
    return nil
  end

  local path = node.path
  if type(node.get_id) == "function" then
    local id_ok, id = pcall(node.get_id, node)
    if id_ok and type(id) == "string" and id ~= "" then
      path = id
    end
  end

  if type(path) ~= "string" or path == "" then
    return nil
  end

  return {
    path = path,
    type = node.type == "directory" and "directory" or "file",
  }
end

local function current_buffer_target()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil
  end

  return {
    path = path,
    type = vim.fn.isdirectory(path) == 1 and "directory" or "file",
  }
end

local function current_target()
  return neo_tree_target() or current_buffer_target()
end

local function target_label(target)
  if target.type == "directory" then
    return "directory"
  end

  return "file"
end

function M.send_file_review()
  local target = current_target()
  if not target then
    notify("No file or Neo-tree node selected for review", vim.log.levels.WARN)
    return
  end

  send_to_codex("Review this " .. target_label(target) .. ": " .. target.path)
end

function M.send_file_fix()
  local target = current_target()
  if not target then
    notify("No file or Neo-tree node selected to fix", vim.log.levels.WARN)
    return
  end

  send_to_codex("Find and fix issues in this " .. target_label(target) .. ": " .. target.path)
end

function M.send_selection()
  vim.cmd('normal! "zy')
  local selected = vim.fn.getreg("z")
  send_to_codex("Review this selected code:\n\n" .. selected)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  vim.g.codux_tmux_window = config.tmux_window

  vim.keymap.set("n", config.mappings.open, M.open, { desc = "Open Codex Window" })
  vim.keymap.set("n", config.mappings.review_file, M.send_file_review, { desc = "Send File Or Neo-tree Node To Codex" })
  vim.keymap.set("n", config.mappings.fix_file, M.send_file_fix, { desc = "Ask Codex To Fix File Or Neo-tree Node" })
  vim.keymap.set("v", config.mappings.review_selection, M.send_selection, { desc = "Send Selection To Codex" })
end

return M
