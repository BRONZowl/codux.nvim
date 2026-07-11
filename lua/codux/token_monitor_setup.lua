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
    on_update = opts.on_update,
  })

  return {
    monitor = monitor,
    token_usage_label = function()
      return monitor:label({
        running = opts.is_running(),
        mode = opts.get_mode(),
        show_error = true,
      })
    end,
    mission_token_usage_label = function(provider)
      if provider ~= nil and provider ~= "" then
        return monitor:label_for_provider(provider, {
          show_when_not_running = true,
          show_error = true,
        })
      end
      return monitor:label({
        show_when_not_running = true,
        show_error = true,
      })
    end,
    label_for_provider = function(provider, label_opts)
      return monitor:label_for_provider(provider, label_opts)
    end,
    provider_refreshed_at = function(provider)
      return monitor:provider_refreshed_at(provider)
    end,
    refresh_token_usage = function(force)
      return monitor:refresh(force)
    end,
    refresh_mission_token_usage = function(force, refresh_opts)
      refresh_opts = type(refresh_opts) == "table" and refresh_opts or {}
      return monitor:refresh(force, {
        require_running = false,
        agent_provider = refresh_opts.agent_provider,
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
