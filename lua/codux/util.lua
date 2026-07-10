local M = {}

function M.noop() end

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
