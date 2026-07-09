local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local workspace_store_mod = require("codux.workspace_store")

local function default_workspace_config()
  return {
    workspaces = {
      instruction_files = true,
    },
  }
end

do
  local old_mkdir = vim.fn.mkdir
  local old_writefile = vim.fn.writefile
  local wrote = false
  vim.fn.mkdir = function()
    return 0
  end
  vim.fn.writefile = function()
    wrote = true
    return 0
  end

  local store = workspace_store_mod.new({
    get_workspace_config = function()
      return default_workspace_config().workspaces
    end,
  })
  local ok, message = store:write_instruction_file("/repo", "review", "review the backend")
  vim.fn.mkdir = old_mkdir
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to create Codux workspace instruction directory")
  assert_false(wrote)
end

do
  local old_mkdir = vim.fn.mkdir
  local old_writefile = vim.fn.writefile
  vim.fn.mkdir = function()
    return 1
  end
  vim.fn.writefile = function()
    return -1
  end

  local store = workspace_store_mod.new({
    get_workspace_config = function()
      return default_workspace_config().workspaces
    end,
  })
  local ok, message = store:write_instruction_file("/repo", "review", "review the backend")
  vim.fn.mkdir = old_mkdir
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to write Codux workspace instruction file")
end

do
  local old_mkdir = vim.fn.mkdir
  local old_writefile = vim.fn.writefile
  local wrote = false
  vim.fn.mkdir = function()
    return 0
  end
  vim.fn.writefile = function()
    wrote = true
    return 0
  end

  local store = workspace_store_mod.new({
    get_workspace_config = function()
      return {
        state_file = "/tmp/codux-workspaces.json",
      }
    end,
    json_encode = function()
      return "{}"
    end,
  })
  local ok, message = store:write_state({ projects = {} })
  vim.fn.mkdir = old_mkdir
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to create Codux workspace state directory")
  assert_false(wrote)
end

do
  local old_mkdir = vim.fn.mkdir
  local old_writefile = vim.fn.writefile
  vim.fn.mkdir = function()
    return 1
  end
  vim.fn.writefile = function()
    return -1
  end

  local store = workspace_store_mod.new({
    get_workspace_config = function()
      return {
        state_file = "/tmp/codux-workspaces.json",
      }
    end,
    json_encode = function()
      return "{}"
    end,
  })
  local ok, message = store:write_state({ projects = {} })
  vim.fn.mkdir = old_mkdir
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to write Codux workspace state")
end

do
  local store = workspace_store_mod.new({
    get_workspace_config = function()
      return default_workspace_config().workspaces
    end,
  })
  local normalized = store:normalize_record({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    nvim_server = "/run/user/1000/codux/ws-review.sock",
    mission_focus_packet = "Focused context",
  }, "review", "/repo")

  assert_equal(normalized.nvim_server, "/run/user/1000/codux/ws-review.sock")
  assert_equal(normalized.mission_focus_packet, "Focused context")
end

do
  local workspace = workspace_store_mod.new({}).workspace_from_state({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    mission_focus_packet = "Current focus",
    last_activity_at = "2026-07-05T10:00:00Z",
    last_target_at = "2026-07-05T09:00:00Z",
  }, {
    mission_focus_packet = "Old focus",
    last_activity_at = "2026-07-04T10:00:00Z",
    last_target_at = "2026-07-04T09:00:00Z",
  })

  assert_equal(workspace.mission_focus_packet, "Current focus")
  assert_equal(workspace.last_activity_at, "2026-07-05T10:00:00Z")
  assert_equal(workspace.last_target_at, "2026-07-05T09:00:00Z")
end

do
  local store = workspace_store_mod.new({})
  local record = store:state_record({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_name = "review",
    status = "idle",
    mission_focus_packet = "Current focus",
  }, {
    last_activity_at = "2026-07-05T10:00:00Z",
    last_target_at = "2026-07-05T09:00:00Z",
  })

  assert_equal(record.mission_focus_packet, "Current focus")
  assert_equal(record.last_activity_at, "2026-07-05T10:00:00Z")
  assert_equal(record.last_target_at, "2026-07-05T09:00:00Z")
end

do
  local store = workspace_store_mod.new({})
  local record = store:state_record({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    window_name = "review",
    status = "idle",
    last_activity_at = "2026-07-05T12:00:00Z",
    last_target_at = "2026-07-05T11:00:00Z",
  }, {
    last_activity_at = "2026-07-05T10:00:00Z",
    last_target_at = "2026-07-05T09:00:00Z",
  })

  assert_equal(record.last_activity_at, "2026-07-05T12:00:00Z")
  assert_equal(record.last_target_at, "2026-07-05T11:00:00Z")
end

do
  local store = workspace_store_mod.new({})
  local normalized = store:normalize_record({
    name = "grok-review",
    safe_name = "grok-review",
    project_root = "/repo",
    agent_provider = "grok",
    codex_session_id = "codex-session",
    codex_session_path = "/codex/session.jsonl",
    codex_session_captured_at = "2026-07-09T12:00:00Z",
  }, "grok-review", "/repo")

  assert_equal(normalized.agent_provider, "grok")
  assert_nil(normalized.agent_session_id)
  assert_nil(normalized.agent_session_path)
  assert_nil(normalized.agent_session_captured_at)

  local workspace = store.workspace_from_state({
    name = "grok-review",
    safe_name = "grok-review",
    project_root = "/repo",
    agent_provider = "grok",
    codex_session_id = "codex-session",
    codex_session_path = "/codex/session.jsonl",
    codex_session_captured_at = "2026-07-09T12:00:00Z",
  }, {
    agent_session_id = "fallback-session",
    agent_session_path = "/fallback/session.jsonl",
    agent_session_captured_at = "2026-07-09T13:00:00Z",
  })

  assert_equal(workspace.agent_session_id, "fallback-session")
  assert_equal(workspace.agent_session_path, "/fallback/session.jsonl")
  assert_equal(workspace.agent_session_captured_at, "2026-07-09T13:00:00Z")

  local state_record = store:state_record({
    name = "grok-review",
    safe_name = "grok-review",
    project_root = "/repo",
    window_name = "grok-review",
    status = "idle",
    agent_provider = "grok",
    codex_session_id = "codex-session",
    codex_session_path = "/codex/session.jsonl",
    codex_session_captured_at = "2026-07-09T12:00:00Z",
  })

  assert_nil(state_record.agent_session_id)
  assert_nil(state_record.agent_session_path)
  assert_nil(state_record.agent_session_captured_at)
end

print("workspace_store_spec.lua: ok")
