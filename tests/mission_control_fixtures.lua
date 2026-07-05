local M = {}

function M.mission_role_entry(mission_name, role)
  mission_name = mission_name or "Alpha"
  role = role or "Builder"
  local mission_key = mission_name:lower()
  local role_key = role:lower()
  local name = mission_key .. "-" .. role_key
  return {
    name = name,
    safe_name = name,
    mission_id = "mission:" .. mission_key,
    mission_name = mission_name,
    mission_role = role,
  }
end

return M
