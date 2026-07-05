local M = {}

function M.install_workspace_target_autocmds(augroup, deps)
  deps = type(deps) == "table" and deps or {}
  pcall(vim.api.nvim_clear_autocmds, {
    group = augroup,
    event = { "BufEnter", "BufWinEnter", "WinEnter", "DirChanged", "CursorMoved" },
  })
  pcall(vim.api.nvim_create_autocmd, { "BufEnter", "BufWinEnter", "WinEnter", "DirChanged" }, {
    group = augroup,
    callback = function(args)
      deps.schedule_workspace_target_sync(args.event)
    end,
  })
  pcall(vim.api.nvim_create_autocmd, "CursorMoved", {
    group = augroup,
    callback = function(args)
      if deps.is_explorer_filetype(deps.current_filetype()) then
        deps.schedule_workspace_target_sync(args.event)
      end
    end,
  })
end

function M.install_shutdown_autocmd(augroup, stop_token_monitor_timer)
  pcall(vim.api.nvim_clear_autocmds, { group = augroup, event = "VimLeavePre" })
  pcall(vim.api.nvim_create_autocmd, "VimLeavePre", {
    group = augroup,
    callback = function()
      stop_token_monitor_timer()
    end,
  })
end

return M
