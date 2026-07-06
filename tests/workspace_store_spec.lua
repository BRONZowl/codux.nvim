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
  }, "review", "/repo")

  assert_equal(normalized.nvim_server, "/run/user/1000/codux/ws-review.sock")
end

do
  local workspace = workspace_store_mod.new({}).workspace_from_state({
    name = "review",
    safe_name = "review",
    project_root = "/repo",
    last_activity_at = "2026-07-05T10:00:00Z",
    last_target_at = "2026-07-05T09:00:00Z",
  }, {
    last_activity_at = "2026-07-04T10:00:00Z",
    last_target_at = "2026-07-04T09:00:00Z",
  })

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
  }, {
    last_activity_at = "2026-07-05T10:00:00Z",
    last_target_at = "2026-07-05T09:00:00Z",
  })

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

print("workspace_store_spec.lua: ok")
