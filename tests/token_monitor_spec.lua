local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_table_equal = h.assert_table_equal

local token_monitor_mod = require("codux.token_monitor")
local token_usage = require("codux.token_usage")
local dashboard_render = require("codux.mission_dashboard_render")
local providers = require("codux.providers")

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
    get_agent_provider = opts.get_agent_provider or function()
      return "codex"
    end,
    on_update = opts.on_update or function() end,
  })
end

do
  local monitor = monitor_with_config({
    codex_cmd = 'codex -s workspace-write -a on-request -c approvals_reviewer="user"',
  })
  local command, executable, error_message = monitor:app_server_command()

  assert_equal(error_message, nil)
  assert_equal(executable, "codex")
  assert_table_equal(command, { "codex", "app-server", "--stdio" })
end

do
  local monitor = monitor_with_config({
    codex_cmd = "codex",
    token_monitor = {
      codex_cmd = { "codex-token", "--profile", "usage" },
    },
  })
  local command, executable, error_message = monitor:app_server_command()

  assert_equal(error_message, nil)
  assert_equal(executable, "codex-token")
  assert_table_equal(command, { "codex-token", "--profile", "usage", "app-server", "--stdio" })
end

do
  assert_equal(token_usage.normalize_percent(12.4), 12)
  assert_equal(token_usage.normalize_percent(12.6), 13)
  assert_equal(token_usage.normalize_percent(-5), 0)
  assert_equal(token_usage.normalize_percent(150), 100)
  assert_nil(token_usage.normalize_percent("nope"))

  local usage = token_usage.parse_response({
    result = {
      rateLimitsByLimitId = {
        codex = {
          primary = { windowDurationMins = 300, usedPercent = 12.4 },
          secondary = { windowDurationMins = 10080, usedPercent = 34.6 },
        },
      },
    },
  })
  assert_equal(usage.five_hour_percent, 12)
  assert_equal(usage.weekly_percent, 35)
  assert_nil(token_usage.parse_response({ result = {} }))
end

do
  assert_equal(token_usage.label({ five_hour_percent = 1, weekly_percent = 2 }), "usage | 5hr 1% | wk 2%")
  assert_equal(
    token_usage.label({ last_error = "timeout" }, { show_error = true }),
    "usage | 5hr --% | wk --% (unavailable)"
  )
  assert_equal(token_usage.label({}, { enabled = false }), "")
  assert_equal(token_usage.label({ five_hour_percent = 1 }, { running = false }), "")
end

do
  local monitor = monitor_with_config({ codex_cmd = "codex" }, {
    state = { five_hour_percent = 12, weekly_percent = 34 },
    is_running = function()
      return false
    end,
  })

  assert_equal(monitor:label({ running = false, mode = "not running" }), "")
  assert_equal(
    monitor:label({ running = false, mode = "not running", show_when_not_running = true }),
    "usage | 5hr 12% | wk 34%"
  )
  assert_equal(monitor:label_for_provider("grok", { show_when_not_running = true }), "")
end

do
  local monitor = monitor_with_config({ token_monitor = false }, {
    state = { five_hour_percent = 12, weekly_percent = 34 },
  })
  assert_equal(monitor:label({ show_when_not_running = true }), "")
  assert_false(monitor:refresh(false))
end

do
  assert_true(providers.token_usage_supported("codex"))
  assert_false(providers.token_usage_supported("grok"))
  assert_false(providers.token_usage_supported("nope"))
  assert_false(providers.token_usage_supported(nil))
end

-- Grok monitoring is intentionally absent: neither direct refresh nor timer startup
-- may invoke jobstart, even when legacy Grok monitor configuration remains.
do
  local jobstarts = 0
  local state = { five_hour_percent = 7, weekly_percent = 9 }
  local monitor = monitor_with_config({
    token_monitor = {
      grok = {
        api_key = "legacy-key",
        refresh_ms = 5000,
      },
    },
  }, {
    state = state,
    get_agent_provider = function()
      return "grok"
    end,
  })

  h.with_stubs({
    {
      target = vim.fn,
      key = "jobstart",
      value = function()
        jobstarts = jobstarts + 1
        return 99
      end,
    },
  }, function()
    assert_false(monitor:refresh(false, { require_running = false, agent_provider = "grok" }))
    assert_nil(monitor:start())
  end)

  assert_equal(jobstarts, 0, "Grok must never start a monitoring process")
  assert_equal(state.five_hour_percent, 7, "Grok refresh must not clear the Codex snapshot")
  assert_equal(state.weekly_percent, 9)
end

-- The Codex monitor is metadata-only. Lock the exact app-server RPC sequence so
-- no thread/start, turn/start, prompt, completion, or other inference call can slip in.
do
  local state = {}
  local started_command
  local job_options
  local sent = {}
  local stopped = {}
  local monitor = token_monitor_mod.new({
    defaults = { enabled = true, refresh_ms = 60000, timeout_ms = 5000 },
    state = state,
    get_config = function()
      return { codex_cmd = "codex" }
    end,
    is_running = function()
      return true
    end,
    get_agent_provider = function()
      return "codex"
    end,
    json_encode = function(payload)
      table.insert(sent, payload)
      return "{}"
    end,
    json_decode = function()
      return nil
    end,
    on_update = function() end,
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
      target = vim,
      key = "uv",
      value = nil,
    },
    {
      target = vim,
      key = "loop",
      value = nil,
    },
    {
      target = vim.fn,
      key = "executable",
      value = function(name)
        return name == "codex" and 1 or 0
      end,
    },
    {
      target = vim.fn,
      key = "jobstart",
      value = function(command, opts)
        started_command = command
        job_options = opts
        return 42
      end,
    },
    {
      target = vim.fn,
      key = "chansend",
      value = function()
        return 1
      end,
    },
    {
      target = vim.fn,
      key = "jobstop",
      value = function(job_id)
        table.insert(stopped, job_id)
        return 1
      end,
    },
  }, function()
    assert_true(monitor:refresh(false))
    assert_table_equal(started_command, { "codex", "app-server", "--stdio" })
    assert_true(type(job_options.on_stdout) == "function")

    monitor:process_message(42, { id = 1, result = {} })
    monitor:process_message(42, {
      id = 2,
      result = {
        rateLimits = {
          primary = { windowDurationMins = 300, usedPercent = 8 },
          secondary = { windowDurationMins = 10080, usedPercent = 13 },
        },
      },
    })
  end)

  assert_equal(#sent, 3)
  assert_equal(sent[1].method, "initialize")
  assert_equal(sent[2].method, "initialized")
  assert_equal(sent[3].method, "account/rateLimits/read")
  assert_equal(sent[3].params, vim.NIL)
  for _, payload in ipairs(sent) do
    local method = tostring(payload.method or "")
    assert_false(method:find("thread/", 1, true) ~= nil)
    assert_false(method:find("turn/", 1, true) ~= nil)
  end
  assert_equal(state.five_hour_percent, 8)
  assert_equal(state.weekly_percent, 13)
  assert_true(type(state.refreshed_at) == "number")
  assert_table_equal(stopped, { 42 })
end

do
  local refreshes = 0
  local controller = {
    state = { mission_dashboard = {} },
    token_usage_now_ms = function()
      return 100000
    end,
    token_usage_refresh_ms = function()
      return 60000
    end,
    token_usage_provider_refreshed_at = function()
      return nil
    end,
    refresh_token_usage = function()
      refreshes = refreshes + 1
      return true
    end,
  }

  assert_false(dashboard_render.refresh_dashboard_token_usage(controller, true, { agent_provider = "grok" }))
  assert_equal(refreshes, 0, "Grok dashboard rows must not request usage")
  assert_true(dashboard_render.refresh_dashboard_token_usage(controller, true, { agent_provider = "codex" }))
  assert_equal(refreshes, 1)
end

print("token_monitor_spec.lua: ok")
