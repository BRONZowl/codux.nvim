package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

if type(vim) ~= "table" then
  vim = {
    fn = {
      shellescape = function(value)
        return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
      end,
    },
    list_extend = function(target, values)
      target = type(target) == "table" and target or {}
      for _, value in ipairs(type(values) == "table" and values or {}) do
        table.insert(target, value)
      end
      return target
    end,
  }
end

local token_monitor_mod = require("codux.token_monitor")

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function assert_table_equal(actual, expected, message)
  if type(actual) ~= "table" then
    error((message or "assertion failed") .. ": expected table, got " .. type(actual), 2)
  end
  assert_equal(#actual, #expected, message)
  for index, expected_value in ipairs(expected) do
    assert_equal(actual[index], expected_value, message .. " at index " .. tostring(index))
  end
end

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
