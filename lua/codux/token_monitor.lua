local M = {}
M.__index = M

local token_usage = require("codux.token_usage")

local function default_json_encode(value)
  if vim.json and type(vim.json.encode) == "function" then
    return vim.json.encode(value)
  end

  return vim.fn.json_encode(value)
end

local function default_json_decode(value)
  local ok, decoded
  if vim.json and type(vim.json.decode) == "function" then
    ok, decoded = pcall(vim.json.decode, value)
  else
    ok, decoded = pcall(vim.fn.json_decode, value)
  end

  if ok then
    return decoded
  end

  return nil
end

local function noop() end

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
    command_util = type(opts.command_util) == "table" and opts.command_util or require("codux.command"),
    json_encode = type(opts.json_encode) == "function" and opts.json_encode or default_json_encode,
    json_decode = type(opts.json_decode) == "function" and opts.json_decode or default_json_decode,
    on_update = type(opts.on_update) == "function" and opts.on_update or noop,
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

  if type(config.token_monitor) ~= "table" then
    return self.defaults
  end

  return config.token_monitor
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
  })
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
  self.state.last_error = nil
end

function M:complete_request(job_id, usage, error_message, stop_job)
  if self.state.job_id ~= job_id then
    return
  end

  self:stop_timeout_timer()
  self.state.job_id = nil
  self.state.in_flight = false
  self.state.stdout = ""
  self.state.initialized = false

  if type(usage) == "table" then
    self.state.five_hour_percent = usage.five_hour_percent
    self.state.weekly_percent = usage.weekly_percent
    self.state.last_error = nil
  elseif type(error_message) == "string" and error_message ~= "" then
    self.state.last_error = error_message
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
  local executable = type(monitor.codex_cmd) == "string" and monitor.codex_cmd or self.command_util.executable(config.codex_cmd)
  if executable == nil or executable == "" then
    executable = "codex"
  end

  return { executable, "app-server", "--stdio" }, executable
end

function M:refresh(force)
  if not self:enabled() or not self.is_running() then
    return false
  end

  if self.state.in_flight then
    if not force then
      return false
    end
    self:complete_request(self.state.job_id, nil, "Codex token usage request was replaced", true)
  end

  local command, executable = self:app_server_command()
  if vim.fn.executable(executable) ~= 1 then
    self.state.last_error = "Codex CLI not found on PATH"
    self.on_update()
    return false
  end

  self.state.in_flight = true
  self.state.stdout = ""
  self.state.initialized = false
  self.state.last_error = nil

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
    self.state.last_error = "Failed to start Codex app-server"
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
  self:clear_usage()
  if job_id then
    pcall(vim.fn.jobstop, job_id)
  end
end

return M
