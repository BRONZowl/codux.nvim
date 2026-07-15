--- Shared redaction helpers for health, notify, doctor, and optional prompt scrubbing.
local command_util = require("codux.command")

local M = {}

-- Lua patterns do not support `|` alternation; check each fragment separately.
local SECRET_KEY_PATTERNS = {
  "api[_%-]?key",
  "access[_%-]?token",
  "refresh[_%-]?token",
  "auth[_%-]?token",
  "oauth[_%-]?token",
  "client[_%-]?secret",
  "private[_%-]?key",
  "password",
  "passwd",
  "secret",
  "authorization",
  "bearer",
}

local SECRET_ENV_NAMES = {
  "OPENAI_API_KEY",
  "ANTHROPIC_API_KEY",
  "XAI_API_KEY",
  "GROK_API_KEY",
  "CODEX_API_KEY",
  "GITHUB_TOKEN",
  "GH_TOKEN",
  "AWS_SECRET_ACCESS_KEY",
  "AWS_SESSION_TOKEN",
}

local MASK = "[REDACTED]"

-- Session-local counters (no secret content stored).
local stats = {
  text_calls = 0,
  text_redacted = 0,
  prompt_calls = 0,
  prompt_scrubbed = 0,
  session_started_at = nil,
  last_redact_at = nil,
  last_prompt_scrub_at = nil,
}

local function now_unix()
  return os.time()
end

local function mark_session_started()
  if stats.session_started_at == nil then
    stats.session_started_at = now_unix()
  end
end

--- Integer percent rate, or nil when there are no samples.
local function rate_percent(numerator, denominator)
  numerator = tonumber(numerator) or 0
  denominator = tonumber(denominator) or 0
  if denominator <= 0 then
    return nil
  end
  return math.floor((100 * numerator) / denominator)
end

function M.reset_audit_stats()
  stats = {
    text_calls = 0,
    text_redacted = 0,
    prompt_calls = 0,
    prompt_scrubbed = 0,
    session_started_at = nil,
    last_redact_at = nil,
    last_prompt_scrub_at = nil,
  }
end

--- Snapshot of redaction activity for health/doctor (counts + lazy rates).
function M.audit_stats()
  return {
    text_calls = stats.text_calls,
    text_redacted = stats.text_redacted,
    text_redaction_rate = rate_percent(stats.text_redacted, stats.text_calls),
    prompt_calls = stats.prompt_calls,
    prompt_scrubbed = stats.prompt_scrubbed,
    prompt_scrub_rate = rate_percent(stats.prompt_scrubbed, stats.prompt_calls),
    session_started_at = stats.session_started_at,
    last_redact_at = stats.last_redact_at,
    last_prompt_scrub_at = stats.last_prompt_scrub_at,
  }
end

function M.audit_scrubs_enabled(config)
  config = type(config) == "table" and config or {}
  local security = type(config.security) == "table" and config.security or {}
  return security.audit_scrubs == true
end

function M.is_secret_key(key)
  if type(key) ~= "string" then
    return false
  end
  local normalized = key:lower():gsub("%s+", "")
  for _, pattern in ipairs(SECRET_KEY_PATTERNS) do
    if normalized:match(pattern) then
      return true
    end
  end
  return false
end

function M.is_command_key(key)
  if type(key) ~= "string" then
    return false
  end
  return key == "codex_cmd"
    or key == "tmux_cmd"
    or key:match("_cmd$") ~= nil
    or key:match("_command$") ~= nil
end

function M.redact_command_value(value)
  local executable = command_util.executable(value)
  if type(executable) == "string" and executable ~= "" then
    return executable
  end
  if value == nil then
    return nil
  end
  return "[redacted]"
end

--- Mask common secret *values* embedded in free-form text.
--- opts.audit (default true) increments session counters when content changes.
function M.redact_text(value, opts)
  opts = type(opts) == "table" and opts or {}
  local audit = opts.audit ~= false

  if type(value) ~= "string" or value == "" then
    return value
  end

  if audit then
    mark_session_started()
    stats.text_calls = stats.text_calls + 1
  end

  local text = value

  -- Authorization: Bearer <token>
  text = text:gsub("([Bb]earer%s+)[%w%-%._~%+/=]+", "%1" .. MASK)

  -- Common API key prefixes
  text = text:gsub("sk%-[A-Za-z0-9_%-][A-Za-z0-9_%-][A-Za-z0-9_%-]+", MASK)
  text = text:gsub("xai%-[A-Za-z0-9_%-][A-Za-z0-9_%-][A-Za-z0-9_%-]+", MASK)
  text = text:gsub("ghp_[A-Za-z0-9_%-][A-Za-z0-9_%-][A-Za-z0-9_%-]+", MASK)
  text = text:gsub("gho_[A-Za-z0-9_%-][A-Za-z0-9_%-][A-Za-z0-9_%-]+", MASK)
  text = text:gsub("github_pat_[A-Za-z0-9_%-][A-Za-z0-9_%-][A-Za-z0-9_%-]+", MASK)

  -- flag-style: --api-key VALUE / -k VALUE / api_key=VALUE
  text = text:gsub("(%-%-?[%w_-]*[Aa][Pp][Ii][_%-]?[Kk][Ee][Yy][%s=]+)(%S+)", "%1" .. MASK)
  text = text:gsub("(%-%-?[%w_-]*[Tt][Oo][Kk][Ee][Nn][%s=]+)(%S+)", "%1" .. MASK)
  text = text:gsub("(%-%-?[%w_-]*[Ss][Ee][Cc][Rr][Ee][Tt][%s=]+)(%S+)", "%1" .. MASK)
  text = text:gsub("(%-%-?[%w_-]*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][%s=]+)(%S+)", "%1" .. MASK)

  -- ENV_NAME=value for known secret env names (quoted or bare)
  for _, name in ipairs(SECRET_ENV_NAMES) do
    text = text:gsub("(" .. name .. "%s*[=:]%s*)([\"']?)([^%s\"']+)(%2)", "%1%2" .. MASK .. "%4")
    text = text:gsub("(" .. name .. "%s*[=:]%s*)(%S+)", function(prefix, rest)
      if rest:sub(1, #MASK) == MASK then
        return prefix .. rest
      end
      return prefix .. MASK
    end)
  end

  if audit and text ~= value then
    stats.text_redacted = stats.text_redacted + 1
    stats.last_redact_at = now_unix()
  end

  return text
end

function M.contains_secret_value(value)
  if type(value) ~= "string" or value == "" then
    return false
  end
  -- Detection-only: do not bump audit counters.
  return M.redact_text(value, { audit = false }) ~= value
end

--- Deep-copy table with secret keys removed and command fields reduced to executables.
--- Optionally runs redact_text on string leaves when scrub_strings is true.
function M.redact_table(value, opts)
  opts = type(opts) == "table" and opts or {}
  local scrub_strings = opts.scrub_strings == true
  local reduce_commands = opts.reduce_commands ~= false

  local function walk(node, key)
    if M.is_secret_key(key) then
      return nil, true
    end

    if reduce_commands and M.is_command_key(key) then
      return M.redact_command_value(node), false
    end

    if type(node) == "string" then
      if scrub_strings then
        return M.redact_text(node), false
      end
      return node, false
    end

    if type(node) ~= "table" then
      return node, false
    end

    local out = {}
    for child_key, child_value in pairs(node) do
      local redacted, drop = walk(child_value, child_key)
      if not drop then
        out[child_key] = redacted
      end
    end
    return out, false
  end

  if type(value) ~= "table" then
    if type(value) == "string" and scrub_strings then
      return M.redact_text(value)
    end
    return value
  end

  local redacted = walk(value, nil)
  return type(redacted) == "table" and redacted or {}
end

--- Public plugin config for health/debug (commands → executables, secrets dropped).
function M.public_config(config)
  if type(config) ~= "table" then
    return {}
  end
  return M.redact_table(config, { reduce_commands = true, scrub_strings = false })
end

--- Whether security.scrub_prompts is enabled on a config table.
function M.scrub_prompts_enabled(config)
  config = type(config) == "table" and config or {}
  local security = type(config.security) == "table" and config.security or {}
  return security.scrub_prompts == true
end

--- Apply optional prompt scrubbing based on config.
function M.maybe_scrub_prompt(prompt, config)
  if type(prompt) ~= "string" then
    return prompt
  end
  mark_session_started()
  stats.prompt_calls = stats.prompt_calls + 1
  if not M.scrub_prompts_enabled(config) then
    return prompt
  end
  local scrubbed = M.redact_text(prompt)
  if scrubbed ~= prompt then
    stats.prompt_scrubbed = stats.prompt_scrubbed + 1
    stats.last_prompt_scrub_at = now_unix()
  end
  return scrubbed
end

local function format_ratio(label, redacted, calls, rate)
  if calls == 0 then
    return string.format("%s 0/0", label)
  end
  return string.format("%s %d/%d (%d%%)", label, redacted, calls, rate or 0)
end

--- One-line summary for doctor (no secret material).
function M.audit_summary_line(config)
  if not M.audit_scrubs_enabled(config) then
    return nil
  end
  local s = M.audit_stats()
  return "redact audit: "
    .. format_ratio("text", s.text_redacted, s.text_calls, s.text_redaction_rate)
    .. " · "
    .. format_ratio("prompts", s.prompt_scrubbed, s.prompt_calls, s.prompt_scrub_rate)
end

--- Scan provider commands for secret-like substrings (doctor warnings).
function M.provider_commands_with_secrets(config)
  config = type(config) == "table" and config or {}
  local findings = {}
  local providers_cfg = type(config.providers) == "table" and config.providers or {}

  local function check(label, command)
    if command == nil then
      return
    end
    local display = command_util.display(command)
    if type(display) == "string" and M.contains_secret_value(display) then
      table.insert(findings, {
        label = label,
        executable = command_util.executable(command) or "?",
        sample = M.redact_text(display),
      })
    end
  end

  for _, provider in ipairs({ "codex", "grok" }) do
    local entry = type(providers_cfg[provider]) == "table" and providers_cfg[provider] or {}
    check(provider .. ".default_cmd", entry.default_cmd or (provider == "codex" and config.codex_cmd or nil))
    check(provider .. ".auto_cmd", entry.auto_cmd or (provider == "codex" and config.workspace_auto_cmd or nil))
    check(provider .. ".danger_cmd", entry.danger_cmd or (provider == "codex" and config.danger_full_access_cmd or nil))
  end

  check("token_monitor.codex_cmd", type(config.token_monitor) == "table" and config.token_monitor.codex_cmd or nil)

  return findings
end

return M
