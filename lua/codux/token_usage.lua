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

local function parse_number(value)
  if type(value) == "string" then
    value = value:match("^%s*(.-)%s*$")
  end
  return tonumber(value)
end

local function used_percent(limit, remaining)
  limit = parse_number(limit)
  remaining = parse_number(remaining)
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

--- Compact absolute counts for rate-limit headroom (e.g. 53000000 -> "53.0M").
function M.format_count(value)
  value = parse_number(value)
  if value == nil then
    return nil
  end
  if value >= 1000000 then
    local millions = value / 1000000
    if millions >= 100 then
      return string.format("%.0fM", millions)
    end
    return string.format("%.1fM", millions)
  end
  if value >= 10000 then
    return string.format("%.1fk", value / 1000)
  end
  return tostring(math.floor(value + 0.5))
end

--- Parse xAI rate-limit headers from a header map or raw HTTP header text.
--- Note: xAI currently reports very large TPM ceilings (tens of millions). Small
--- real usage often still rounds to 0% used; absolute remaining is more useful.
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

  local tpm_limit = parse_number(header_value(map, "x-ratelimit-limit-tokens"))
  local tpm_remaining = parse_number(header_value(map, "x-ratelimit-remaining-tokens"))
  local rpm_limit = parse_number(header_value(map, "x-ratelimit-limit-requests"))
  local rpm_remaining = parse_number(header_value(map, "x-ratelimit-remaining-requests"))

  local tpm = used_percent(tpm_limit, tpm_remaining)
  local rpm = used_percent(rpm_limit, rpm_remaining)

  local has_tpm = tpm ~= nil or (tpm_limit ~= nil and tpm_limit > 0 and tpm_remaining ~= nil)
  local has_rpm = rpm ~= nil or (rpm_limit ~= nil and rpm_limit > 0 and rpm_remaining ~= nil)
  if not has_tpm and not has_rpm then
    return nil
  end

  return {
    tpm_percent = tpm,
    rpm_percent = rpm,
    tpm_limit = tpm_limit,
    tpm_remaining = tpm_remaining,
    rpm_limit = rpm_limit,
    rpm_remaining = rpm_remaining,
    usage_provider = "grok",
  }
end

local function percent_label(value)
  if value == nil then
    return "--%"
  end
  return tostring(value) .. "%"
end

local function grok_bucket_label(name, percent, remaining, limit)
  local rem = M.format_count(remaining)
  local lim = M.format_count(limit)
  if rem and lim then
    -- Prefer absolute remaining/limit: large xAI quotas stay at 0% until heavy load.
    if type(percent) == "number" and percent > 0 then
      return name .. " " .. tostring(percent) .. "% · " .. rem .. " left"
    end
    return name .. " " .. rem .. "/" .. lim
  end
  return name .. " " .. percent_label(percent)
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
    local label = "quota | "
      .. grok_bucket_label("tpm", usage.tpm_percent, usage.tpm_remaining, usage.tpm_limit)
      .. " | "
      .. grok_bucket_label("rpm", usage.rpm_percent, usage.rpm_remaining, usage.rpm_limit)
    if
      usage.tpm_percent == nil
      and usage.rpm_percent == nil
      and usage.tpm_remaining == nil
      and usage.rpm_remaining == nil
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
