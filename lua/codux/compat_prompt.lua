local M = {}

function M.install_prompt_open(api, deps)
  api = type(api) == "table" and api or {}
  deps = type(deps) == "table" and deps or {}
  local state = type(deps.state) == "table" and deps.state or {}
  local terminal = deps.terminal
  local open_with_keyed_profile_menu = deps.open_with_keyed_profile_menu

  function api.send_prompt_or_open_with_profile(message)
    if not api.should_select_permission_profile(state.job_id) then
      return terminal:send_to_codex(message)
    end

    return open_with_keyed_profile_menu({
      initial_prompt = message,
      open_opts = {
        initial_mode = "plan",
      },
    })
  end

  return api
end

return M
