local M = {}

local text_util = require("codux.text")
local util = require("codux.util")

local severity_names = {
  [vim.diagnostic.severity.ERROR] = "ERROR",
  [vim.diagnostic.severity.WARN] = "WARN",
  [vim.diagnostic.severity.INFO] = "INFO",
  [vim.diagnostic.severity.HINT] = "HINT",
}

local function trim(value)
  return text_util.trim(value)
end

local function call(dep, fallback, ...)
  if type(dep) == "function" then
    return dep(...)
  end
  if type(fallback) == "function" then
    return fallback(...)
  end
  return fallback
end

local function runtime_config(deps)
  local config = call(deps.config, {})
  return type(config) == "table" and config or {}
end

local function notify(deps, message, level)
  if type(deps.notify) == "function" then
    deps.notify(message, level)
  else
    util.notify(message, level)
  end
end

function M.normalize_target(target, source)
  if type(target) ~= "table" or type(target.path) ~= "string" or target.path == "" then
    return nil
  end

  return {
    path = target.path,
    type = target.type == "directory" and "directory" or "file",
    source = target.source or source,
  }
end

function M.is_explorer_filetype(filetype)
  return filetype == "neo-tree" or filetype == "oil" or filetype == "NvimTree" or filetype == "minifiles"
end

function M.target_label(target)
  if target and target.type == "directory" then
    return "directory"
  end

  return "file"
end

function M.render_prompt(template, context)
  if type(template) == "function" then
    local ok, value = pcall(template, context)
    if ok and type(value) == "string" then
      return value
    end

    return nil, "Prompt function failed"
  end

  return tostring(template):gsub("%%{([%w_]+)}", function(key)
    local value = context[key]
    if value == nil then
      return ""
    end
    return tostring(value)
  end)
end

function M.format_list_diagnostics(items)
  if vim.tbl_isempty(items) then
    return nil
  end

  local lines = {}
  for _, item in ipairs(items) do
    local filename = item.filename and vim.fn.fnamemodify(item.filename, ":.") or ""
    local location = ""
    if filename ~= "" then
      location = filename .. ":"
    end

    local line = item.lnum or 0
    local col = item.col or 0
    local type_label = item.type and item.type ~= "" and item.type or "INFO"
    table.insert(lines, string.format("%s %s%d:%d %s", type_label, location, line, col, item.text or ""))
  end

  return table.concat(lines, "\n")
end

function M.health_has_issues(text)
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    local lower = string.lower(line)
    if lower:match("^%s*health command exited with code") then
      return true
    end
    if lower:match("^%s*failed to collect :") or lower:match("^%s*failed to collect health output") then
      return true
    end
    if line:match("^%s*%- .*❌") or line:match("^%s*%- .*⚠") then
      return true
    end
    if lower:match("^%s*%- %s*error") or lower:match("^%s*%- %s*warn") or lower:match("^%s*%- %s*warning") then
      return true
    end
  end

  return false
end

function M.new(deps)
  deps = type(deps) == "table" and deps or {}
  local context = {}

  local function config()
    return runtime_config(deps)
  end

  local function system(args, input)
    return call(deps.system, function()
      local output = vim.fn.system(args, input)
      return output, vim.v.shell_error
    end, args, input)
  end

  local function system_with_timeout(args, timeout_ms)
    return call(deps.system_with_timeout, system, args, timeout_ms)
  end

  local function current_filetype()
    return call(deps.current_filetype, "unknown")
  end

  local function current_buffer_name()
    return call(deps.current_buffer_name, "")
  end

  local function explorer_enabled(name)
    local explorers = config().explorers
    return type(explorers) == "table" and explorers[name] ~= false
  end

  function context.normalize_target(target, source)
    return M.normalize_target(target, source)
  end

  function context.is_explorer_filetype(filetype)
    return M.is_explorer_filetype(filetype)
  end

  local function neo_tree_target()
    if not explorer_enabled("neo_tree") or current_filetype() ~= "neo-tree" then
      return nil
    end

    local ok, manager = pcall(require, "neo-tree.sources.manager")
    if not ok then
      return nil
    end

    local state_ok, state = pcall(manager.get_state_for_window)
    if not state_ok or not state or not state.tree then
      return nil
    end

    local node_ok, node = pcall(state.tree.get_node, state.tree)
    if not node_ok or not node then
      return nil
    end

    local path = node.path
    if (type(path) ~= "string" or path == "") and type(node.get_id) == "function" then
      local id_ok, id = pcall(node.get_id, node)
      if id_ok and type(id) == "string" and id ~= "" then
        path = id
      end
    end

    return M.normalize_target({
      path = path,
      type = node.type == "directory" and "directory" or "file",
    }, "neo-tree")
  end

  local function oil_target()
    if not explorer_enabled("oil") or current_filetype() ~= "oil" then
      return nil
    end

    local ok, oil = pcall(require, "oil")
    if not ok then
      return nil
    end

    local dir_ok, dir = pcall(oil.get_current_dir)
    local entry_ok, entry = pcall(oil.get_cursor_entry)
    if not dir_ok or not entry_ok or type(dir) ~= "string" or type(entry) ~= "table" or type(entry.name) ~= "string" then
      return nil
    end

    if not dir:match("/$") then
      dir = dir .. "/"
    end

    local path = dir .. entry.name
    return M.normalize_target({
      path = path,
      type = vim.fn.isdirectory(path) == 1 and "directory" or "file",
    }, "oil")
  end

  local function nvim_tree_target()
    if not explorer_enabled("nvim_tree") or current_filetype() ~= "NvimTree" then
      return nil
    end

    local ok, api = pcall(require, "nvim-tree.api")
    if not ok or not api.tree or type(api.tree.get_node_under_cursor) ~= "function" then
      return nil
    end

    local node_ok, node = pcall(api.tree.get_node_under_cursor)
    if not node_ok or type(node) ~= "table" then
      return nil
    end

    return M.normalize_target({
      path = node.absolute_path,
      type = node.type == "directory" and "directory" or "file",
    }, "nvim-tree")
  end

  local function mini_files_target()
    if not explorer_enabled("mini_files") or current_filetype() ~= "minifiles" then
      return nil
    end

    local ok, mini_files = pcall(require, "mini.files")
    if not ok or type(mini_files.get_fs_entry) ~= "function" then
      return nil
    end

    local entry_ok, entry = pcall(mini_files.get_fs_entry)
    if not entry_ok or type(entry) ~= "table" then
      return nil
    end

    return M.normalize_target({
      path = entry.path,
      type = vim.fn.isdirectory(entry.path or "") == 1 and "directory" or "file",
    }, "mini.files")
  end

  function context.current_buffer_target()
    local path = current_buffer_name()
    if path == "" then
      return nil
    end

    return M.normalize_target({
      path = path,
      type = vim.fn.isdirectory(path) == 1 and "directory" or "file",
    }, "buffer")
  end

  function context.current_target()
    local providers = type(config().target_providers) == "table" and config().target_providers or {}
    for _, provider in ipairs(providers) do
      if type(provider) == "function" then
        local ok, target = pcall(provider)
        if ok then
          target = M.normalize_target(target, "custom")
          if target then
            return target
          end
        end
      end
    end

    return neo_tree_target() or oil_target() or nvim_tree_target() or mini_files_target() or context.current_buffer_target()
  end

  function context.target_label(target)
    return M.target_label(target)
  end

  function context.git_branch_for(path)
    local cwd = path
    if path and vim.fn.isdirectory(path) ~= 1 then
      cwd = vim.fn.fnamemodify(path, ":h")
    end

    if not cwd or cwd == "" then
      cwd = vim.fn.getcwd()
    end

    local output, code = system({ "git", "-C", cwd, "branch", "--show-current" })
    if code ~= 0 then
      return ""
    end

    return trim(output)
  end

  function context.git_root_for(path)
    local cwd = path
    if cwd and cwd ~= "" and vim.fn.isdirectory(cwd) ~= 1 then
      cwd = vim.fn.fnamemodify(cwd, ":h")
    end

    if cwd == nil or cwd == "" then
      cwd = vim.fn.getcwd()
    end

    local output, code = system({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })
    if code ~= 0 then
      return nil
    end

    local root = trim(output)
    if root == "" then
      return nil
    end

    return root
  end

  local function git_output(root, ...)
    local args = { "git", "-C", root }
    vim.list_extend(args, { ... })
    local output, code = system(args)
    if code ~= 0 then
      return nil
    end

    return trim(output)
  end

  function context.git_branch_or_head(root)
    local branch = git_output(root, "branch", "--show-current")
    if branch and branch ~= "" then
      return branch
    end

    local head = git_output(root, "rev-parse", "--short", "HEAD")
    if head and head ~= "" then
      return head
    end

    return "unknown"
  end

  function context.git_diff_target_path()
    local target = context.current_target()
    if target and type(target.path) == "string" and target.path ~= "" then
      return target.path
    end

    local path = current_buffer_name()
    if path ~= "" then
      return path
    end

    return vim.fn.getcwd()
  end

  function context.format_git_diff_context(root)
    local status = git_output(root, "status", "--short")
    if status == nil then
      return nil, "Failed to collect Git status"
    end

    if status == "" then
      return nil, "No Git changes found"
    end

    local staged = git_output(root, "diff", "--cached", "--no-ext-diff", "--")
    if staged == nil then
      return nil, "Failed to collect staged Git diff"
    end

    local unstaged = git_output(root, "diff", "--no-ext-diff", "--")
    if unstaged == nil then
      return nil, "Failed to collect unstaged Git diff"
    end

    local sections = {
      "## Git status\n" .. status,
      "## Staged diff\n" .. (staged ~= "" and staged or "(none)"),
      "## Unstaged diff\n" .. (unstaged ~= "" and unstaged or "(none)"),
    }

    return table.concat(sections, "\n\n"), nil
  end

  function context.format_vim_diagnostics(bufnr)
    local ok, diagnostics = pcall(vim.diagnostic.get, bufnr or 0)
    if not ok then
      return nil
    end

    if vim.tbl_isempty(diagnostics) then
      return nil
    end

    local lines = {}
    for _, diagnostic in ipairs(diagnostics) do
      local source = diagnostic.source and (" [" .. diagnostic.source .. "]") or ""
      local code = diagnostic.code and (" (" .. diagnostic.code .. ")") or ""
      local severity = severity_names[diagnostic.severity] or "UNKNOWN"
      table.insert(
        lines,
        string.format(
          "%s %d:%d%s%s %s",
          severity,
          (diagnostic.lnum or 0) + 1,
          (diagnostic.col or 0) + 1,
          source,
          code,
          diagnostic.message or ""
        )
      )
    end

    return table.concat(lines, "\n")
  end

  function context.format_list_diagnostics(items)
    return M.format_list_diagnostics(items)
  end

  function context.health_has_issues(text)
    return M.health_has_issues(text)
  end

  function context.collect_health_diagnostics()
    local nvim = vim.v.progpath ~= "" and vim.v.progpath or "nvim"
    local script = table.concat({
      'local commands = {}',
      'if vim.fn.exists(":LazyHealth") == 2 then table.insert(commands, "LazyHealth") end',
      'table.insert(commands, "checkhealth")',
      'local function capture_buffer()',
      'local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)',
      'return table.concat(lines, "\\n")',
      'end',
      'for _, command in ipairs(commands) do',
      'print("## :" .. command)',
      'local ok, err = pcall(vim.cmd, "silent " .. command)',
      'if ok then print(capture_buffer()) else print("Failed to collect :" .. command .. " output: " .. tostring(err)) end',
      'pcall(vim.cmd, "silent! bwipeout!")',
      'end',
      'vim.cmd("qa!")',
    }, "\n")

    local output, code =
      system_with_timeout({ nvim, "--headless", "-i", "NONE", "-c", "lua " .. script }, config().health_timeout_ms)
    local text = trim(output)
    if text == "" then
      text = "Failed to collect health output"
    end
    if code ~= 0 then
      text = text .. "\n\nHealth command exited with code " .. tostring(code)
    end

    return {
      source = ":LazyHealth/:checkhealth",
      text = text,
      has_issues = code ~= 0 or M.health_has_issues(text),
    }
  end

  function context.collect_diagnostics(bufnr)
    local sections = {}
    local sources = {}
    local has_issues = false
    local formatted = context.format_vim_diagnostics(bufnr or 0)
    if formatted then
      has_issues = true
      table.insert(sources, "Neovim diagnostics")
      table.insert(sections, "## Neovim diagnostics\n" .. formatted)
    end

    formatted = M.format_list_diagnostics(vim.fn.getloclist(0))
    if formatted then
      has_issues = true
      table.insert(sources, "Location list")
      table.insert(sections, "## Location list\n" .. formatted)
    end

    formatted = M.format_list_diagnostics(vim.fn.getqflist())
    if formatted then
      has_issues = true
      table.insert(sources, "Quickfix list")
      table.insert(sections, "## Quickfix list\n" .. formatted)
    end

    local health = context.collect_health_diagnostics()
    if health and (has_issues or health.has_issues) then
      has_issues = has_issues or health.has_issues
      table.insert(sources, health.source)
      table.insert(sections, "## " .. health.source .. "\n" .. health.text)
    end

    if has_issues and not vim.tbl_isempty(sections) then
      return {
        source = table.concat(sources, ", "),
        text = table.concat(sections, "\n\n"),
      }
    end

    return nil
  end

  function context.context_for_target(target, extra)
    extra = extra or {}
    local fallback_path = extra.fallback_path
    if fallback_path == nil then
      fallback_path = current_buffer_name()
    end
    local path = target and target.path or fallback_path
    local absolute_path = path ~= "" and vim.fn.fnamemodify(path, ":p") or ""
    local relative_path = path ~= "" and vim.fn.fnamemodify(path, ":.") or "current Neovim session"

    return vim.tbl_extend("force", {
      path = path,
      absolute_path = absolute_path,
      relative_path = relative_path,
      target_type = target and M.target_label(target) or "file",
      target_source = target and target.source or "buffer",
      filetype = current_filetype(),
      git_branch = context.git_branch_for(path),
      diagnostics = "",
      diagnostics_source = "",
      line_range = "",
      selection = "",
    }, extra)
  end

  function context.render_prompt(template, prompt_context)
    local rendered, error_message = M.render_prompt(template, prompt_context)
    if error_message then
      notify(deps, error_message, vim.log.levels.ERROR)
    end
    return rendered
  end

  return context
end

return M
