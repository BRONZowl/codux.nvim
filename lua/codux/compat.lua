local core = require("codux.compat_core")
local prompt = require("codux.compat_prompt")
local terminal = require("codux.compat_terminal")
local ui = require("codux.compat_ui")
local workspace = require("codux.compat_workspace")

local M = {}

M.install = core.install
M.install_ui = ui.install_ui
M.install_terminal = terminal.install_terminal
M.install_prompt_open = prompt.install_prompt_open
M.install_workspace_static = workspace.install_workspace_static
M.install_workspace_runtime = workspace.install_workspace_runtime
M.install_workspace_manager = workspace.install_workspace_manager
M.install_workspace_create = workspace.install_workspace_create

return M
