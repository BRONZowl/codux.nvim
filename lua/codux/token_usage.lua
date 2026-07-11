local M = {}

function M.normalize_percent(value)
  local percent = tonumber(value)
  if percent == nil then
    return nil
  end

  percent = math.floor(percent + 0.5)
  return math.min(100, math.max(0, percent))
end

local function parse_window(window, usage)
  if type(window) ~= "table" then
    return
  end

  local duration = tonumber(window.windowDurationMins)
  local percent = M.normalize_percent(window.usedPercent)
  if duration == nil or percent == nil then
    return
  end

  if duration == 300 then
    usage.five_hour_percent = percent
  elseif duration == 10080 then
    usage.weekly_percent = percent
  end
end

function M.parse_response(response)
  if type(response) ~= "table" then
    return nil
  end

  local result = type(response.result) == "table" and response.result or response
  local rate_limits = result.rateLimits
  if type(result.rateLimitsByLimitId) == "table" and type(result.rateLimitsByLimitId.codex) == "table" then
    rate_limits = result.rateLimitsByLimitId.codex
  end

  if type(rate_limits) ~= "table" then
    return nil
  end

  local usage = {
    five_hour_percent = nil,
    weekly_percent = nil,
  }

  parse_window(rate_limits.primary, usage)
  parse_window(rate_limits.secondary, usage)

  if usage.five_hour_percent == nil and usage.weekly_percent == nil then
    return nil
  end

  return usage
end

local function used_percent(limit, remaining)
  if type(limit) == "string" then
    limit = limit:match("^%s*(.-)%s*$")
  end
  if type(remaining) == "string" then
    remaining = remaining:match("^%s*(.-)%s*$")
  end
  limit = tonumber(limit)
  remaining = tonumber(remaining)
  if limit == nil or limit <= 0 or remaining == nil then
    return nil
  end
  local used = ((limit - remaining) / limit) * 100
  return M.normalize_percent(used)
end

local function header_value(headers, name)
  if type(headers) ~= "table" then
    return nil
  end
  local want = tostring(name or ""):lower()
  for key, value in pairs(headers) do
    if type(key) == "string" and key:lower() == want then
      if type(value) == "string" then
        return value:match("^%s*(.-)%s*$")
      end
      return value
    end
  end
  return nil
end

local function parse_header_line(line)
  line = tostring(line or ""):gsub("\r", "")
  if line == "" or line:match("^%s*$") then
    return nil, nil
  end
  -- Status lines: "HTTP/1.1 200 OK", "HTTP/2 200 "
  if line:match("^HTTP/") then
    return nil, nil
  end
  local name, value = line:match("^([^:]+):%s*(.-)%s*$")
  if not name or name == "" then
    return nil, nil
  end
  return name, value
end

--- Parse xAI rate-limit headers from a header map or raw HTTP header text.
function M.parse_grok_headers(headers)
  local map = headers
  if type(headers) == "string" then
    map = {}
    -- Accept both LF and CRLF dumps from curl -D -.
    local normalized = headers:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
      local name, value = parse_header_line(line)
      if name and value then
        map[name] = value
      end
    end
  end

  if type(map) ~= "table" then
    return nil
  end

  local tpm = used_percent(
    header_value(map, "x-ratelimit-limit-tokens"),
    header_value(map, "x-ratelimit-remaining-tokens")
  )
  local rpm = used_percent(
    header_value(map, "x-ratelimit-limit-requests"),
    header_value(map, "x-ratelimit-remaining-requests")
  )

  if tpm == nil and rpm == nil then
    return nil
  end

  return {
    tpm_percent = tpm,
    rpm_percent = rpm,
    usage_provider = "grok",
  }
end

local function percent_label(value)
  if value == nil then
    return "--%"
  end
  return tostring(value) .. "%"
end

function M.label(usage, opts)
  opts = type(opts) == "table" and opts or {}
  usage = type(usage) == "table" and usage or {}

  if opts.enabled == false then
    return ""
  end
  if opts.show_when_not_running ~= true and (opts.running == false or opts.mode == "not running") then
    return ""
  end

  local provider = opts.provider or usage.usage_provider
  if provider == "grok" then
    local label = "usage | tpm "
      .. percent_label(usage.tpm_percent)
      .. " | rpm "
      .. percent_label(usage.rpm_percent)
    if
      usage.tpm_percent == nil
      and usage.rpm_percent == nil
      and type(usage.last_error) == "string"
      and usage.last_error ~= ""
      and opts.show_error == true
    then
      label = label .. " (unavailable)"
    end
    return label
  end

  local five_hour = usage.five_hour_percent
  local weekly = usage.weekly_percent
  local label = "usage | 5hr " .. percent_label(five_hour) .. " | wk " .. percent_label(weekly)
  if
    five_hour == nil
    and weekly == nil
    and type(usage.last_error) == "string"
    and usage.last_error ~= ""
    and opts.show_error == true
  then
    label = label .. " (unavailable)"
  end
  return label
end

return M
