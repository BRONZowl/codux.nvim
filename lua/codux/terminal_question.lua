local text_util = require("codux.text")

local M = {}

local trim = text_util.trim

local function send_key(controller, key)
  local send_ok, sent = pcall(vim.fn.chansend, controller.state.job_id, key)
  if send_ok and sent ~= 0 then
    return true
  end
  controller.notify("Failed to answer agent question", vim.log.levels.ERROR)
  return false
end

function M.select_option(controller, option, with_note)
  option = trim(option)
  local option_number = tonumber(option)
  if
    option == ""
    or not option:match("^%d+$")
    or option_number == nil
    or option_number < 1
    or option_number > 4
    or not controller:terminal_running()
  then
    return false
  end

  for _ = 1, 20 do
    if not send_key(controller, "\27[A") then
      return false
    end
    pcall(vim.fn.sleep, "15m")
  end
  for _ = 1, option_number - 1 do
    if not send_key(controller, "\27[B") then
      return false
    end
    pcall(vim.fn.sleep, "15m")
  end

  local suffix = with_note == true and "\t" or "\r"
  pcall(vim.fn.sleep, "40m")
  if not send_key(controller, suffix) then
    return false
  end

  if with_note == true then
    pcall(vim.fn.sleep, "40m")
  end
  controller:invalidate_terminal_prompt_tracking()
  if with_note ~= true then
    controller:mark_terminal_prompt_submission()
    controller:set_agent_working(true)
  end
  return true
end

function M.submit_note(controller, note)
  note = tostring(note or "")
  if trim(note) == "" or not controller:terminal_running() then
    return false
  end

  local paste = "\27[200~" .. note .. "\27[201~\r"
  local send_ok, sent = pcall(vim.fn.chansend, controller.state.job_id, paste)
  if not send_ok or sent == 0 then
    controller.notify("Failed to send agent question note", vim.log.levels.ERROR)
    return false
  end

  controller:mark_terminal_prompt_submission()
  controller:invalidate_terminal_prompt_tracking()
  controller:set_agent_working(true)
  return true
end

return M
