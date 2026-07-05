local M = {}

local function command_display(command)
  if type(command) == "table" then
    local parts = {}
    for _, part in ipairs(command) do
      table.insert(parts, tostring(part))
    end
    return table.concat(parts, " ")
  end
  return tostring(command or "")
end

local function preview_attach_error(command, detail)
  local message = "failed to attach workspace session preview"
  detail = tostring(detail or "")
  if detail ~= "" then
    message = message .. ": " .. detail
  end

  local display = command_display(command)
  if display ~= "" then
    message = message .. " (" .. display .. ")"
  end
  return message
end

function M.output_preview_running(self)
  local job_id = self.state.mission_dashboard_output_job
  if type(job_id) ~= "number" or job_id <= 0 then
    return false
  end
  local ok, statuses = pcall(vim.fn.jobwait, { job_id }, 0)
  return ok and type(statuses) == "table" and statuses[1] == -1
end

function M.close_output_preview(self)
  local job_id = self.state.mission_dashboard_output_job
  self.state.mission_dashboard_output_job = nil
  if type(job_id) == "number" and job_id > 0 then
    pcall(self.jobstop, job_id)
  end
  local preview = self.state.mission_dashboard_output_preview
  self.state.mission_dashboard_output_preview = nil
  if preview then
    pcall(self.close_workspace_interactive_preview, preview)
  end
end

function M.start_output_preview(self, entry)
  if not self.is_loaded_buf(self.state.mission_dashboard_output_buf) then
    return false
  end

  self:close_output_preview()
  self.state.mission_dashboard_output_generation = (tonumber(self.state.mission_dashboard_output_generation) or 0) + 1
  local generation = self.state.mission_dashboard_output_generation
  self.state.mission_dashboard_output_entry = entry
  self.state.mission_dashboard_output_key = self:output_entry_key(entry)
  self.state.mission_dashboard_output_blocked_key = nil
  if type(entry) ~= "table" then
    return self:render_output_status(entry, "select a workspace to preview")
  end
  if entry.status == "inactive" then
    return self:render_output_status(entry, "workspace is not active")
  end

  self:render_output_status(entry, "opening workspace session preview...")
  local preview, error_message = self.workspace_interactive_preview(entry)
  if not preview then
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, error_message or "workspace session preview unavailable")
  end

  local command = preview.command
  if type(command) ~= "table" and type(command) ~= "string" then
    self.close_workspace_interactive_preview(preview)
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, "workspace session preview command unavailable")
  end

  if not self:prepare_output_terminal_buffer() then
    self.close_workspace_interactive_preview(preview)
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, "workspace session preview buffer unavailable")
  end
  local preview_key = self.state.mission_dashboard_output_key
  local preview_buf = self.state.mission_dashboard_output_buf
  local term_ok, term_error = pcall(vim.api.nvim_buf_call, self.state.mission_dashboard_output_buf, function()
    return self.termopen(command, {
      on_exit = function(exited_job_id, code)
        if
          self.state.mission_dashboard_output_job == exited_job_id
          and self.state.mission_dashboard_output_generation == generation
          and self.state.mission_dashboard_output_key == preview_key
        then
          self.state.mission_dashboard_output_job = nil
          local active_entry = self.state.mission_dashboard_output_entry
          local active_key = self.state.mission_dashboard_output_key
          local active_preview = self.state.mission_dashboard_output_preview
          self.state.mission_dashboard_output_preview = nil
          if active_preview then
            pcall(self.close_workspace_interactive_preview, active_preview)
          end
          self.state.mission_dashboard_output_blocked_key = active_key
          self:render_output_status(active_entry, "workspace preview exited with code " .. tostring(code))
        end
      end,
    })
  end)
  if not term_ok or type(term_error) ~= "number" or term_error <= 0 then
    self.close_workspace_interactive_preview(preview)
    local detail = term_ok and ("invalid job id " .. tostring(term_error)) or term_error
    self.state.mission_dashboard_output_blocked_key = self.state.mission_dashboard_output_key
    return self:render_output_status(entry, preview_attach_error(command, detail))
  end

  self.state.mission_dashboard_output_job = term_error
  self.state.mission_dashboard_output_preview = preview
  pcall(vim.api.nvim_set_option_value, "filetype", "codux-missions-output", { buf = preview_buf })
  return true
end

return M
