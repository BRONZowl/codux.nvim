local M = {}

function M.noop() end

function M.notify(message, level)
  local log_levels = type(vim) == "table" and type(vim.log) == "table" and vim.log.levels or nil
  local default_level = log_levels and log_levels.INFO or 2
  if type(message) == "string" and message ~= "" then
    local ok, redact = pcall(require, "codux.redact")
    if ok and type(redact.redact_text) == "function" then
      message = redact.redact_text(message)
    end
  end
  if type(vim) == "table" and type(vim.notify) == "function" then
    vim.notify(message, level or default_level, { title = "codux.nvim" })
  end
end

function M.api_function(name)
  return vim.api and type(vim.api[name]) == "function" and vim.api[name] or nil
end

function M.value_from(value, ...)
  if type(value) == "function" then
    return value(...)
  end
  return value
end

function M.now_ms()
  local loop = vim.uv or vim.loop
  if loop and type(loop.now) == "function" then
    return loop.now()
  end
  if loop and type(loop.hrtime) == "function" then
    return math.floor(loop.hrtime() / 1000000)
  end

  return os.time() * 1000
end

return M
