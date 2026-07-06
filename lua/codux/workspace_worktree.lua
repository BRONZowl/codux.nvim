local text_util = require("codux.text")
local workspace_git = require("codux.workspace_git")

local M = {}

local function trim(value)
  return text_util.trim(value)
end

function M.git_output(runtime, root, ...)
  local args = { "git", "-C", root }
  for _, arg in ipairs({ ... }) do
    table.insert(args, arg)
  end
  local output, code = runtime.system(args)
  if code ~= 0 then
    return nil, code
  end
  return trim(output), code
end

function M.git_common_dir(runtime, root)
  local output = runtime:git_output(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
  if output and output ~= "" then
    return workspace_git.strip_trailing_slashes(output)
  end

  output = runtime:git_output(root, "rev-parse", "--git-common-dir")
  if output and output ~= "" then
    return workspace_git.strip_trailing_slashes(workspace_git.normalize_absolute_path(root, output))
  end

  return nil
end

function M.git_current_ref(runtime, root)
  local branch = runtime:git_output(root, "branch", "--show-current")
  if branch and branch ~= "" then
    return branch
  end

  local head = runtime:git_output(root, "rev-parse", "--short", "HEAD")
  if head and head ~= "" then
    return head
  end

  return "HEAD"
end

function M.git_rev_parse(runtime, root, ref)
  local output = runtime:git_output(root, "rev-parse", tostring(ref or "HEAD"))
  if output and output ~= "" then
    return output
  end
  return nil
end

function M.git_checkout_clean(runtime, root)
  local output, code = runtime.system({ "git", "-C", root, "status", "--porcelain" })
  if code ~= 0 then
    return false, "not inside a Git repository"
  end
  if trim(output) ~= "" then
    return false, "current branch must be clean before creating a Codux workspace"
  end
  return true, nil
end

function M.git_branch_exists(runtime, root, branch)
  local _, code = runtime.system({ "git", "-C", root, "show-ref", "--verify", "--quiet", "refs/heads/" .. tostring(branch or "") })
  return code == 0
end

function M.resolve_worktree_branch(runtime, root, safe_name)
  local prefix = runtime:worktree_config().branch_prefix
  local prefix_namespace = prefix:match("^(.-)/+$")
  if not prefix_namespace or prefix_namespace == "" then
    local branch = prefix .. tostring(safe_name or "")
    if runtime:git_branch_exists(root, branch) then
      return nil, "branch already exists: " .. branch
    end
    return branch, nil
  end

  for index = 0, 99 do
    local namespace = index == 0 and prefix_namespace or (prefix_namespace .. tostring(index))
    if not runtime:git_branch_exists(root, namespace) then
      local branch = namespace .. "/" .. tostring(safe_name or "")
      if runtime:git_branch_exists(root, branch) then
        return nil, "branch already exists: " .. branch
      end
      return branch, nil
    end
  end

  return nil, "no available branch namespace for " .. prefix_namespace .. "/"
end

function M.worktree_path(runtime, base_root, safe_name)
  local config = runtime:worktree_config()
  local directory = config.directory
  if directory:sub(1, 1) ~= "/" then
    directory = workspace_git.normalize_absolute_path(base_root, directory)
  end
  return workspace_git.normalize_absolute_path(directory, safe_name)
end

function M.worktree_branch(runtime, safe_name)
  return runtime:worktree_config().branch_prefix .. tostring(safe_name or "")
end

function M.renamed_worktree_branch(runtime, existing, safe_name)
  existing = type(existing) == "table" and existing or {}
  local branch = existing.worktree_branch
  if type(branch) == "string" then
    local namespace = branch:match("^(.*)/[^/]+$")
    if namespace and namespace ~= "" then
      return namespace .. "/" .. tostring(safe_name or "")
    end
  end
  return runtime:worktree_branch(safe_name)
end

function M.target_in_worktree(_, path, target_type, base_root, worktree_root)
  if type(path) ~= "string" or path == "" then
    return worktree_root, "directory"
  end

  local normalized_base = workspace_git.strip_trailing_slashes(base_root)
  local normalized_path = workspace_git.strip_trailing_slashes(path)
  if workspace_git.starts_with_path(normalized_path, normalized_base) then
    local suffix = normalized_path:sub(#normalized_base + 1)
    if suffix:sub(1, 1) == "/" then
      suffix = suffix:sub(2)
    end
    if suffix == "" then
      return worktree_root, "directory"
    end
    return workspace_git.normalize_absolute_path(worktree_root, suffix), target_type == "directory" and "directory" or "file"
  end

  return worktree_root, "directory"
end

function M.create_git_worktree(runtime, base_root, worktree_path, branch, base_ref)
  local output, code = runtime.system({ "git", "-C", base_root, "worktree", "add", "-b", branch, worktree_path, base_ref })
  if code ~= 0 then
    local detail = trim(output)
    local message = "Failed to create Git worktree " .. tostring(worktree_path)
    if detail ~= "" then
      message = message .. ": " .. detail
    end
    return false, message
  end
  return true, nil
end

function M.remove_git_worktree(runtime, base_root, worktree_path)
  local output, code = runtime.system({ "git", "-C", base_root, "worktree", "remove", "--force", worktree_path })
  if code == 0 then
    return true, nil
  end
  local message = "Failed to remove Git worktree " .. tostring(worktree_path)
  local detail = trim(output)
  if detail:find("is not a working tree", 1, true) then
    return true, nil
  end
  if detail ~= "" then
    message = message .. ": " .. detail
  end
  return false, message
end

function M.remove_git_worktree_in_common_dir(runtime, git_common_dir, worktree_path)
  local output, code = runtime.system({ "git", "--git-dir=" .. tostring(git_common_dir or ""), "worktree", "remove", "--force", worktree_path })
  if code == 0 then
    return true, nil
  end
  local message = "Failed to remove Git worktree " .. tostring(worktree_path)
  local detail = trim(output)
  if detail:find("is not a working tree", 1, true) then
    return true, nil
  end
  if detail ~= "" then
    message = message .. ": " .. detail
  end
  return false, message
end

function M.delete_git_branch(runtime, base_root, branch)
  local _, code = runtime.system({ "git", "-C", base_root, "branch", "-D", branch })
  return code == 0
end

function M.delete_git_branch_in_common_dir(runtime, git_common_dir, branch)
  local output, code = runtime.system({ "git", "--git-dir=" .. tostring(git_common_dir or ""), "branch", "-D", branch })
  if code == 0 then
    return true, nil
  end
  local message = "Failed to delete Git branch " .. tostring(branch)
  local detail = trim(output)
  if detail ~= "" then
    message = message .. ": " .. detail
  end
  return false, message
end

function M.move_git_worktree(runtime, base_root, old_path, new_path)
  local _, code = runtime.system({ "git", "-C", base_root, "worktree", "move", old_path, new_path })
  return code == 0
end

function M.rename_git_branch(runtime, base_root, old_branch, new_branch)
  local _, code = runtime.system({ "git", "-C", base_root, "branch", "-m", old_branch, new_branch })
  return code == 0
end

function M.workspace_branch_merged(runtime, entry)
  entry = type(entry) == "table" and entry or {}
  if entry.workspace_kind ~= "worktree" then
    return false
  end
  local branch = entry.worktree_branch
  local base = entry.worktree_base
  local base_commit = entry.worktree_base_commit
  local root = entry.worktree_path or entry.project_root
  if
    type(branch) ~= "string"
    or branch == ""
    or type(base) ~= "string"
    or base == ""
    or type(base_commit) ~= "string"
    or base_commit == ""
    or type(root) ~= "string"
  then
    return false
  end

  local count_output, count_code = runtime.system({ "git", "-C", root, "rev-list", "--count", base_commit .. ".." .. branch })
  if count_code ~= 0 or tonumber(trim(count_output)) == nil or tonumber(trim(count_output)) <= 0 then
    return false
  end

  local _, code = runtime.system({ "git", "-C", root, "merge-base", "--is-ancestor", branch, base })
  return code == 0
end

function M.workspace_branch_state(runtime, entry)
  entry = type(entry) == "table" and entry or {}
  local state = {
    worktree = entry.workspace_kind == "worktree",
    branch = entry.worktree_branch,
    base = entry.worktree_base,
    ahead_count = 0,
    merged = false,
  }
  if not state.worktree then
    return state
  end

  local branch = entry.worktree_branch
  local base = entry.worktree_base
  local base_commit = entry.worktree_base_commit
  local root = entry.worktree_path or entry.project_root
  if
    type(branch) ~= "string"
    or branch == ""
    or type(base) ~= "string"
    or base == ""
    or type(base_commit) ~= "string"
    or base_commit == ""
    or type(root) ~= "string"
    or root == ""
  then
    state.error = "missing base"
    return state
  end

  local count_output, count_code = runtime.system({ "git", "-C", root, "rev-list", "--count", base_commit .. ".." .. branch })
  local ahead = tonumber(trim(count_output))
  if count_code ~= 0 or ahead == nil then
    state.error = "ahead unknown"
    return state
  end

  state.ahead_count = ahead
  if ahead <= 0 then
    return state
  end

  local _, code = runtime.system({ "git", "-C", root, "merge-base", "--is-ancestor", branch, base })
  state.merged = code == 0
  return state
end

function M.backfill_workspace_base_commit(runtime, entry)
  entry = type(entry) == "table" and entry or {}
  if entry.workspace_kind ~= "worktree" or (type(entry.worktree_base_commit) == "string" and entry.worktree_base_commit ~= "") then
    return false
  end

  local root = entry.worktree_path or entry.project_root
  local branch = entry.worktree_branch
  local base = entry.worktree_base
  if type(root) ~= "string" or root == "" or type(branch) ~= "string" or branch == "" or type(base) ~= "string" or base == "" then
    return false
  end

  local commit = runtime:git_output(root, "merge-base", branch, base)
  if not commit or commit == "" then
    return false
  end

  local state_data, state_error = runtime:read_state()
  if state_error then
    return false
  end
  local project = type(state_data.projects) == "table" and state_data.projects[entry.project_root] or nil
  local workspaces = type(project) == "table" and project.workspaces or nil
  local record = type(workspaces) == "table" and workspaces[entry.safe_name] or nil
  if type(record) ~= "table" then
    return false
  end

  record.worktree_base_commit = commit
  project.updated_at = runtime:timestamp()
  local write_ok = runtime:write_state(state_data)
  if write_ok then
    entry.worktree_base_commit = commit
  end
  return write_ok
end

function M.prompt_merged_workspaces(runtime, root)
  local entries, error_message = runtime:entries_for_project(root)
  if error_message then
    return false
  end

  runtime.state.merged_workspace_cleanup_declined = type(runtime.state.merged_workspace_cleanup_declined) == "table"
      and runtime.state.merged_workspace_cleanup_declined
    or {}

  for _, entry in ipairs(entries) do
    local key = tostring(entry.project_root or "") .. "\0" .. tostring(entry.safe_name or "")
    if entry.workspace_kind == "worktree" and (type(entry.worktree_base_commit) ~= "string" or entry.worktree_base_commit == "") then
      runtime:backfill_workspace_base_commit(entry)
    elseif not runtime.state.merged_workspace_cleanup_declined[key] and runtime:workspace_branch_merged(entry) then
      local choice = vim.fn.confirm(
        "Codux workspace " .. tostring(entry.name or entry.safe_name) .. " has been merged. Delete workspace/worktree?",
        "&Yes\n&No",
        2
      )
      if choice == 1 then
        return runtime:delete_saved_workspace(entry)
      end
      runtime.state.merged_workspace_cleanup_declined[key] = true
    end
  end

  return true
end

function M.cleanup_created_worktree(runtime, base_root, worktree_path, branch)
  local errors = {}
  if type(worktree_path) == "string" and worktree_path ~= "" then
    local ok, err = runtime:remove_git_worktree(base_root, worktree_path)
    if not ok then
      table.insert(errors, err or ("failed to remove Git worktree " .. tostring(worktree_path)))
    end
  end
  if type(branch) == "string" and branch ~= "" then
    if not runtime:delete_git_branch(base_root, branch) then
      table.insert(errors, "failed to delete Git branch " .. tostring(branch))
    end
  end
  if #errors > 0 then
    return false, table.concat(errors, "; ")
  end
  return true, nil
end

return M
