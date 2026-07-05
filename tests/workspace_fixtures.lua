local h = require("tests.helpers")

local M = {}

local runtime_mod = require("codux.workspace_runtime")

function M.runtime_with_tmux(responses, state)
  return runtime_mod.new({
    state = state or {},
    get_config = function()
      return { tmux_cmd = "tmux" }
    end,
    system = function(args)
      local command = table.concat(args, " ")
      local response = responses[command]
      if response == nil then
        return "", 1
      end
      return response[1], response[2]
    end,
  })
end

function M.review_workspace_record(fields)
  local record = {
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    tmux_window = "review",
    status = "inactive",
    codex_status = "idle",
  }
  for key, value in pairs(fields or {}) do
    record[key] = value
  end
  return record
end

function M.workspace_state(workspaces, fields)
  local project = {
    workspaces = workspaces or {},
  }
  for key, value in pairs(fields or {}) do
    project[key] = value
  end
  return {
    projects = {
      ["/repo"] = project,
    },
  }
end

function M.default_workspace_config()
  return {
    codex_cmd = "codex",
    workspace_auto_cmd = "codex-auto",
    danger_full_access_cmd = "codex-danger",
    default_initial_mode = "plan",
    workspaces = {
      tmux_cmd = "tmux",
      nvim_cmd = "nvim",
    },
  }
end

function M.default_workspace_from_state(record, fallback)
  local workspace = vim.deepcopy(fallback)
  if type(record) == "table" then
    for key, value in pairs(record) do
      workspace[key] = value
    end
  end
  return workspace
end

function M.default_state_record(_, workspace)
  return {
    name = workspace.name,
    safe_name = workspace.safe_name,
    project_root = workspace.project_root,
    resolved_instruction = workspace.resolved_instruction,
    target_path = workspace.target_path,
    target_type = workspace.target_type,
    permission_profile = workspace.permission_profile,
    tmux_window = workspace.window_name,
    status = workspace.status,
    codex_status = workspace.codex_status,
    git_branch = workspace.git_branch,
    workspace_kind = workspace.workspace_kind,
    git_common_dir = workspace.git_common_dir,
    worktree_path = workspace.worktree_path,
    worktree_branch = workspace.worktree_branch,
    worktree_base = workspace.worktree_base,
    worktree_base_commit = workspace.worktree_base_commit,
    mission_id = workspace.mission_id,
    mission_name = workspace.mission_name,
    mission_role = workspace.mission_role,
    mission_objective = workspace.mission_objective,
    nvim_server = workspace.nvim_server,
    initial_mode = workspace.initial_mode,
    codex_mode = workspace.codex_mode,
  }
end

function M.project_state(_, state, root)
  state.projects[root] = state.projects[root] or { workspaces = {} }
  return state.projects[root]
end

function M.simple_project_state(state_data, root)
  state_data.projects = state_data.projects or {}
  state_data.projects[root] = state_data.projects[root] or { workspaces = {} }
  state_data.projects[root].workspaces = state_data.projects[root].workspaces or {}
  return state_data.projects[root]
end

function M.with_filereadable(value, callback)
  local old_filereadable = vim.fn.filereadable
  vim.fn.filereadable = function()
    return value
  end
  local ok, err = pcall(callback)
  vim.fn.filereadable = old_filereadable
  if not ok then
    error(err, 0)
  end
end

function M.with_workspace_prepare_env(callback)
  local old_tmux = vim.env.TMUX
  local old_executable = vim.fn.executable
  local old_isdirectory = vim.fn.isdirectory
  local old_filereadable = vim.fn.filereadable
  local old_getcwd = vim.fn.getcwd
  local old_shellescape = vim.fn.shellescape

  vim.env.TMUX = "/tmp/tmux,1,0"
  vim.fn.executable = function()
    return 1
  end
  vim.fn.isdirectory = function(path)
    return path == "/repo" and 1 or 0
  end
  vim.fn.filereadable = function(path)
    return (path == "/repo/file.lua" or path == "/codux-worktrees/review/file.lua") and 1 or 0
  end
  vim.fn.getcwd = function()
    return "/repo"
  end
  vim.fn.shellescape = function(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
  end

  local ok, err = pcall(callback)
  vim.env.TMUX = old_tmux
  vim.fn.executable = old_executable
  vim.fn.isdirectory = old_isdirectory
  vim.fn.filereadable = old_filereadable
  vim.fn.getcwd = old_getcwd
  vim.fn.shellescape = old_shellescape
  if not ok then
    error(err, 0)
  end
end

function M.workspace_prepare_runtime(opts)
  opts = opts or {}
  local custom_system = opts.system
  return runtime_mod.new({
    state = opts.state or {},
    notify = opts.notify,
    get_config = opts.get_config or M.default_workspace_config,
    current_target = opts.current_target or function()
      return { path = "/repo/file.lua", type = "file" }
    end,
    current_buffer_name = opts.current_buffer_name or function()
      return "/repo/file.lua"
    end,
    current_buffer = opts.current_buffer or function()
      return 1
    end,
    alternate_buffer = opts.alternate_buffer or function()
      return 1
    end,
    list_buffers = opts.list_buffers or function()
      return {}
    end,
    is_loaded_buf = opts.is_loaded_buf or function()
      return false
    end,
    git_root_for = opts.git_root_for or function()
      return "/repo"
    end,
    git_branch_for = opts.git_branch_for or function()
      return "main"
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if custom_system then
        local output, code = custom_system(args)
        if code == 0 or output ~= "" or command:find("^tmux") then
          return output, code
        end
      end
      if command == "git -C /repo status --porcelain" then
        return "", 0
      end
      if command == "git -C /repo branch --show-current" then
        return "main\n", 0
      end
      if command == "git -C /repo rev-parse main" then
        return "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 0
      end
      if command == "git -C /repo rev-parse --path-format=absolute --git-common-dir" then
        return "/repo/.git\n", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev" then
        return "", 1
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/review" then
        return "", 1
      end
      if command == "git -C /repo worktree add -b dev/review /codux-worktrees/review main" then
        return "", 0
      end
      if command == "git -C /repo worktree remove --force /codux-worktrees/review" then
        return "", 0
      end
      if command == "git -C /repo branch -D dev/review" then
        return "", 0
      end
      if command == "git -C /codux-worktrees/review merge-base --is-ancestor dev/review main" then
        return "", 1
      end
      return "", 1
    end,
    store = opts.store or {},
  })
end

function M.workspace_store(opts)
  opts = opts or {}
  local state_data = opts.state_data or { projects = {} }
  return {
    state_data = function()
      return state_data
    end,
    store = {
      read_state = function()
        return state_data, nil
      end,
      write_state = opts.write_state or function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = opts.project_state or M.project_state,
      workspace_from_state = opts.workspace_from_state or M.default_workspace_from_state,
      state_record = opts.state_record or M.default_state_record,
      instruction_file_path = opts.instruction_file_path or function()
        return "/repo/.agents/codux/review.md"
      end,
      read_instruction_file = opts.read_instruction_file or function()
        return nil
      end,
      write_instruction_file = opts.write_instruction_file or function()
        return true, nil
      end,
      delete_instruction_file = opts.delete_instruction_file or function()
        return true, nil
      end,
      instruction_file_records = opts.instruction_file_records or function()
        return {}
      end,
      resolve_workspace_resume_session = opts.resolve_workspace_resume_session or function() end,
    },
  }
end

function M.workspace_delete_runtime(store, opts)
  opts = opts or {}
  return runtime_mod.new({
    state = opts.state or {
      workspace_manager_project_root = "/repo",
    },
    notify = opts.notify or function() end,
    render_workspace_manager = opts.render_workspace_manager or function() end,
    close_workspace_manager = opts.close_workspace_manager or function() end,
    system = opts.system,
    store = store,
  })
end

function M.with_tmux(callback)
  return h.with_stubs({
    { target = vim.fn, key = "executable", value = function() return 1 end },
    { target = vim.fn, key = "filereadable", value = function() return 0 end },
  }, callback)
end

return M
