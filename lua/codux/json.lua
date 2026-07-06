local M = {}

function M.encode(value)
  if vim.json and type(vim.json.encode) == "function" then
    return vim.json.encode(value)
  end

  return vim.fn.json_encode(value)
end

function M.decode(value)
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

return M
