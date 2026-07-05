local workspace_git = require("codux.workspace_git")

local M = {}

function M.renamed_worktree_path(old_worktree_path, safe_name)
  return workspace_git.normalize_absolute_path(workspace_git.normalize_absolute_path(old_worktree_path, ".."), safe_name)
end

function M.retarget_path_after_worktree_move(target_path, old_worktree_path, new_worktree_path)
  if type(target_path) ~= "string" or not workspace_git.starts_with_path(target_path, old_worktree_path) then
    return target_path
  end

  local suffix = target_path:sub(#workspace_git.strip_trailing_slashes(old_worktree_path) + 2)
  return workspace_git.normalize_absolute_path(new_worktree_path, suffix)
end

return M
