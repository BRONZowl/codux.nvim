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
  local providers = require("codux.providers")
  assert_true(providers.token_usage_supported("codex"))
  assert_true(providers.token_usage_supported("grok"))
  -- Unknown values still fall back to codex (legacy normalize behavior).
  assert_true(providers.token_usage_supported("nope"))
end

do
  local parsed = token_usage.parse_grok_headers({
    ["x-ratelimit-limit-tokens"] = "100",
    ["x-ratelimit-remaining-tokens"] = "100",
    ["x-ratelimit-limit-requests"] = "50",
    ["x-ratelimit-remaining-requests"] = "50",
  })
  assert_equal(parsed.tpm_percent, 0)
  assert_equal(parsed.rpm_percent, 0)

  parsed = token_usage.parse_grok_headers(
    "HTTP/1.1 200 OK\nx-ratelimit-limit-tokens: 100\nx-ratelimit-remaining-tokens: 40\nx-ratelimit-limit-requests: 10\nx-ratelimit-remaining-requests: 7\n\n"
  )
  assert_equal(parsed.tpm_percent, 60)
  assert_equal(parsed.rpm_percent, 30)

  -- Live-shaped curl -D - dump: HTTP/2, trailing space on status, large limits, CRLF.
  parsed = token_usage.parse_grok_headers(
    "HTTP/2 200 \r\nx-ratelimit-limit-tokens: 53000000\r\nx-ratelimit-remaining-tokens: 53000000\r\nx-ratelimit-limit-requests: 8300\r\nx-ratelimit-remaining-requests: 8300\r\n\r\n"
  )
  assert_equal(parsed.tpm_percent, 0)
  assert_equal(parsed.rpm_percent, 0)
  assert_equal(parsed.usage_provider, "grok")

  parsed = token_usage.parse_grok_headers(
    "HTTP/2 200\r\nx-ratelimit-limit-tokens: 100\r\nx-ratelimit-remaining-tokens: 25\r\nx-ratelimit-limit-requests: 20\r\nx-ratelimit-remaining-requests: 10\r\n\r\n"
  )
  assert_equal(parsed.tpm_percent, 75)
  assert_equal(parsed.rpm_percent, 50)

  assert_nil(token_usage.parse_grok_headers({}))
  assert_nil(token_usage.parse_grok_headers({ ["x-ratelimit-limit-tokens"] = "0", ["x-ratelimit-remaining-tokens"] = "0" }))
end

do
  assert_equal(token_usage.format_count(53000000), "53.0M")
  assert_equal(token_usage.format_count(8300), "8300")
  assert_equal(token_usage.format_count(12500), "12.5k")

  -- Absolute remaining/limit when percent is 0 (typical for large xAI quotas).
  assert_equal(
    token_usage.label({
      tpm_percent = 0,
      rpm_percent = 0,
      tpm_limit = 53000000,
      tpm_remaining = 53000000,
      rpm_limit = 8300,
      rpm_remaining = 8300,
      usage_provider = "grok",
    }),
    "quota | tpm 53.0M/53.0M | rpm 8300/8300"
  )
  -- When percent is non-zero, show percent and remaining.
  assert_equal(
    token_usage.label({
      tpm_percent = 12,
      rpm_percent = 3,
      tpm_limit = 100,
      tpm_remaining = 88,
      rpm_limit = 100,
      rpm_remaining = 97,
      usage_provider = "grok",
    }),
    "quota | tpm 12% · 88 left | rpm 3% · 97 left"
  )
  assert_equal(
    token_usage.label({ last_error = "nope" }, { provider = "grok", show_error = true }),
    "quota | tpm --% | rpm --% (unavailable)"
  )
  -- Codex label format must stay byte-identical for the same inputs.
  assert_equal(
    token_usage.label({ five_hour_percent = 1, weekly_percent = 2 }),
    "usage | 5hr 1% | wk 2%"
  )
end

do
  local state = {
    five_hour_percent = 5,
    weekly_percent = 6,
  }
  local updates = 0
  local monitor = monitor_with_config({
    codex_cmd = "codex",
    token_monitor = {
      grok = false,
    },
  }, {
    state = state,
    get_agent_provider = function()
      return "grok"
    end,
    on_update = function()
      updates = updates + 1
    end,
  })

  assert_false(monitor:refresh(false, { require_running = false }), "disabled grok monitor should not probe")
  assert_equal(state.usage_provider, "grok")
  assert_nil(state.tpm_percent)
  assert_nil(state.rpm_percent)
  assert_equal(updates, 1)
  -- Codex cached percents are not cleared by a Grok-disabled refresh.
  assert_equal(state.five_hour_percent, 5)
  assert_equal(state.weekly_percent, 6)
end

do
  local state = {
    five_hour_percent = 5,
    weekly_percent = 6,
  }
  local updates = 0
  local started_commands = {}
  local monitor = token_monitor_mod.new({
    defaults = {
      enabled = true,
      refresh_ms = 60000,
      timeout_ms = 5000,
      grok = { enabled = true, base_url = "https://api.x.ai/v1", model = "grok-4.5" },
    },
    state = state,
    get_config = function()
      return {
        codex_cmd = "codex",
        token_monitor = {
          grok = { api_key = "test-key" },
        },
      }
    end,
    is_running = function()
      return true
    end,
    get_agent_provider = function()
      return "grok"
    end,
    json_encode = function()
      return '{"model":"grok-4.5"}'
    end,
    on_update = function()
      updates = updates + 1
    end,
  })

  h.with_stubs({
    {
      target = vim,
      key = "schedule_wrap",
      value = function(fn)
        return fn
      end,
    },
    {
      target = vim.fn,
      key = "executable",
      value = function(name)
        if name == "curl" or name == "codex" then
          return 1
        end
        return 0
      end,
    },
    {
      target = vim.fn,
      key = "jobstart",
      value = function(command)
        table.insert(started_commands, command)
        return 0
      end,
    },
  }, function()
    assert_false(
      monitor:refresh(false, { require_running = false, agent_provider = "grok" }),
      "failed grok jobstart should return false"
    )
    assert_equal(#started_commands, 1, "grok override should start curl probe")
    assert_true(type(started_commands[1]) == "table")
    assert_equal(started_commands[1][1], "curl")
    assert_equal(state.five_hour_percent, 5, "grok probe must not clear Codex fields")
    assert_equal(updates, 1)

    state.five_hour_percent = 9
    state.weekly_percent = 10
    updates = 0
    started_commands = {}
    assert_false(
      monitor:refresh(false, { require_running = false, agent_provider = "codex" }),
      "jobstart failure should still attempt codex when overridden"
    )
    assert_equal(#started_commands, 1, "codex override should start even when main provider is grok")
    assert_equal(started_commands[1][1], "codex")
    assert_equal(updates, 1)
  end)
end

do
  local key, err = token_monitor_mod.resolve_grok_api_key({
    grok = {},
    env = {},
    read_file = function()
      return nil
    end,
  })
  assert_nil(key)
  assert_equal(err, "Grok credentials not found")

  key = token_monitor_mod.resolve_grok_api_key({
    grok = { api_key = "from-config" },
    env = { XAI_API_KEY = "from-env" },
  })
  assert_equal(key, "from-config")

  key = token_monitor_mod.resolve_grok_api_key({
    grok = {},
    env = { GROK_API_KEY = "from-grok-env" },
  })
  assert_equal(key, "from-grok-env")

  key = token_monitor_mod.resolve_grok_api_key({
    grok = { auth_file = "/tmp/fake-auth.json" },
    env = {},
    read_file = function()
      return '{"https://auth.x.ai::id":{"key":"oauth-key"}}'
    end,
    json_decode = function()
      return { ["https://auth.x.ai::id"] = { key = "oauth-key" } }
    end,
  })
  assert_equal(key, "oauth-key")
end

do
  local state = {
    five_hour_percent = 11,
    weekly_percent = 22,
    by_provider = { codex = { five_hour_percent = 11, weekly_percent = 22 }, grok = {} },
  }
  local updates = 0
  local stdout_cb
  local exit_cb
  local monitor = token_monitor_mod.new({
    defaults = {
      enabled = true,
      refresh_ms = 60000,
      timeout_ms = 5000,
      grok = { enabled = true, model = "grok-4.5", base_url = "https://api.x.ai/v1" },
    },
    state = state,
    get_config = function()
      return { token_monitor = { grok = { api_key = "k" } } }
    end,
    is_running = function()
      return false
    end,
    json_encode = function()
      return '{"model":"grok-4.5"}'
    end,
    on_update = function()
      updates = updates + 1
    end,
  })

  local old_uv = vim.uv
  local old_loop = vim.loop
  vim.uv = nil
  vim.loop = nil
  h.with_stubs({
    {
      target = vim,
      key = "schedule_wrap",
      value = function(fn)
        return fn
      end,
    },
    {
      target = vim.fn,
      key = "executable",
      value = function()
        return 1
      end,
    },
    {
      target = vim.fn,
      key = "jobstart",
      value = function(_, opts)
        stdout_cb = opts.on_stdout
        exit_cb = opts.on_exit
        return 42
      end,
    },
  }, function()
    assert_true(monitor:refresh(false, { require_running = false, agent_provider = "grok" }))
    assert_equal(state.job_id, 42)
    -- Realistic path: buffered stdout arrives, then exit (stdout must not depend on schedule order).
    stdout_cb(nil, {
      "HTTP/2 200 ",
      "x-ratelimit-limit-tokens: 100",
      "x-ratelimit-remaining-tokens: 25",
      "x-ratelimit-limit-requests: 20",
      "x-ratelimit-remaining-requests: 10",
      "",
      "",
    })
    exit_cb(nil, 0)
    assert_equal(state.tpm_percent, 75)
    assert_equal(state.rpm_percent, 50)
    assert_equal(state.tpm_limit, 100)
    assert_equal(state.tpm_remaining, 25)
    assert_equal(state.rpm_limit, 20)
    assert_equal(state.rpm_remaining, 10)
    assert_equal(state.usage_provider, "grok")
    assert_nil(state.last_error)
    assert_equal(state.by_provider.grok.tpm_percent, 75)
    assert_equal(state.by_provider.grok.rpm_percent, 50)
    assert_equal(state.by_provider.grok.tpm_remaining, 25)
    assert_nil(state.by_provider.grok.last_error)
    assert_true(type(state.by_provider.grok.refreshed_at) == "number")
    assert_equal(state.five_hour_percent, 11, "Grok success must not clear Codex snapshot")
    assert_equal(state.weekly_percent, 22, "Grok success must not clear Codex snapshot")
    assert_true(updates >= 1)
  end)
  vim.uv = old_uv
  vim.loop = old_loop
end

do
  -- Regression: even if exit runs before a deferred stdout would have, sync on_stdout
  -- means pre-exit accumulation always wins when nvim delivers stdout first in-process.
  local state = {}
  local stdout_cb
  local exit_cb
  local monitor = token_monitor_mod.new({
    defaults = {
      enabled = true,
      refresh_ms = 60000,
      timeout_ms = 5000,
      grok = { enabled = true, model = "grok-4.5", base_url = "https://api.x.ai/v1" },
    },
    state = state,
    get_config = function()
      return { token_monitor = { grok = { api_key = "k" } } }
    end,
    is_running = function()
      return true
    end,
    json_encode = function()
      return "{}"
    end,
    on_update = function() end,
  })

  local old_uv = vim.uv
  local old_loop = vim.loop
  vim.uv = nil
  vim.loop = nil
  h.with_stubs({
    {
      target = vim,
      key = "schedule_wrap",
      value = function(fn)
        return fn
      end,
    },
    {
      target = vim.fn,
      key = "executable",
      value = function()
        return 1
      end,
    },
    {
      target = vim.fn,
      key = "jobstart",
      value = function(_, opts)
        stdout_cb = opts.on_stdout
        exit_cb = opts.on_exit
        return 7
      end,
    },
  }, function()
    assert_true(monitor:refresh(false, { agent_provider = "grok" }))
    -- Deliver headers synchronously (as production on_stdout now does).
    stdout_cb(nil, {
      "HTTP/1.1 200 OK",
      "x-ratelimit-limit-tokens: 200",
      "x-ratelimit-remaining-tokens: 50",
      "x-ratelimit-limit-requests: 40",
      "x-ratelimit-remaining-requests: 10",
      "",
    })
    exit_cb(nil, 0)
    assert_equal(state.tpm_percent, 75)
    assert_equal(state.rpm_percent, 75)
    assert_equal(state.tpm_remaining, 50)
    assert_equal(state.usage_provider, "grok")
  end)
  vim.uv = old_uv
  vim.loop = old_loop
end

do
  local controller = {
    state = {
      mission_dashboard_items = {
        [4] = { kind = "role", entry = { agent_provider = "grok" } },
        [6] = { kind = "role", entry = { agent_provider = "codex" } },
      },
    },
    selected_item = function()
      return { kind = "role", entry = { agent_provider = "grok" } }
    end,
  }
  assert_equal(dashboard_render.dashboard_token_agent_provider(controller), "grok", "selected role wins")

  controller.selected_item = function()
    return nil
  end
  assert_equal(dashboard_render.dashboard_token_agent_provider(controller), "codex", "any codex role wins when unselected")

  controller.state.mission_dashboard_items = {
    [4] = { kind = "role", entry = { agent_provider = "grok" } },
  }
  assert_equal(dashboard_render.dashboard_token_agent_provider(controller), "grok", "grok-only dashboard")

  controller.state.mission_dashboard_items = {}
  controller.default_agent_provider = function()
    return "grok"
  end
  assert_equal(dashboard_render.dashboard_token_agent_provider(controller), "grok", "default provider fallback")
end

do
  local now_ms = 1000
  local refresh_calls = {}
  local controller = {
    state = {},
    token_usage_now_ms = function()
      return now_ms
    end,
    token_usage_refresh_ms = function()
      return 60000
    end,
    selected_item = function()
      return { kind = "role", entry = { agent_provider = "codex" } }
    end,
    refresh_token_usage = function(force, opts)
      table.insert(refresh_calls, { force = force, opts = opts })
      return true
    end,
  }

  assert_true(dashboard_render.refresh_dashboard_token_usage(controller, true))
  assert_equal(#refresh_calls, 1)
  assert_equal(refresh_calls[1].force, true)
  assert_equal(refresh_calls[1].opts.agent_provider, "codex")

  assert_true(dashboard_render.refresh_dashboard_token_usage(controller, true, { agent_provider = "grok" }))
  assert_equal(refresh_calls[2].opts.agent_provider, "grok", "explicit override should win")
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

  -- Other provider is not blocked by Codex throttle.
  controller.selected_item = function()
    return { kind = "role", entry = { agent_provider = "grok" } }
  end
  assert_true(dashboard_render.refresh_dashboard_token_usage(controller, false))
  assert_equal(refresh_calls, 5, "grok provider should refresh despite codex throttle")
end

do
  local state = {
    by_provider = {
      codex = { five_hour_percent = 11, weekly_percent = 22, last_error = nil },
      grok = {
        tpm_percent = 33,
        rpm_percent = 44,
        tpm_limit = 100,
        tpm_remaining = 67,
        rpm_limit = 100,
        rpm_remaining = 56,
        last_error = nil,
      },
    },
    usage_provider = "grok",
    tpm_percent = 33,
    rpm_percent = 44,
    tpm_limit = 100,
    tpm_remaining = 67,
    rpm_limit = 100,
    rpm_remaining = 56,
    five_hour_percent = 11,
    weekly_percent = 22,
  }
  local monitor = monitor_with_config({ codex_cmd = "codex" }, { state = state })
  assert_equal(monitor:label_for_provider("codex"), "usage | 5hr 11% | wk 22%")
  assert_equal(monitor:label_for_provider("grok"), "quota | tpm 33% · 67 left | rpm 44% · 56 left")
  assert_equal(monitor:label(), "quota | tpm 33% · 67 left | rpm 44% · 56 left", "active snapshot follows usage_provider")
end

do
  local state = { by_provider = { codex = {}, grok = {} } }
  local monitor = monitor_with_config({ codex_cmd = "codex" }, { state = state })
  monitor:write_provider_cache("codex", {
    five_hour_percent = 7,
    weekly_percent = 8,
    last_error = nil,
  })
  monitor:write_provider_cache("grok", {
    tpm_percent = 1,
    rpm_percent = 2,
    tpm_limit = 100,
    tpm_remaining = 99,
    rpm_limit = 50,
    rpm_remaining = 49,
    last_error = nil,
  })
  assert_equal(state.by_provider.codex.five_hour_percent, 7)
  assert_equal(state.by_provider.grok.tpm_percent, 1)
  assert_equal(monitor:label_for_provider("codex"), "usage | 5hr 7% | wk 8%")
  assert_equal(monitor:label_for_provider("grok"), "quota | tpm 1% · 99 left | rpm 2% · 49 left")
end

do
  local calls = {}
  local controller = {
    state = {
      mission_dashboard_token_usage_provider = "codex",
      mission_dashboard_selectable_rows = { 4, 6 },
      mission_dashboard_selected_row = 4,
      mission_dashboard_items = {
        [4] = { kind = "role", entry = { agent_provider = "codex" } },
        [6] = { kind = "role", entry = { agent_provider = "grok" } },
      },
      mission_dashboard_win = 1,
    },
    is_valid_win = function()
      return true
    end,
    selected_item = function(self)
      local row = self.state.mission_dashboard_selected_row
      return self.state.mission_dashboard_items[row]
    end,
    selected_row = function(self)
      return self.state.mission_dashboard_selected_row
    end,
    capture_stationary_output_preview_anchor = function()
      return nil
    end,
    dashboard_token_agent_provider = function(self)
      return dashboard_render.dashboard_token_agent_provider(self)
    end,
    refresh_dashboard_token_usage = function(_, force)
      table.insert(calls, { "token", force })
      return true
    end,
    render_dashboard = function(_, opts)
      table.insert(calls, { "render", opts and opts.skip_token_refresh })
      return true
    end,
  }
  local selection = require("codux.mission_dashboard_selection")
  assert_true(selection.move_mission_selection(controller, 1))
  assert_equal(controller.state.mission_dashboard_selected_row, 6)
  assert_equal(calls[1][1], "token")
  assert_true(calls[1][2], "provider change should force token refresh")
  assert_equal(calls[2][1], "render")
  assert_true(calls[2][2], "forced token path skips second refresh in render")
end

print("token_monitor_spec.lua: ok")
