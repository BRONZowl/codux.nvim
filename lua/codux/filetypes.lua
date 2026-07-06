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
  ["codux-mission-preview-sink"] = true,
  ["codux-mission-question-answer"] = true,
  ["codux-mission-question-answer-sink"] = true,
  ["codux-mission-question-note"] = true,
  ["codux-mission-question-option"] = true,
  ["codux-mission-objective-preview"] = true,
  ["codux-mission-objective"] = true,
  ["codux-mission-workspace-prompt"] = true,
}

M.workspace = {
  ["codux-workspaces"] = true,
  ["codux-workspaces-footer"] = true,
  ["codux-workspaces-search"] = true,
  ["codux-workspaces-command"] = true,
  ["codux-workspaces-actions"] = true,
  ["codux-workspace-create"] = true,
  ["codux-workspace-create-footer"] = true,
  ["codux-workspace-instruction"] = true,
}

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
