local providers = require("codux.providers")

local M = {}

local function fnameescape(value)
  if type(vim.fn.fnameescape) == "function" then
    return vim.fn.fnameescape(value)
  end
  return tostring(value or ""):gsub("([ \\])", "\\%1")
end

local function set_private_file_mode(path)
  if type(path) == "string" and path ~= "" and type(vim.fn.setfperm) == "function" then
    pcall(vim.fn.setfperm, path, "rw-------")
  end
end

function M.shell_env_assignment(name, value)
  return name .. "=" .. vim.fn.shellescape(tostring(value or ""))
end

function M.lua_string(value)
  local escaped = tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
  escaped = escaped:gsub("[%z\1-\31\127]", function(char)
    if char == "\n" then
      return "\\n"
    end
    if char == "\r" then
      return "\\r"
    end
    if char == "\t" then
      return "\\t"
    end
    return string.format("\\%03d", string.byte(char))
  end)
  return '"' .. escaped .. '"'
end

function M.launch_base_name(runtime, workspace)
  workspace = type(workspace) == "table" and workspace or {}
  local server_dir = runtime:workspace_server_dir()
  local server = workspace.nvim_server or runtime:workspace_server_path(workspace.project_root, workspace.safe_name)
  local name = tostring(server or workspace.safe_name or workspace.window_name or "workspace")
  name = vim.fn.fnamemodify(name, ":t"):gsub("%.sock$", "")
  if name == "" then
    name = "workspace"
  end
  return server_dir, name
end

function M.launch_script_path(runtime, workspace)
  local server_dir, name = M.launch_base_name(runtime, workspace)
  return server_dir .. "/" .. name .. ".lua"
end

function M.launch_payload_path(runtime, workspace)
  local server_dir, name = M.launch_base_name(runtime, workspace)
  return server_dir .. "/" .. name .. ".payload.lua"
end

function M.payload_from_workspace(workspace)
  workspace = type(workspace) == "table" and workspace or {}
  return {
    initial_prompt = workspace.initial_prompt or "",
    mission_objective = workspace.mission_objective or "",
    mission_focus_packet = workspace.mission_focus_packet or "",
    custom_instruction = workspace.custom_instruction or "",
    resolved_instruction = workspace.resolved_instruction or "",
    instruction_file = workspace.instruction_file or "",
  }
end

function M.encode_payload_lua(payload)
  payload = type(payload) == "table" and payload or {}
  return table.concat({
    "return {",
    "initial_prompt=" .. M.lua_string(payload.initial_prompt or "") .. ",",
    "mission_objective=" .. M.lua_string(payload.mission_objective or "") .. ",",
    "mission_focus_packet=" .. M.lua_string(payload.mission_focus_packet or "") .. ",",
    "custom_instruction=" .. M.lua_string(payload.custom_instruction or "") .. ",",
    "resolved_instruction=" .. M.lua_string(payload.resolved_instruction or "") .. ",",
    "instruction_file=" .. M.lua_string(payload.instruction_file or "") .. ",",
    "}",
  }, "")
end

function M.write_private_file(path, content)
  if type(path) ~= "string" or path == "" then
    return false, "missing path"
  end
  local directory = vim.fn.fnamemodify(path, ":h")
  if directory ~= "" then
    local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, directory, "p", 448)
    if not mkdir_ok or (mkdir_result ~= 1 and mkdir_result ~= 0) then
      mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, directory, "p")
      if not mkdir_ok or (mkdir_result ~= 1 and type(vim.fn.isdirectory) == "function" and vim.fn.isdirectory(directory) ~= 1) then
        if not mkdir_ok or mkdir_result ~= 1 then
          return false, "Failed to create directory"
        end
      end
    end
    set_private_file_mode(directory)
    if type(vim.fn.setfperm) == "function" then
      pcall(vim.fn.setfperm, directory, "rwx------")
    end
  end

  local ok, result = pcall(vim.fn.writefile, { tostring(content or "") }, path)
  if not ok or result ~= 0 then
    return false, "Failed to write file"
  end
  set_private_file_mode(path)
  return true, nil
end

--- Bootstrap script keeps identifiers only. Sensitive prompt/instruction text is
--- loaded from a sibling private payload file (deleted after one read).
function M.bootstrap_lua(workspace)
  workspace = type(workspace) == "table" and workspace or {}
  local root = workspace.project_root or "."
  local target_path = workspace.target_path or ""
  local target_type = workspace.target_type or ""
  local profile = workspace.permission_profile or "default"
  local agent_provider = workspace.agent_provider or "codex"
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
  local window_name = workspace.window_name or ""
  local nvim_server = workspace.nvim_server or ""
  local initial_mode = workspace.initial_mode or ""
  local open_visible = workspace.open_visible == true
  local agent_session_id = workspace.agent_session_id or ""
  local agent_session_path = workspace.agent_session_path or ""
  local agent_session_captured_at = workspace.agent_session_captured_at or ""
  local payload_path = workspace.launch_payload or ""
  local instruction_file = workspace.instruction_file or ""
  if agent_provider ~= "grok" then
    if agent_session_id == "" then
      agent_session_id = workspace.codex_session_id or ""
    end
    if agent_session_path == "" then
      agent_session_path = workspace.codex_session_path or ""
    end
    if agent_session_captured_at == "" then
      agent_session_captured_at = workspace.codex_session_captured_at or ""
    end
  end
  local resume_agent_session = workspace.resume_agent_session == true
  local has_prompt = type(workspace.initial_prompt) == "string" and workspace.initial_prompt ~= ""
  local agent_status = has_prompt and "working" or "idle"
  local status = has_prompt and "active" or "idle"
  local show_codux = open_visible or has_prompt

  return table.concat({
    "local root=" .. M.lua_string(root),
    "local target=" .. M.lua_string(target_path),
    "local target_type=" .. M.lua_string(target_type),
    "local profile=" .. M.lua_string(profile),
    "local agent_provider=" .. M.lua_string(agent_provider),
    "local payload_path=" .. M.lua_string(payload_path),
    "local instruction_file=" .. M.lua_string(instruction_file),
    "local show_codux=" .. tostring(show_codux),
    "local payload={}",
    "if payload_path~='' then pcall(function() local chunk=loadfile(payload_path); if type(chunk)=='function' then payload=chunk() or {} end end) pcall(vim.fn.delete,payload_path) end",
    "local prompt=type(payload.initial_prompt)=='string' and payload.initial_prompt or ''",
    "if instruction_file=='' and type(payload.instruction_file)=='string' then instruction_file=payload.instruction_file end",
    "local workspace={name="
      .. M.lua_string(name)
      .. ",safe_name="
      .. M.lua_string(safe_name)
      .. ",project_root=root,target_path=target,target_type=target_type,git_branch="
      .. M.lua_string(branch)
      .. ",workspace_kind="
      .. M.lua_string(workspace_kind)
      .. ",git_common_dir="
      .. M.lua_string(git_common_dir)
      .. ",worktree_path="
      .. M.lua_string(worktree_path)
      .. ",worktree_branch="
      .. M.lua_string(worktree_branch)
      .. ",worktree_base="
      .. M.lua_string(worktree_base)
      .. ",worktree_base_commit="
      .. M.lua_string(worktree_base_commit)
      .. ",mission_id="
      .. M.lua_string(mission_id)
      .. ",mission_name="
      .. M.lua_string(mission_name)
      .. ",mission_role="
      .. M.lua_string(mission_role)
      .. ",mission_objective=(type(payload.mission_objective)=='string' and payload.mission_objective) or ''"
      .. ",mission_focus_packet=(type(payload.mission_focus_packet)=='string' and payload.mission_focus_packet) or ''"
      .. ",window_name="
      .. M.lua_string(window_name)
      .. ",nvim_server="
      .. M.lua_string(nvim_server)
      .. ",custom_instruction=(type(payload.custom_instruction)=='string' and payload.custom_instruction) or ''"
      .. ",resolved_instruction=(type(payload.resolved_instruction)=='string' and payload.resolved_instruction) or ''"
      .. ",instruction_file=instruction_file"
      .. ",initial_mode="
      .. M.lua_string(initial_mode)
      .. ",agent_provider=agent_provider,permission_profile=profile,agent_status="
      .. M.lua_string(agent_status)
      .. ",status="
      .. M.lua_string(status)
      .. ",agent_session_id="
      .. M.lua_string(agent_session_id)
      .. ",agent_session_path="
      .. M.lua_string(agent_session_path)
      .. ",agent_session_captured_at="
      .. M.lua_string(agent_session_captured_at)
      .. ",resume_agent_session="
      .. tostring(resume_agent_session)
      .. ",open_visible="
      .. tostring(open_visible)
      .. ",initial_prompt=prompt}",
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

function M.write_launch_script(runtime, workspace)
  workspace = type(workspace) == "table" and workspace or {}
  local path = M.launch_script_path(runtime, workspace)
  local payload_path = M.launch_payload_path(runtime, workspace)
  workspace.launch_payload = payload_path

  local payload_ok, payload_err = M.write_private_file(payload_path, M.encode_payload_lua(M.payload_from_workspace(workspace)))
  if not payload_ok then
    return nil, payload_err or "Failed to write Codux workspace launch payload"
  end

  local ok, err = M.write_private_file(path, M.bootstrap_lua(workspace))
  if not ok then
    pcall(vim.fn.delete, payload_path)
    return nil, err or "Failed to write Codux workspace launch script"
  end

  return path, nil
end

function M.delete_launch_script(path)
  if type(path) ~= "string" or path == "" then
    return true
  end
  if type(vim.fn.delete) ~= "function" then
    return true
  end

  local payload_path = path:gsub("%.lua$", ".payload.lua")
  if payload_path ~= path then
    pcall(vim.fn.delete, payload_path)
  end
  local ok = pcall(vim.fn.delete, path)
  return ok
end

function M.nvim_command(runtime, workspace)
  workspace = type(workspace) == "table" and workspace or {}
  local config = runtime.get_config()
  local env = {
    M.shell_env_assignment("CODEX_CMD", runtime.command_util.shell(providers.command(config, "codex", "default"))),
    M.shell_env_assignment(
      "CODEX_WORKSPACE_AUTO_CMD",
      runtime.command_util.shell(providers.command(config, "codex", "auto"))
    ),
    M.shell_env_assignment(
      "CODEX_DANGER_FULL_ACCESS_CMD",
      runtime.command_util.shell(providers.command(config, "codex", "danger"))
    ),
    M.shell_env_assignment("GROK_CMD", runtime.command_util.shell(providers.command(config, "grok", "default"))),
    M.shell_env_assignment(
      "GROK_WORKSPACE_AUTO_CMD",
      runtime.command_util.shell(providers.command(config, "grok", "auto"))
    ),
    M.shell_env_assignment(
      "GROK_DANGER_FULL_ACCESS_CMD",
      runtime.command_util.shell(providers.command(config, "grok", "danger"))
    ),
  }
  local nvim_target = "."
  if workspace.target_type ~= "directory" and type(workspace.target_path) == "string" and workspace.target_path ~= "" then
    nvim_target = workspace.target_path
  end

  -- Prefer luafile so the bootstrap body is never on the process command line.
  local bootstrap_command
  if type(workspace.launch_script) == "string" and workspace.launch_script ~= "" then
    bootstrap_command = "luafile " .. fnameescape(workspace.launch_script)
  else
    bootstrap_command = "lua " .. M.bootstrap_lua(workspace)
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
    vim.fn.shellescape(bootstrap_command),
  }

  return table.concat(parts, " ")
end

return M
