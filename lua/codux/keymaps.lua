local M = {}

local function mapping_id(mode, lhs)
  return tostring(mode) .. "\0" .. tostring(lhs)
end

function M.remove_installed(state)
  state = type(state) == "table" and state or {}
  state.installed_mappings = type(state.installed_mappings) == "table" and state.installed_mappings or {}

  for id, mapping in pairs(state.installed_mappings) do
    local mode = mapping.mode
    local lhs = mapping.lhs
    if type(mode) == "string" and type(lhs) == "string" and lhs ~= "" then
      local current = vim.fn.maparg(lhs, mode, false, true)
      if type(current) == "table" and current.desc == mapping.desc then
        pcall(vim.keymap.del, mode, lhs)
      end
    end
    state.installed_mappings[id] = nil
  end
end

function M.set(state, mode, lhs, rhs, desc)
  state = type(state) == "table" and state or {}
  state.installed_mappings = type(state.installed_mappings) == "table" and state.installed_mappings or {}

  if type(lhs) == "string" and lhs ~= "" then
    vim.keymap.set(mode, lhs, rhs, { desc = desc })
    if type(mode) == "string" then
      state.installed_mappings[mapping_id(mode, lhs)] = {
        mode = mode,
        lhs = lhs,
        desc = desc,
      }
    end
  end
end

function M.install_defaults(state, mappings, codux, mode_action_desc)
  mappings = type(mappings) == "table" and mappings or {}
  M.set(state, "n", mappings.open, codux.open_with_keyed_profile_menu, "open codux")
  M.set(state, "n", mappings.review_file, codux.send_file_review, "send file/folder")
  M.set(state, "n", mappings.review_selection, codux.send_selection, "send selection")
  M.set(state, "v", mappings.review_selection, codux.send_selection, "send selection")
  M.set(state, "n", mappings.diagnostics, codux.send_diagnostics, "send diagnostics")
  M.set(state, "n", mappings.diff, codux.send_git_diff, "send git diff")
  M.set(state, "n", mappings.workspace, codux.open_workspace_prompt, "create codux workspace")
  M.set(state, "n", mappings.workspaces, codux.open_workspaces, "current codux workspaces")
  M.set(state, "n", mappings.mission, codux.open_mission_prompt, "create codux mission")
  M.set(state, "n", mappings.missions, codux.open_missions, "mission control")
  if mode_action_desc then
    M.set(state, "n", mappings.mode, codux.toggle_plan_mode, mode_action_desc)
  end
end

return M
