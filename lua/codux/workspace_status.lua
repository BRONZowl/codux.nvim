local M = {}

function M.normalize_agent_mode(mode)
  if mode == "execute" or mode == "plan" then
    return mode
  end

  return nil
end

-- Legacy alias.
M.normalize_codex_mode = M.normalize_agent_mode

function M.inactive_like_status(status)
  return status == "inactive" or status == "missing"
end

return M
