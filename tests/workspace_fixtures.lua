local h = require("tests.helpers")

local M = {}

local runtime_mod = require("codux.workspace_runtime")

local function copy_fields(fields)
  local copy = {}
  for key, value in pairs(fields or {}) do
    copy[key] = value
  end
  return copy
end

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

function M.project_owned_worktree_record(fields)
  local values = {
    project_root = "/repo",
    workspace_kind = "worktree",
    git_common_dir = "/repo/.git",
    worktree_path = "/codux-worktrees/review",
    worktree_branch = "dev/review",
    worktree_base = "main",
  }
  for key, value in pairs(fields or {}) do
    values[key] = value
  end
  return M.review_workspace_record(values)
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
    mission_focus_packet = workspace.mission_focus_packet,
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
    return (path == "/repo/file.lua" or path == "/codux-worktrees/review/file.lua" or path:match("^/codux%-worktrees/repo/.+/file%.lua$"))
        and 1
      or 0
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

function M.command_text(commands)
  return table.concat(commands or {}, "\n")
end

function M.prepare_harness(opts)
  opts = opts or {}
  local commands = opts.commands or {}
  local store = opts.store_instance or M.workspace_store(opts.store)
  local harness = {
    commands = commands,
    store = store,
    launch_scripts = {},
    deleted_launch_scripts = {},
  }
  function harness.command_text()
    return M.command_text(commands)
  end

  local runtime_opts = copy_fields(opts.runtime)
  runtime_opts.store = runtime_opts.store or store.store
  runtime_opts.system = function(args)
    local command = table.concat(args, " ")
    table.insert(commands, command)
    if opts.system then
      local output, code = opts.system(args, command, harness)
      if output ~= nil or code ~= nil then
        return output or "", code or 0
      end
    end
    return "", 1
  end
  harness.runtime = M.workspace_prepare_runtime(runtime_opts)
  harness.runtime.write_launch_script = opts.write_launch_script or function(runtime, workspace)
    local path = "/tmp/codux/" .. tostring(workspace.safe_name or workspace.window_name or "workspace") .. ".lua"
    harness.launch_scripts[path] = runtime:bootstrap_lua(workspace)
    return path, nil
  end
  harness.runtime.delete_launch_script = opts.delete_launch_script or function(_, path)
    if type(path) == "string" and path ~= "" then
      harness.deleted_launch_scripts[path] = true
    end
    return true
  end
  return harness
end

function M.mission_builder_prepare_opts(overrides)
  local opts = {
    resolved_instruction = "builder instructions",
    initial_prompt = "start building",
    permission_profile = "auto",
    mission_id = "mission:mission",
    mission_name = "Mission",
    mission_role = "Builder",
    launch_verify_attempts = 1,
  }
  for key, value in pairs(overrides or {}) do
    opts[key] = value
  end
  return opts
end

function M.mission_builder_prepare_harness(opts)
  opts = type(opts) == "table" and opts or {}
  local flags = {
    created = false,
    killed = false,
    removed_worktree = false,
    deleted_branch = false,
  }
  local remote_status = opts.remote_status
  if remote_status == nil then
    remote_status = "not_running"
  end
  local harness = M.prepare_harness({
    store = opts.store,
    store_instance = opts.store_instance,
    runtime = opts.runtime,
    system = function(_, command, active_harness)
      if type(opts.system) == "function" then
        local output, code = opts.system(command, flags, active_harness)
        if output ~= nil or code ~= nil then
          return output or "", code or 0
        end
      end
      if command == "tmux display-message -p #S" then
        return "session\n", 0
      end
      if command == "git -C /repo show-ref --verify --quiet refs/heads/dev/mission-builder" then
        return "", 1
      end
      if command == "git -C /repo worktree add -b dev/mission-builder /codux-worktrees/mission-builder main" then
        return "", 0
      end
      if command == "tmux list-windows -t session -F #{window_id}\t#{window_name}" then
        if flags.created then
          return "@1\tmission-builder\n", 0
        end
        return "", 0
      end
      if command:find("tmux new%-window", 1, false) == 1 then
        flags.created = true
        return "", 0
      end
      if command == "tmux list-panes -t @1 -F #{pane_current_command}" then
        return "nvim\n", 0
      end
      if remote_status ~= false and command:find("remote_workspace_status", 1, true) then
        return remote_status .. "\n", 0
      end
      if command == "tmux kill-window -t @1" then
        flags.killed = true
        return "", 0
      end
      if command == "git -C /repo worktree remove --force /codux-worktrees/mission-builder" then
        flags.removed_worktree = true
        return "", 0
      end
      if command == "git -C /repo branch -D dev/mission-builder" then
        flags.deleted_branch = true
        return "", 0
      end
      return "", 1
    end,
  })
  return harness, flags
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

function M.review_debug_workspace_state(opts)
  opts = opts or {}
  local review = M.review_workspace_record({
    status = "idle",
    codex_status = "idle",
    codex_mode = "plan",
  })
  local debug = M.review_workspace_record({
    name = "debug",
    safe_name = "debug",
    tmux_window = "debug",
    status = "active",
    codex_status = "working",
    codex_mode = "execute",
  })
  for key, value in pairs(opts.review or {}) do
    review[key] = value
  end
  for key, value in pairs(opts.debug or {}) do
    debug[key] = value
  end
  return M.workspace_state({
    review = review,
    debug = debug,
  }, opts.project)
end

function M.worktree_delete_state(fields)
  local record = {
    project_root = "/repo",
    workspace_kind = "worktree",
    git_common_dir = "/repo/.git",
    worktree_path = "/codux-worktrees/review",
    worktree_branch = "dev/review",
    worktree_base = "main",
  }
  for key, value in pairs(fields or {}) do
    record[key] = value
  end
  return M.workspace_state({
    review = M.review_workspace_record(record),
  })
end

function M.with_tmux_env(value, callback)
  local old_tmux = vim.env.TMUX
  vim.env.TMUX = value
  local ok, result = pcall(callback)
  vim.env.TMUX = old_tmux
  if not ok then
    error(result, 0)
  end
  return result
end

function M.lifecycle_runtime(opts)
  opts = opts or {}
  local state_data = opts.state_data or M.review_debug_workspace_state()
  local messages = opts.messages or {}
  local runtime = runtime_mod.new({
    state = opts.state or {
      workspace_manager_project_root = "/repo",
    },
    notify = opts.notify or function(message)
      table.insert(messages, message)
    end,
    get_config = opts.get_config or function()
      return { tmux_cmd = "tmux" }
    end,
    system = opts.system,
    close_workspace_manager = opts.close_workspace_manager,
    store = opts.store or {
      read_state = function()
        return state_data, nil
      end,
      write_state = function(_, next_state)
        state_data = next_state
        return true, nil
      end,
      timestamp = function()
        return "2026-06-30T00:00:00Z"
      end,
      project_state = opts.project_state,
      instruction_file_path = opts.instruction_file_path,
    },
  })
  return {
    runtime = runtime,
    state_data = function()
      return state_data
    end,
    messages = messages,
  }
end

function M.with_tmux(callback)
  return h.with_stubs({
    { target = vim.fn, key = "executable", value = function() return 1 end },
    { target = vim.fn, key = "filereadable", value = function() return 0 end },
  }, callback)
end

return M
