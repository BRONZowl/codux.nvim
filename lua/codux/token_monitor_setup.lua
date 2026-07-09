local json = require("codux.json")
local token_monitor_mod = require("codux.token_monitor")

local M = {}

function M.new(opts)
  opts = type(opts) == "table" and opts or {}
  local monitor = token_monitor_mod.new({
    get_config = opts.get_config,
    defaults = opts.defaults,
    state = opts.state,
    is_running = opts.is_running,
    get_mode = opts.get_mode,
    get_agent_provider = opts.get_agent_provider,
    command_util = opts.command_util,
    json_encode = json.encode,
    json_decode = json.decode,
    on_update = opts.on_update,
  })

  return {
    monitor = monitor,
    token_usage_label = function()
      return monitor:label({
        running = opts.is_running(),
        mode = opts.get_mode(),
      })
    end,
    mission_token_usage_label = function()
      return monitor:label({
        show_when_not_running = true,
      })
    end,
    refresh_token_usage = function(force)
      return monitor:refresh(force)
    end,
    refresh_mission_token_usage = function(force)
      return monitor:refresh(force, {
        require_running = false,
      })
    end,
    token_usage_refresh_ms = function()
      return monitor:refresh_ms()
    end,
    start = function()
      return monitor:start()
    end,
    stop = function()
      return monitor:stop()
    end,
  }
end

return M
