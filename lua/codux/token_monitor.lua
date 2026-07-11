local M = {}
M.__index = M

local json = require("codux.json")
local token_usage = require("codux.token_usage")
local providers = require("codux.providers")
local util = require("codux.util")

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local monitor = {
    get_config = opts.get_config,
    defaults = type(opts.defaults) == "table" and opts.defaults or {},
    state = type(opts.state) == "table" and opts.state or {},
    is_running = type(opts.is_running) == "function" and opts.is_running or function()
      return false
    end,
    get_mode = type(opts.get_mode) == "function" and opts.get_mode or function()
      return nil
    end,
    get_agent_provider = type(opts.get_agent_provider) == "function" and opts.get_agent_provider or function()
      return "codex"
    end,
    command_util = type(opts.command_util) == "table" and opts.command_util or require("codux.command"),
    json_encode = type(opts.json_encode) == "function" and opts.json_encode or json.encode,
    json_decode = type(opts.json_decode) == "function" and opts.json_decode or json.decode,
    on_update = type(opts.on_update) == "function" and opts.on_update or util.noop,
    read_file = type(opts.read_file) == "function" and opts.read_file or function(path)
      local ok, lines = pcall(vim.fn.readfile, path)
      if not ok or type(lines) ~= "table" then
        return nil
      end
      return table.concat(lines, "\n")
    end,
    env = type(opts.env) == "table" and opts.env or vim.env,
  }

  return setmetatable(monitor, M)
end

function M:config()
  local config = type(self.get_config) == "function" and self.get_config() or {}
  if type(config) ~= "table" then
    config = {}
  end

  if config.token_monitor == false then
    return { enabled = false }
  end

  local defaults = type(self.defaults) == "table" and self.defaults or {}
  if type(config.token_monitor) ~= "table" then
    return defaults
  end

  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), config.token_monitor)
end

function M:enabled()
  return self:config().enabled ~= false
end

function M:refresh_ms()
  local value = tonumber(self:config().refresh_ms)
  if value == nil or value < 10000 then
    return self.defaults.refresh_ms
  end

  return value
end

function M:timeout_ms()
  local value = tonumber(self:config().timeout_ms)
  if value == nil or value < 1000 then
    return self.defaults.timeout_ms
  end

  return value
end

function M:grok_config()
  local monitor = self:config()
  if monitor.grok == false then
    return { enabled = false }
  end
  if type(monitor.grok) ~= "table" then
    local defaults = type(self.defaults) == "table" and self.defaults.grok or {}
    return type(defaults) == "table" and defaults or { enabled = true }
  end
  return monitor.grok
end

function M:ensure_by_provider()
  if type(self.state.by_provider) ~= "table" then
    self.state.by_provider = { codex = {}, grok = {} }
  end
  if type(self.state.by_provider.codex) ~= "table" then
    self.state.by_provider.codex = {}
  end
  if type(self.state.by_provider.grok) ~= "table" then
    self.state.by_provider.grok = {}
  end
  return self.state.by_provider
end

function M:provider_cache(provider)
  provider = providers.normalize_provider(provider) or "codex"
  local caches = self:ensure_by_provider()
  return caches[provider] or caches.codex, provider
end

function M:label(opts)
  opts = type(opts) == "table" and opts or {}
  local running = opts.running
  if running == nil then
    running = self.is_running()
  end
  local mode = opts.mode
  if mode == nil then
    mode = self.get_mode()
  end

  return token_usage.label(self.state, {
    enabled = self:enabled(),
    running = running,
    mode = mode,
    show_when_not_running = opts.show_when_not_running,
    show_error = opts.show_error,
    provider = self.state.usage_provider,
  })
end

--- Label usage for a specific agent provider using the per-provider cache.
function M:label_for_provider(provider, opts)
  opts = type(opts) == "table" and opts or {}
  local cached, normalized = self:provider_cache(provider)
  return token_usage.label({
    five_hour_percent = cached.five_hour_percent,
    weekly_percent = cached.weekly_percent,
    tpm_percent = cached.tpm_percent,
    rpm_percent = cached.rpm_percent,
    last_error = cached.last_error,
    usage_provider = normalized,
  }, {
    enabled = self:enabled(),
    running = opts.running,
    mode = opts.mode,
    show_when_not_running = opts.show_when_not_running,
    show_error = opts.show_error,
    provider = normalized,
  })
end

function M:provider_refreshed_at(provider)
  local cached = self:provider_cache(provider)
  return tonumber(cached.refreshed_at)
end

function M:stop_timeout_timer()
  local timer = self.state.timeout_timer
  self.state.timeout_timer = nil
  if timer then
    pcall(timer.stop, timer)
    pcall(timer.close, timer)
  end
end

function M:clear_usage()
  self.state.five_hour_percent = nil
  self.state.weekly_percent = nil
  self.state.tpm_percent = nil
  self.state.rpm_percent = nil
  self.state.usage_provider = nil
  self.state.last_error = nil
  self.state.in_flight_provider = nil
end

local function now_ms()
  return util.now_ms()
end

function M:write_provider_cache(provider, fields)
  local cached, normalized = self:provider_cache(provider)
  fields = type(fields) == "table" and fields or {}
  for key, value in pairs(fields) do
    cached[key] = value
  end
  if fields.refreshed_at == nil then
    cached.refreshed_at = now_ms()
  end
  return normalized
end

function M:complete_request(job_id, usage, error_message, stop_job)
  if self.state.job_id ~= job_id then
    return
  end

  local flight_provider = providers.normalize_provider(self.state.in_flight_provider)
    or providers.normalize_provider(self.state.usage_provider)
    or "codex"

  self:stop_timeout_timer()
  self.state.job_id = nil
  self.state.in_flight = false
  self.state.in_flight_provider = nil
  self.state.stdout = ""
  self.state.initialized = false

  if type(usage) == "table" then
    if usage.usage_provider == "grok" or usage.tpm_percent ~= nil or usage.rpm_percent ~= nil then
      self.state.tpm_percent = usage.tpm_percent
      self.state.rpm_percent = usage.rpm_percent
      self.state.usage_provider = "grok"
      self:write_provider_cache("grok", {
        tpm_percent = usage.tpm_percent,
        rpm_percent = usage.rpm_percent,
        last_error = nil,
      })
    else
      self.state.five_hour_percent = usage.five_hour_percent
      self.state.weekly_percent = usage.weekly_percent
      self.state.usage_provider = "codex"
      self:write_provider_cache("codex", {
        five_hour_percent = usage.five_hour_percent,
        weekly_percent = usage.weekly_percent,
        last_error = nil,
      })
    end
    self.state.last_error = nil
  elseif type(error_message) == "string" and error_message ~= "" then
    self.state.last_error = error_message
    self:write_provider_cache(flight_provider, {
      last_error = error_message,
    })
  end

  if stop_job then
    pcall(vim.fn.jobstop, job_id)
  end

  self.on_update()
end

function M:send_rpc(job_id, payload)
  local encoded = self.json_encode(payload)
  local ok, sent = pcall(vim.fn.chansend, job_id, encoded .. "\n")
  return ok and sent ~= 0
end

function M:process_message(job_id, message)
  if self.state.job_id ~= job_id then
    return
  end

  if message.id == 1 and not self.state.initialized then
    if type(message.result) ~= "table" then
      self:complete_request(job_id, nil, "Codex app-server initialize failed", true)
      return
    end

    self.state.initialized = true
    self:send_rpc(job_id, {
      jsonrpc = "2.0",
      method = "initialized",
      params = {},
    })
    if not self:send_rpc(job_id, {
      jsonrpc = "2.0",
      id = 2,
      method = "account/rateLimits/read",
      params = vim.NIL,
    }) then
      self:complete_request(job_id, nil, "Failed to request Codex token usage", true)
    end
    return
  end

  if message.id ~= 2 then
    return
  end

  if type(message.error) == "table" then
    self:complete_request(job_id, nil, tostring(message.error.message or "Codex token usage request failed"), true)
    return
  end

  local usage = token_usage.parse_response(message)
  if usage == nil then
    self:complete_request(job_id, nil, "Codex token usage response was unavailable", true)
    return
  end

  self:complete_request(job_id, usage, nil, true)
end

function M:handle_stdout(job_id, data)
  if self.state.job_id ~= job_id or type(data) ~= "table" then
    return
  end

  local chunk = table.concat(data, "\n")
  if chunk == "" then
    return
  end

  self.state.stdout = (self.state.stdout or "") .. chunk

  while true do
    local newline = self.state.stdout:find("\n", 1, true)
    if not newline then
      break
    end

    local line = self.state.stdout:sub(1, newline - 1)
    self.state.stdout = self.state.stdout:sub(newline + 1)
    local message = self.json_decode(line)
    if type(message) == "table" then
      self:process_message(job_id, message)
    end
  end
end

function M:app_server_command()
  local config = type(self.get_config) == "function" and self.get_config() or {}
  if type(config) ~= "table" then
    config = {}
  end

  local monitor = self:config()
  if monitor.codex_cmd ~= nil then
    local error_message = self.command_util.error(monitor.codex_cmd, "Codex token monitor command")
    if error_message then
      return nil, nil, error_message
    end

    return self.command_util.with_args(monitor.codex_cmd, { "app-server", "--stdio" }),
      self.command_util.executable(monitor.codex_cmd),
      nil
  end

  local executable = self.command_util.executable(providers.command(config, "codex", "default"))
  if executable == nil or executable == "" then
    executable = "codex"
  end

  return { executable, "app-server", "--stdio" }, executable, nil
end

function M.resolve_grok_api_key(opts)
  opts = type(opts) == "table" and opts or {}
  local grok = type(opts.grok) == "table" and opts.grok or {}
  if type(grok.api_key) == "string" and grok.api_key ~= "" then
    return grok.api_key
  end

  local env = type(opts.env) == "table" and opts.env or {}
  if type(env.XAI_API_KEY) == "string" and env.XAI_API_KEY ~= "" then
    return env.XAI_API_KEY
  end
  if type(env.GROK_API_KEY) == "string" and env.GROK_API_KEY ~= "" then
    return env.GROK_API_KEY
  end

  local auth_file = grok.auth_file
  if type(auth_file) ~= "string" or auth_file == "" then
    local home = type(env.HOME) == "string" and env.HOME or (vim.env and vim.env.HOME) or ""
    if home ~= "" then
      auth_file = home .. "/.grok/auth.json"
    end
  end
  if type(auth_file) ~= "string" or auth_file == "" then
    return nil, "Grok credentials not found"
  end

  local read_file = type(opts.read_file) == "function" and opts.read_file
  local content = read_file and read_file(auth_file) or nil
  if type(content) ~= "string" or content == "" then
    return nil, "Grok credentials not found"
  end

  local decoded = (opts.json_decode or json.decode)(content)
  if type(decoded) ~= "table" then
    return nil, "Grok credentials file is invalid"
  end

  for _, entry in pairs(decoded) do
    if type(entry) == "table" and type(entry.key) == "string" and entry.key ~= "" then
      return entry.key
    end
  end

  return nil, "Grok credentials not found"
end

function M:refresh_grok(force)
  local grok = self:grok_config()
  if grok.enabled == false then
    self.state.tpm_percent = nil
    self.state.rpm_percent = nil
    self.state.usage_provider = "grok"
    self.state.last_error = nil
    self:write_provider_cache("grok", {
      tpm_percent = nil,
      rpm_percent = nil,
      last_error = nil,
    })
    self.on_update()
    return false
  end

  if self.state.in_flight then
    if not force then
      return false, "in_flight"
    end
    self:complete_request(self.state.job_id, nil, "Grok token usage request was replaced", true)
  end

  local api_key, auth_error = M.resolve_grok_api_key({
    grok = grok,
    env = self.env,
    read_file = self.read_file,
    json_decode = self.json_decode,
  })
  if not api_key then
    self.state.usage_provider = "grok"
    self.state.tpm_percent = nil
    self.state.rpm_percent = nil
    self.state.last_error = auth_error or "Grok credentials not found"
    self:write_provider_cache("grok", {
      tpm_percent = nil,
      rpm_percent = nil,
      last_error = self.state.last_error,
    })
    self.on_update()
    return false
  end

  if vim.fn.executable("curl") ~= 1 then
    self.state.usage_provider = "grok"
    self.state.last_error = "curl not found on PATH (required for Grok token usage)"
    self:write_provider_cache("grok", {
      last_error = self.state.last_error,
    })
    self.on_update()
    return false
  end

  local base_url = type(grok.base_url) == "string" and grok.base_url ~= "" and grok.base_url or "https://api.x.ai/v1"
  base_url = base_url:gsub("/+$", "")
  local model = type(grok.model) == "string" and grok.model ~= "" and grok.model or "grok-4.5"
  local payload = self.json_encode({
    model = model,
    messages = { { role = "user", content = "." } },
    max_tokens = 1,
  })

  local command = {
    "curl",
    "-sS",
    "-D",
    "-",
    "-o",
    "/dev/null",
    "-X",
    "POST",
    base_url .. "/chat/completions",
    "-H",
    "Authorization: Bearer " .. api_key,
    "-H",
    "Content-Type: application/json",
    "-H",
    "Accept: application/json",
    "-H",
    "User-Agent: codux.nvim",
    "--data-binary",
    payload,
  }

  self.state.in_flight = true
  self.state.in_flight_provider = "grok"
  self.state.stdout = ""
  self.state.initialized = false
  self.state.last_error = nil
  self.state.usage_provider = "grok"

  local job_id
  -- Accumulate stdout synchronously so a scheduled on_exit never races an empty buffer.
  -- Only complete_request / UI work is deferred via schedule_wrap.
  job_id = vim.fn.jobstart(command, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if self.state.job_id ~= job_id or type(data) ~= "table" then
        return
      end
      self.state.stdout = (self.state.stdout or "") .. table.concat(data, "\n")
    end,
    on_exit = vim.schedule_wrap(function(_, code)
      if self.state.job_id ~= job_id then
        return
      end
      local raw = self.state.stdout or ""
      local usage = token_usage.parse_grok_headers(raw)
      if usage then
        self:complete_request(job_id, usage, nil, false)
        return
      end
      local message = "Grok token usage response was unavailable"
      if code ~= 0 then
        message = "Grok token usage request exited with code " .. tostring(code)
      elseif raw:find("401", 1, true) or raw:lower():find("unauthenticated", 1, true) then
        message = "Grok token usage authentication failed"
      end
      self:complete_request(job_id, nil, message, false)
    end),
  })

  if type(job_id) ~= "number" or job_id <= 0 then
    self.state.job_id = nil
    self.state.in_flight = false
    self.state.in_flight_provider = nil
    self.state.last_error = "Failed to start Grok token usage probe"
    self:write_provider_cache("grok", { last_error = self.state.last_error })
    self.on_update()
    return false
  end

  self.state.job_id = job_id

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if timer then
    self.state.timeout_timer = timer
    timer:start(self:timeout_ms(), 0, vim.schedule_wrap(function()
      self:complete_request(job_id, nil, "Grok token usage request timed out", true)
    end))
  end

  return true
end

--- Codex path: preserved behavior (app-server rate limits).
function M:refresh_codex(force)
  if self.state.in_flight then
    if not force then
      return false, "in_flight"
    end
    self:complete_request(self.state.job_id, nil, "Codex token usage request was replaced", true)
  end

  local command, executable, command_error = self:app_server_command()
  if command_error then
    self.state.last_error = command_error
    self.state.usage_provider = "codex"
    self:write_provider_cache("codex", { last_error = command_error })
    self.on_update()
    return false
  end

  if vim.fn.executable(executable) ~= 1 then
    self.state.last_error = "Codex CLI not found on PATH"
    self.state.usage_provider = "codex"
    self:write_provider_cache("codex", { last_error = self.state.last_error })
    self.on_update()
    return false
  end

  self.state.in_flight = true
  self.state.in_flight_provider = "codex"
  self.state.stdout = ""
  self.state.initialized = false
  self.state.last_error = nil
  self.state.usage_provider = "codex"

  local job_id
  job_id = vim.fn.jobstart(command, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = vim.schedule_wrap(function(_, data)
      self:handle_stdout(job_id, data)
    end),
    on_exit = vim.schedule_wrap(function(_, code)
      if self.state.job_id == job_id then
        self:complete_request(job_id, nil, "Codex token usage request exited with code " .. tostring(code), false)
      end
    end),
  })

  if type(job_id) ~= "number" or job_id <= 0 then
    self.state.job_id = nil
    self.state.in_flight = false
    self.state.in_flight_provider = nil
    self.state.last_error = "Failed to start Codex app-server"
    self:write_provider_cache("codex", { last_error = self.state.last_error })
    self.on_update()
    return false
  end

  self.state.job_id = job_id

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if timer then
    self.state.timeout_timer = timer
    timer:start(self:timeout_ms(), 0, vim.schedule_wrap(function()
      self:complete_request(job_id, nil, "Codex token usage request timed out", true)
    end))
  end

  if not self:send_rpc(job_id, {
    jsonrpc = "2.0",
    id = 1,
    method = "initialize",
    params = {
      clientInfo = {
        name = "codux.nvim",
        version = "0",
      },
      capabilities = {
        experimentalApi = true,
      },
    },
  }) then
    self:complete_request(job_id, nil, "Failed to initialize Codex app-server", true)
    return false
  end

  return true
end

function M:refresh(force, opts)
  opts = type(opts) == "table" and opts or {}
  local require_running = opts.require_running ~= false
  if not self:enabled() or (require_running and not self.is_running()) then
    return false
  end

  local agent_provider = opts.agent_provider
  if agent_provider == nil then
    agent_provider = self.get_agent_provider()
  end
  agent_provider = providers.normalize_provider(agent_provider) or "codex"

  if not providers.token_usage_supported(agent_provider) then
    self:clear_usage()
    self.state.last_error = nil
    self.on_update()
    return false
  end

  if agent_provider == "grok" then
    return self:refresh_grok(force)
  end

  return self:refresh_codex(force)
end

function M:start()
  if not self:enabled() or not self.is_running() then
    return
  end

  if self.state.refresh_timer then
    self:refresh(true)
    return
  end

  self:refresh(false)

  local loop = vim.uv or vim.loop
  local timer = loop and loop.new_timer()
  if not timer then
    return
  end

  self.state.refresh_timer = timer
  timer:start(self:refresh_ms(), self:refresh_ms(), vim.schedule_wrap(function()
    self:refresh(false)
  end))
end

function M:stop()
  local refresh_timer = self.state.refresh_timer
  self.state.refresh_timer = nil
  if refresh_timer then
    pcall(refresh_timer.stop, refresh_timer)
    pcall(refresh_timer.close, refresh_timer)
  end

  self:stop_timeout_timer()

  local job_id = self.state.job_id
  self.state.job_id = nil
  self.state.in_flight = false
  self.state.stdout = ""
  self.state.initialized = false
  -- Keep last-known percentages so mission dashboard / which-key can still
  -- show usage after the terminal exits; only cancel in-flight work.
  self.state.last_error = nil
  if job_id then
    pcall(vim.fn.jobstop, job_id)
  end
end

return M
