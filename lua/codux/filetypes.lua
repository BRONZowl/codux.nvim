local M = {}

M.mission_control = {
  ["codux-missions"] = true,
  ["codux-missions-search"] = true,
  ["codux-missions-command"] = true,
  ["codux-missions-commands"] = true,
  ["codux-missions-actions"] = true,
  ["codux-missions-output"] = true,
  ["codux-mission-preview"] = true,
  ["codux-mission-preview-footer"] = true,
  ["codux-mission-question-answer"] = true,
  ["codux-mission-question-answer-sink"] = true,
  ["codux-mission-question-note"] = true,
  ["codux-mission-question-option"] = true,
  ["codux-mission-objective-preview"] = true,
  ["codux-mission-objective"] = true,
  ["codux-mission-workspace-prompt"] = true,
}

-- Floating manager chrome (list/search/command/action). Closing the manager
-- only tears these down — create/instruction editors are separate flows.
M.workspace_manager = {
  ["codux-workspaces"] = true,
  ["codux-workspaces-footer"] = true,
  ["codux-workspaces-search"] = true,
  ["codux-workspaces-command"] = true,
  ["codux-workspaces-actions"] = true,
}

M.workspace = {
  ["codux-workspace-create"] = true,
  ["codux-workspace-create-footer"] = true,
  ["codux-workspace-instruction"] = true,
}

for filetype in pairs(M.workspace_manager) do
  M.workspace[filetype] = true
end

M.internal = {
  codux = true,
}

for filetype in pairs(M.workspace) do
  M.internal[filetype] = true
end

for filetype in pairs(M.mission_control) do
  M.internal[filetype] = true
end

function M.is_mission_control(filetype)
  return M.mission_control[tostring(filetype or "")] == true
end

function M.is_workspace(filetype)
  return M.workspace[tostring(filetype or "")] == true
end

function M.is_internal(filetype)
  return M.internal[tostring(filetype or "")] == true
end

return M
