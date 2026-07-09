local workspace_manager_mod = require("codux.workspace_manager")

local M = {}

function M.new(opts)
  opts = type(opts) == "table" and opts or {}

  return workspace_manager_mod.new({
    state = opts.state,
    notify = opts.notify,
    trim = opts.trim,
    ui = opts.ui,
    workspace_ui = opts.workspace_ui,
    is_valid_win = opts.is_valid_win,
    is_loaded_buf = opts.is_loaded_buf,
    window_buffer = opts.window_buffer,
    buffer_filetype = opts.buffer_filetype,
    workspace_manager_max_height = opts.workspace_manager_max_height,
    workspace_entries_for_project = opts.workspace_entries_for_project,
    project_root = opts.project_root,
    workspaces_enabled = opts.workspaces_enabled,
    restore_workspaces = opts.restore_workspaces,
    prompt_merged_workspaces = opts.prompt_merged_workspaces,
    open_saved_workspace = opts.open_saved_workspace,
    rename_saved_workspace = opts.rename_saved_workspace,
    edit_saved_workspace_instruction = opts.edit_saved_workspace_instruction,
    delete_saved_workspace = opts.delete_saved_workspace,
    close_saved_workspace_window = opts.close_saved_workspace_window,
    select_provider_profile = opts.select_provider_profile,
    switch_workspace_profile = opts.switch_workspace_profile,
    close_all_saved_workspace_windows = opts.close_all_saved_workspace_windows,
    doctor = opts.doctor,
    single_line_prompt = opts.single_line_prompt,
    set_buffer_keymap = opts.set_buffer_keymap,
    bind_close_keys = opts.bind_close_keys,
    namespace = opts.namespace,
  })
end

return M
