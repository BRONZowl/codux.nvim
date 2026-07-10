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

function M.label(usage, opts)
  opts = type(opts) == "table" and opts or {}
  usage = type(usage) == "table" and usage or {}

  if opts.enabled == false then
    return ""
  end
  if opts.show_when_not_running ~= true and (opts.running == false or opts.mode == "not running") then
    return ""
  end

  local five_hour = usage.five_hour_percent
  local weekly = usage.weekly_percent
  local five_hour_label = five_hour ~= nil and (tostring(five_hour) .. "%") or "--%"
  local weekly_label = weekly ~= nil and (tostring(weekly) .. "%") or "--%"

  local label = "usage | 5hr " .. five_hour_label .. " | wk " .. weekly_label
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
