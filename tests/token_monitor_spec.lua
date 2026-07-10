local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_table_equal = h.assert_table_equal

local token_monitor_mod = require("codux.token_monitor")
local token_usage = require("codux.token_usage")
local dashboard_render = require("codux.mission_dashboard_render")

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
    get_agent_provider = opts.get_agent_provider,
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

do
  assert_equal(token_usage.normalize_percent(12.4), 12)
  assert_equal(token_usage.normalize_percent(12.6), 13)
  assert_equal(token_usage.normalize_percent(-5), 0)
  assert_equal(token_usage.normalize_percent(150), 100)
  assert_nil(token_usage.normalize_percent("nope"))
end

do
  local usage = token_usage.parse_response({
    result = {
      rateLimits = {
        primary = { windowDurationMins = 300, usedPercent = 12.4 },
        secondary = { windowDurationMins = 10080, usedPercent = 34.6 },
      },
    },
  })
  assert_equal(usage.five_hour_percent, 12)
  assert_equal(usage.weekly_percent, 35)
end

do
  local usage = token_usage.parse_response({
    result = {
      rateLimitsByLimitId = {
        codex = {
          primary = { windowDurationMins = 300, usedPercent = 7 },
          secondary = { windowDurationMins = 10080, usedPercent = 9 },
        },
      },
    },
  })
  assert_equal(usage.five_hour_percent, 7)
  assert_equal(usage.weekly_percent, 9)
end

do
  assert_nil(token_usage.parse_response({ result = {} }), "missing rate limits should be nil")
  assert_nil(
    token_usage.parse_response({
      result = {
        rateLimits = {
          primary = { windowDurationMins = 999, usedPercent = 10 },
        },
      },
    }),
    "unknown window durations should be nil"
  )
end

do
  assert_equal(
    token_usage.label({ five_hour_percent = 1, weekly_percent = 2 }),
    "usage | 5hr 1% | wk 2%"
  )
  assert_equal(
    token_usage.label({ last_error = "timeout" }, { show_error = true }),
    "usage | 5hr --% | wk --% (unavailable)"
  )
  assert_equal(
    token_usage.label({ last_error = "timeout" }),
    "usage | 5hr --% | wk --%"
  )
  assert_equal(token_usage.label({}, { enabled = false }), "")
  assert_equal(token_usage.label({ five_hour_percent = 1 }, { running = false }), "")
end

do
  local monitor = monitor_with_config({
    token_monitor = {
      refresh_ms = 30000,
    },
  })
  local cfg = monitor:config()
  assert_equal(cfg.enabled, true, "partial config should merge enabled default")
  assert_equal(cfg.refresh_ms, 30000, "partial config should keep overrides")
  assert_equal(cfg.timeout_ms, 5000, "partial config should merge timeout default")
  assert_equal(monitor:refresh_ms(), 30000)
end

do
  local state = {
    five_hour_percent = 12,
    weekly_percent = 34,
    last_error = "old",
    in_flight = true,
    job_id = 99,
    stdout = "partial",
    initialized = true,
  }
  local stopped = {}
  local monitor = monitor_with_config({ codex_cmd = "codex" }, { state = state })
  h.with_stubs({
    {
      target = vim.fn,
      key = "jobstop",
      value = function(job_id)
        table.insert(stopped, job_id)
        return 1
      end,
    },
  }, function()
    monitor:stop()
  end)

  assert_equal(state.five_hour_percent, 12, "stop should keep last-known five-hour usage")
  assert_equal(state.weekly_percent, 34, "stop should keep last-known weekly usage")
  assert_nil(state.last_error, "stop should clear last_error")
  assert_false(state.in_flight)
  assert_nil(state.job_id)
  assert_equal(state.stdout, "")
  assert_false(state.initialized)
  assert_table_equal(stopped, { 99 })
end

do
  local state = {
    five_hour_percent = 5,
    weekly_percent = 6,
  }
  local updates = 0
  local monitor = monitor_with_config({ codex_cmd = "codex" }, {
    state = state,
    get_agent_provider = function()
      return "grok"
    end,
    on_update = function()
      updates = updates + 1
    end,
  })

  assert_false(monitor:refresh(false), "unsupported provider should not refresh")
  assert_nil(state.five_hour_percent, "unsupported provider should clear usage")
  assert_nil(state.weekly_percent)
  assert_nil(state.last_error)
  assert_equal(updates, 1)
end

do
  local now_ms = 1000
  local refresh_calls = 0
  local controller = {
    state = {},
    token_usage_now_ms = function()
      return now_ms
    end,
    token_usage_refresh_ms = function()
      return 60000
    end,
    refresh_token_usage = function()
      refresh_calls = refresh_calls + 1
      return false, "in_flight"
    end,
  }

  assert_false(dashboard_render.refresh_dashboard_token_usage(controller, false))
  assert_equal(refresh_calls, 1)
  assert_nil(controller.state.mission_dashboard_token_usage_refreshed_at, "in-flight must not stamp throttle")

  assert_false(dashboard_render.refresh_dashboard_token_usage(controller, false))
  assert_equal(refresh_calls, 2, "in-flight refresh should remain eligible immediately")

  controller.refresh_token_usage = function()
    refresh_calls = refresh_calls + 1
    return false
  end
  assert_false(dashboard_render.refresh_dashboard_token_usage(controller, false))
  assert_equal(controller.state.mission_dashboard_token_usage_refreshed_at, 1000, "permanent failure should stamp throttle")
  assert_equal(refresh_calls, 3)

  assert_false(dashboard_render.refresh_dashboard_token_usage(controller, false))
  assert_equal(refresh_calls, 3, "permanent failure should throttle subsequent calls")

  controller.refresh_token_usage = function()
    refresh_calls = refresh_calls + 1
    return true
  end
  now_ms = 62000
  assert_true(dashboard_render.refresh_dashboard_token_usage(controller, false))
  assert_equal(controller.state.mission_dashboard_token_usage_refreshed_at, 62000)
  assert_equal(refresh_calls, 4)

  assert_false(dashboard_render.refresh_dashboard_token_usage(controller, false))
  assert_equal(refresh_calls, 4, "successful refresh should throttle subsequent calls")
end

print("token_monitor_spec.lua: ok")
