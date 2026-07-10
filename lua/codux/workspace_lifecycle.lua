local path_util = require("codux.path_util")

local M = {}

function M.renamed_worktree_path(old_worktree_path, safe_name)
  return path_util.normalize_absolute_path(path_util.normalize_absolute_path(old_worktree_path, ".."), safe_name)
end

function M.retarget_path_after_worktree_move(target_path, old_worktree_path, new_worktree_path)
  if type(target_path) ~= "string" or not path_util.starts_with_path(target_path, old_worktree_path) then
    return target_path
  end

  local suffix = target_path:sub(#path_util.strip_trailing_slashes(old_worktree_path) + 2)
  return path_util.normalize_absolute_path(new_worktree_path, suffix)
end

return M
