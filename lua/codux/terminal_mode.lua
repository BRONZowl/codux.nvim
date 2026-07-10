local text_util = require("codux.text")

local M = {}

local trim = text_util.trim

function M.mode_display_label(mode)
  if mode == "execute" then
    return "exec"
  end

  return mode or "not running"
end

function M.strip_terminal_control_sequences(value)
  return tostring(value or "")
    :gsub("\27%][^\7]*\7", "")
    :gsub("\27%][^\27]*\27\\", "")
    :gsub("\27%[[0-?]*[ -/]*[@-~]", "")
    :gsub("\27[@-_]", "")
    :gsub("\r", "")
    :gsub("[%z\1-\8\11-\12\14-\31\127]", "")
end

function M.detect_terminal_mode_from_line(line)
  line = trim(M.strip_terminal_control_sequences(line):lower():gsub("%s+", " "))
  if line == "" then
    return nil
  end

  local mode = line:match("^mode:%s*(plan)$") or line:match("^codex mode:%s*(plan)$")
  if not mode and line == "plan mode" then
    mode = "plan"
  end
  if not mode and line:find("plan mode (shift+tab to cycle)", 1, true) then
    mode = "plan"
  end
  if not mode and line:match("plan mode$") then
    mode = "plan"
  end
  if mode then
    return mode
  end

  mode = line:match("^mode:%s*(execute)$") or line:match("^codex mode:%s*(execute)$")
  if not mode and line == "execute mode" then
    mode = "execute"
  end
  if not mode and line:find("execute mode (shift+tab to cycle)", 1, true) then
    mode = "execute"
  end
  if not mode and line:match("execute mode$") then
    mode = "execute"
  end
  if mode then
    return mode
  end

  return nil
end

function M.detect_terminal_mode_from_lines(lines, first_index)
  if type(lines) ~= "table" then
    return nil
  end

  first_index = math.max(1, tonumber(first_index) or 1)
  local start_index = math.max(first_index, #lines - 39)

  for index = #lines, start_index, -1 do
    local mode = M.detect_terminal_mode_from_line(lines[index])
    if mode ~= nil then
      return mode
    end
  end

  return nil
end

function M.output_looks_like_question(lines, first_index)
  if type(lines) ~= "table" then
    return false
  end

  first_index = math.max(1, tonumber(first_index) or 1)
  local start_index = math.max(first_index, #lines - 79)
  for index = #lines, start_index, -1 do
    local line = trim(M.strip_terminal_control_sequences(lines[index]))
    if line ~= "" and line:match("%?[%]%)}\"'`%s]*$") then
      return true
    end
  end

  return false
end

function M.terminal_prompt_is_plan_toggle(input, tracking_valid)
  if tracking_valid == nil then
    tracking_valid = true
  end
  return tracking_valid == true and trim(input) == "/plan"
end

function M.terminal_line_is_plan_toggle(line)
  line = trim(M.strip_terminal_control_sequences(line):gsub("%s+", " "))
  return line == "/plan" or line == "> /plan"
end

return M
