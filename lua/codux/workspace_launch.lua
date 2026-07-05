local M = {}

function M.shell_env_assignment(name, value)
  return name .. "=" .. vim.fn.shellescape(tostring(value or ""))
end

function M.lua_string(value)
  return string.format("%q", tostring(value or ""))
end

function M.bootstrap_lua(workspace)
  workspace = type(workspace) == "table" and workspace or {}
  local root = workspace.project_root or "."
  local target_path = workspace.target_path or ""
  local target_type = workspace.target_type or ""
  local profile = workspace.permission_profile or "default"
  local name = workspace.name or workspace.safe_name or ""
  local safe_name = workspace.safe_name or ""
  local branch = workspace.git_branch or ""
  local workspace_kind = workspace.workspace_kind or ""
  local git_common_dir = workspace.git_common_dir or ""
  local worktree_path = workspace.worktree_path or ""
  local worktree_branch = workspace.worktree_branch or ""
  local worktree_base = workspace.worktree_base or ""
  local worktree_base_commit = workspace.worktree_base_commit or ""
  local mission_id = workspace.mission_id or ""
  local mission_name = workspace.mission_name or ""
  local mission_role = workspace.mission_role or ""
  local mission_objective = workspace.mission_objective or ""
  local window_name = workspace.window_name or ""
  local nvim_server = workspace.nvim_server or ""
  local custom_instruction = workspace.custom_instruction or ""
  local resolved_instruction = workspace.resolved_instruction or ""
  local initial_prompt = workspace.initial_prompt or ""
  local initial_mode = workspace.initial_mode or ""
  local open_visible = workspace.open_visible == true
  local codex_session_id = workspace.codex_session_id or ""
  local codex_session_path = workspace.codex_session_path or ""
  local codex_session_captured_at = workspace.codex_session_captured_at or ""
  local codex_status = initial_prompt ~= "" and "working" or "idle"
  local status = initial_prompt ~= "" and "active" or "idle"
  local show_codux = open_visible or initial_prompt ~= ""

  return table.concat({
    "local root=" .. M.lua_string(root),
    "local target=" .. M.lua_string(target_path),
    "local target_type=" .. M.lua_string(target_type),
    "local profile=" .. M.lua_string(profile),
    "local prompt=" .. M.lua_string(initial_prompt),
    "local show_codux=" .. tostring(show_codux),
    "local workspace={name=" .. M.lua_string(name) .. ",safe_name=" .. M.lua_string(safe_name) .. ",project_root=root,target_path=target,target_type=target_type,git_branch=" .. M.lua_string(branch) .. ",workspace_kind=" .. M.lua_string(workspace_kind) .. ",git_common_dir=" .. M.lua_string(git_common_dir) .. ",worktree_path=" .. M.lua_string(worktree_path) .. ",worktree_branch=" .. M.lua_string(worktree_branch) .. ",worktree_base=" .. M.lua_string(worktree_base) .. ",worktree_base_commit=" .. M.lua_string(worktree_base_commit) .. ",mission_id=" .. M.lua_string(mission_id) .. ",mission_name=" .. M.lua_string(mission_name) .. ",mission_role=" .. M.lua_string(mission_role) .. ",mission_objective=" .. M.lua_string(mission_objective) .. ",window_name=" .. M.lua_string(window_name) .. ",nvim_server=" .. M.lua_string(nvim_server) .. ",custom_instruction=" .. M.lua_string(custom_instruction) .. ",resolved_instruction=" .. M.lua_string(resolved_instruction) .. ",initial_mode=" .. M.lua_string(initial_mode) .. ",permission_profile=profile,codex_status=" .. M.lua_string(codex_status) .. ",status=" .. M.lua_string(status) .. ",codex_session_id=" .. M.lua_string(codex_session_id) .. ",codex_session_path=" .. M.lua_string(codex_session_path) .. ",codex_session_captured_at=" .. M.lua_string(codex_session_captured_at) .. ",open_visible=" .. tostring(open_visible) .. "}",
    "vim.defer_fn(function()",
    "pcall(vim.cmd,'cd '..vim.fn.fnameescape(root))",
    "local target_win=vim.api.nvim_get_current_win()",
    "if vim.fn.exists(':Neotree')==2 then",
    "local tree_dir=(target_type=='directory' and target~='' and target) or root",
    "local cmd='Neotree source=filesystem action=show position=left dir='..vim.fn.fnameescape(tree_dir)",
    "if target~='' and target_type~='directory' then cmd=cmd..' reveal_file='..vim.fn.fnameescape(target)..' reveal_force_cwd' end",
    "pcall(vim.cmd,cmd)",
    "end",
    "if target~='' and target_type~='directory' then if vim.api.nvim_win_is_valid(target_win) then pcall(vim.api.nvim_set_current_win,target_win) else pcall(vim.cmd,'edit '..vim.fn.fnameescape(target)) end end",
    "local ok_attach,codux_attach=pcall(require,'codux')",
    "if ok_attach and type(codux_attach.attach_workspace)=='function' then codux_attach.attach_workspace(workspace) end",
    "vim.defer_fn(function()",
    "local ok,codux=pcall(require,'codux')",
    "if ok and type(codux.open_workspace_session)=='function' then codux.open_workspace_session(workspace,prompt,{visible=show_codux}) end",
    "end,300)",
    "end,300)",
  }, " ")
end

function M.nvim_command(runtime, workspace)
  workspace = type(workspace) == "table" and workspace or {}
  local config = runtime.get_config()
  local env = {
    M.shell_env_assignment("CODEX_CMD", runtime.command_util.shell(config.codex_cmd)),
    M.shell_env_assignment("CODEX_WORKSPACE_AUTO_CMD", runtime.command_util.shell(config.workspace_auto_cmd)),
    M.shell_env_assignment("CODEX_DANGER_FULL_ACCESS_CMD", runtime.command_util.shell(config.danger_full_access_cmd)),
  }
  local nvim_target = "."
  if workspace.target_type ~= "directory" and type(workspace.target_path) == "string" and workspace.target_path ~= "" then
    nvim_target = workspace.target_path
  end

  local parts = {
    "cd",
    vim.fn.shellescape(workspace.project_root or "."),
    "&&",
    "env",
    table.concat(env, " "),
    vim.fn.shellescape(runtime:nvim_cmd()),
    "--listen",
    vim.fn.shellescape(workspace.nvim_server or runtime:workspace_server_path(workspace.project_root, workspace.safe_name)),
    vim.fn.shellescape(nvim_target),
    "-c",
    vim.fn.shellescape("lua " .. M.bootstrap_lua(workspace)),
  }

  return table.concat(parts, " ")
end

return M
