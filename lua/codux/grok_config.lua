local text_util = require("codux.text")

local M = {}

local path_override = nil

local THEME_ALIASES = {
  auto = "auto",
  system = "auto",
  groknight = "groknight",
  ["grok-night"] = "groknight",
  dark = "groknight",
  grokday = "grokday",
  ["grok-day"] = "grokday",
  light = "grokday",
  day = "grokday",
  tokyonight = "tokyonight",
  ["tokyo-night"] = "tokyonight",
  tokyo = "tokyonight",
  ["rosepine-moon"] = "rosepine-moon",
  rosepine = "rosepine-moon",
  ["rose-pine"] = "rosepine-moon",
  ["rose-pine-moon"] = "rosepine-moon",
  ["oscura-midnight"] = "oscura-midnight",
  oscura = "oscura-midnight",
}

local CANONICAL_THEMES = {
  "auto",
  "groknight",
  "grokday",
  "tokyonight",
  "rosepine-moon",
  "oscura-midnight",
}

function M.set_path_for_tests(path)
  if type(path) == "string" and path ~= "" then
    path_override = path
  else
    path_override = nil
  end
end

function M.config_file()
  if type(path_override) == "string" and path_override ~= "" then
    return path_override
  end
  return vim.fn.expand("~/.grok/config.toml")
end

function M.theme_names()
  return vim.deepcopy(CANONICAL_THEMES)
end

function M.normalize_theme(value)
  if type(value) ~= "string" then
    return nil
  end
  value = text_util.trim(value):lower()
  if value == "" then
    return nil
  end
  return THEME_ALIASES[value]
end

function M.theme_label(theme)
  theme = M.normalize_theme(theme) or theme
  local labels = {
    auto = "Auto (system)",
    groknight = "GrokNight",
    grokday = "GrokDay",
    tokyonight = "TokyoNight",
    ["rosepine-moon"] = "RosePineMoon",
    ["oscura-midnight"] = "OscuraMidnight",
  }
  return labels[theme] or tostring(theme or "")
end

function M.theme_choices()
  return {
    { key = "a", theme = "auto", label = "auto", desc = "Auto (system)" },
    { key = "n", theme = "groknight", label = "night", desc = "GrokNight" },
    { key = "d", theme = "grokday", label = "day", desc = "GrokDay" },
    { key = "t", theme = "tokyonight", label = "tokyo", desc = "TokyoNight" },
    { key = "r", theme = "rosepine-moon", label = "rose", desc = "RosePineMoon" },
    { key = "o", theme = "oscura-midnight", label = "oscura", desc = "OscuraMidnight" },
  }
end

local function parse_theme_assignment(line)
  local key, value = line:match("^%s*([%w_-]+)%s*=%s*(.-)%s*$")
  if key ~= "theme" then
    return nil
  end
  value = value:match("^['\"](.-)['\"]%s*$") or value:match("^([^#;]+)")
  if type(value) ~= "string" then
    return nil
  end
  value = text_util.trim(value)
  -- strip trailing inline comment without quotes
  value = value:gsub("%s+#.*$", ""):gsub("%s+;.*$", "")
  value = text_util.trim(value)
  if value == "" then
    return nil
  end
  return M.normalize_theme(value) or value
end

function M.read_ui_theme()
  local path = M.config_file()
  if type(vim.fn.filereadable) ~= "function" or vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return nil
  end

  local in_ui = false
  for _, line in ipairs(lines) do
    local section = line:match("^%s*%[([^%]]+)%]%s*$")
    if section then
      in_ui = section == "ui"
    elseif in_ui then
      local theme = parse_theme_assignment(line)
      if theme then
        return M.normalize_theme(theme) or theme
      end
    end
  end

  return nil
end

local function ensure_directory(path)
  local directory = vim.fn.fnamemodify(path, ":h")
  if directory == "" or directory == "." then
    return true
  end
  local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, directory, "p")
  if mkdir_ok and (mkdir_result == 1 or (type(vim.fn.isdirectory) == "function" and vim.fn.isdirectory(directory) == 1)) then
    return true
  end
  if type(vim.fn.isdirectory) == "function" and vim.fn.isdirectory(directory) == 1 then
    return true
  end
  return false
end

function M.write_ui_theme(theme)
  theme = M.normalize_theme(theme)
  if not theme then
    return false, "Unknown Grok theme"
  end

  local path = M.config_file()
  if not ensure_directory(path) then
    return false, "Failed to create Grok config directory"
  end

  local lines = {}
  if type(vim.fn.filereadable) == "function" and vim.fn.filereadable(path) == 1 then
    local ok, existing = pcall(vim.fn.readfile, path)
    if ok and type(existing) == "table" then
      lines = existing
    end
  end

  local in_ui = false
  local ui_start = nil
  local theme_line = nil
  local next_section_after_ui = nil

  for index, line in ipairs(lines) do
    local section = line:match("^%s*%[([^%]]+)%]%s*$")
    if section then
      if section == "ui" then
        in_ui = true
        ui_start = index
      elseif in_ui then
        next_section_after_ui = index
        in_ui = false
      end
    elseif in_ui and line:match("^%s*theme%s*=") then
      theme_line = index
    end
  end

  local assignment = 'theme = "' .. theme .. '"'
  if theme_line then
    lines[theme_line] = assignment
  elseif ui_start then
    local insert_at = next_section_after_ui or (#lines + 1)
    table.insert(lines, insert_at, assignment)
  else
    if #lines > 0 and text_util.trim(lines[#lines]) ~= "" then
      table.insert(lines, "")
    end
    table.insert(lines, "[ui]")
    table.insert(lines, assignment)
  end

  local ok, result = pcall(vim.fn.writefile, lines, path)
  if not ok or result ~= 0 then
    return false, "Failed to write Grok config"
  end
  return true
end

return M
