--- Best-effort private filesystem helpers (user-only perms when setfperm exists).
local M = {}

local FILE_MODE = "rw-------" -- 0600
local DIR_MODE = "rwx------" -- 0700

function M.set_private_file(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  if type(vim.fn) ~= "table" or type(vim.fn.setfperm) ~= "function" then
    return false
  end
  local ok = pcall(vim.fn.setfperm, path, FILE_MODE)
  return ok == true
end

function M.set_private_dir(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  if type(vim.fn) ~= "table" or type(vim.fn.setfperm) ~= "function" then
    return false
  end
  local ok = pcall(vim.fn.setfperm, path, DIR_MODE)
  return ok == true
end

function M.ensure_dir(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  if type(vim.fn) ~= "table" or type(vim.fn.mkdir) ~= "function" then
    return false
  end

  local ok, result = pcall(vim.fn.mkdir, path, "p", 448)
  if not ok or (result ~= 1 and result ~= 0) then
    ok, result = pcall(vim.fn.mkdir, path, "p")
    if not ok or (result ~= 1 and type(vim.fn.isdirectory) == "function" and vim.fn.isdirectory(path) ~= 1) then
      if not ok or result ~= 1 then
        return false
      end
    end
  end
  M.set_private_dir(path)
  return type(vim.fn.isdirectory) ~= "function" or vim.fn.isdirectory(path) == 1 or result == 1
end

--- Write a single-string or list-of-lines file with private mode.
function M.write_private(path, content)
  if type(path) ~= "string" or path == "" then
    return false, "missing path"
  end
  if type(vim.fn) ~= "table" or type(vim.fn.writefile) ~= "function" then
    return false, "writefile unavailable"
  end

  local directory = type(vim.fn.fnamemodify) == "function" and vim.fn.fnamemodify(path, ":h") or nil
  if type(directory) == "string" and directory ~= "" and directory ~= "." then
    if not M.ensure_dir(directory) then
      return false, "Failed to create directory"
    end
  end

  local lines
  if type(content) == "table" then
    lines = content
  else
    lines = { tostring(content or "") }
  end

  local ok, result = pcall(vim.fn.writefile, lines, path)
  if not ok or result ~= 0 then
    return false, "Failed to write file"
  end
  M.set_private_file(path)
  return true, nil
end

return M
