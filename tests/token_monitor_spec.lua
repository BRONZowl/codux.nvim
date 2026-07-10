local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_table_equal = h.assert_table_equal

local token_monitor_mod = require("codux.token_monitor")

local function monitor_with_config(config, opts)
  opts = opts or {}
  return token_monitor_mod.new({
    defaults = {
      enabled = true,
      refresh_ms = 60000,
      timeout_ms = 5000,
    },
    state = opts.state or {},
    get_config = function()
      return config
    end,
    is_running = opts.is_running or function()
      return true
    end,
    on_update = opts.on_update or function() end,
  })
end

do
  local monitor = monitor_with_config({
    codex_cmd = 'codex -s workspace-write -a on-request -c approvals_reviewer="user"',
  })
  local command, executable, error_message = monitor:app_server_command()

  assert_equal(error_message, nil, "default string config should be valid")
  assert_equal(executable, "codex", "default string config should derive executable only")
  assert_table_equal(command, { "codex", "app-server", "--stdio" }, "default string config should not inherit terminal flags")
end

do
  local monitor = monitor_with_config({
    codex_cmd = { "codex", "-s", "workspace-write" },
  })
  local command, executable, error_message = monitor:app_server_command()

  assert_equal(error_message, nil, "default list config should be valid")
  assert_equal(executable, "codex", "default list config should derive executable only")
  assert_table_equal(command, { "codex", "app-server", "--stdio" }, "default list config should not inherit terminal flags")
end

do
  local monitor = monitor_with_config({
    providers = {
      codex = {
        default_cmd = "nested-codex --profile terminal",
      },
    },
  })
  local command, executable, error_message = monitor:app_server_command()

  assert_equal(error_message, nil, "nested provider config should be valid")
  assert_equal(executable, "nested-codex", "nested provider config should derive the executable")
  assert_table_equal(command, { "nested-codex", "app-server", "--stdio" }, "monitor should not inherit terminal flags")
end

do
  local monitor = monitor_with_config({
    codex_cmd = "codex",
    token_monitor = {
      codex_cmd = "codex-token --profile usage",
    },
  })
  local command, executable, error_message = monitor:app_server_command()

  assert_equal(error_message, nil, "explicit string monitor command should be valid")
  assert_equal(executable, "codex-token", "explicit string monitor command should derive executable")
  assert_equal(
    command,
    "codex-token --profile usage 'app-server' '--stdio'",
    "explicit string monitor command should keep configured args"
  )
end

do
  local monitor = monitor_with_config({
    codex_cmd = "codex",
    token_monitor = {
      codex_cmd = { "codex-token", "--profile", "usage" },
    },
  })
  local command, executable, error_message = monitor:app_server_command()

  assert_equal(error_message, nil, "explicit list monitor command should be valid")
  assert_equal(executable, "codex-token", "explicit list monitor command should derive executable")
  assert_table_equal(
    command,
    { "codex-token", "--profile", "usage", "app-server", "--stdio" },
    "explicit list monitor command should keep configured args"
  )
end

do
  local monitor = monitor_with_config({
    codex_cmd = "codex",
  }, {
    state = {
      five_hour_percent = 12,
      weekly_percent = 34,
    },
    is_running = function()
      return false
    end,
  })

  assert_equal(monitor:label({ running = false, mode = "not running" }), "")
  assert_equal(
    monitor:label({ running = false, mode = "not running", show_when_not_running = true }),
    "usage | 5hr 12% | wk 34%"
  )
end

do
  local monitor = monitor_with_config({
    token_monitor = false,
  }, {
    state = {
      five_hour_percent = 12,
      weekly_percent = 34,
    },
    is_running = function()
      return false
    end,
  })

  assert_equal(monitor:label({ show_when_not_running = true }), "")
end

do
  local state = {}
  local updates = 0
  local monitor = monitor_with_config({
    codex_cmd = "codex",
    token_monitor = {
      codex_cmd = {},
    },
  }, {
    state = state,
    is_running = function()
      return false
    end,
    on_update = function()
      updates = updates + 1
    end,
  })

  assert_equal(monitor:refresh(false), false, "default refresh should require a running terminal")
  assert_nil(state.last_error, "default refresh should stop before command validation")
  assert_equal(updates, 0, "default refresh should not publish an update")

  assert_equal(
    monitor:refresh(false, { require_running = false }),
    false,
    "dashboard refresh should validate even without a running terminal"
  )
  assert_equal(state.last_error, "Codex token monitor command list must start with an executable")
  assert_equal(updates, 1, "dashboard refresh should publish command validation errors")
end

do
  local state = {}
  local updates = 0
  local monitor = monitor_with_config({
    codex_cmd = "codex",
    token_monitor = {
      codex_cmd = {},
    },
  }, {
    state = state,
    on_update = function()
      updates = updates + 1
    end,
  })

  assert_equal(monitor:refresh(false), false, "invalid explicit monitor command should not refresh")
  assert_equal(state.last_error, "Codex token monitor command list must start with an executable")
  assert_equal(updates, 1, "invalid explicit monitor command should publish an update")
end

print("token_monitor_spec.lua: ok")
