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

function M.notifications()
  local messages = {}
  return messages, function(message)
    table.insert(messages, message)
  end
end

function M.dashboard_controller(opts)
  opts = opts or {}
  local mission_control_mod = require("codux.mission_control")
  local notifications = opts.notifications
  local config = {}
  for key, value in pairs(opts.config or {}) do
    config[key] = value
  end
  if opts.state ~= nil then
    config.state = opts.state
  end
  if opts.ui ~= nil then
    config.ui = opts.ui
  end
  if opts.notify ~= nil then
    config.notify = opts.notify
  elseif notifications ~= nil then
    config.notify = function(message)
      table.insert(notifications, message)
    end
  end

  local controller = mission_control_mod.new(config)
  for key, value in pairs(opts.methods or {}) do
    controller[key] = value
  end
  return controller, {
    notifications = notifications,
  }
end

return M
