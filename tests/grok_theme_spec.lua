local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_nil = h.assert_nil
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local grok_config = require("codux.grok_config")
local settings = require("codux.settings")

do
  assert_equal(grok_config.normalize_theme("TokyoNight"), "tokyonight")
  assert_equal(grok_config.normalize_theme("tokyo-night"), "tokyonight")
  assert_equal(grok_config.normalize_theme("tokyo"), "tokyonight")
  assert_equal(grok_config.normalize_theme("dark"), "groknight")
  assert_equal(grok_config.normalize_theme("light"), "grokday")
  assert_equal(grok_config.normalize_theme("system"), "auto")
  assert_equal(grok_config.normalize_theme("rose-pine"), "rosepine-moon")
  assert_equal(grok_config.normalize_theme("oscura"), "oscura-midnight")
  assert_nil(grok_config.normalize_theme("nope"))
  assert_nil(grok_config.normalize_theme(""))
  assert_equal(grok_config.theme_label("tokyonight"), "TokyoNight")
end

if type(vim.api) == "table" and type(vim.fn.tempname) == "function" then
  local settings_path = vim.fn.tempname() .. "-codux-settings.json"
  local grok_path = vim.fn.tempname() .. "-grok-config.toml"
  settings.set_path_for_tests(settings_path)
  grok_config.set_path_for_tests(grok_path)

  assert_nil(settings.get_grok_theme())
  assert_false(settings.set_grok_theme("nope"))
  assert_true(settings.set_grok_theme("tokyo"))
  assert_equal(settings.get_grok_theme(), "tokyonight")

  local seed = {
    "[cli]",
    'installer = "internal"',
    "",
    "[ui]",
    "max_thoughts_width = 120",
    "vim_mode = true",
    "",
    "[marketplace]",
    "official_marketplace_auto_installed = true",
  }
  assert_equal(vim.fn.writefile(seed, grok_path), 0)
  assert_nil(grok_config.read_ui_theme())

  assert_true(grok_config.write_ui_theme("tokyonight"))
  assert_equal(grok_config.read_ui_theme(), "tokyonight")
  local written = table.concat(vim.fn.readfile(grok_path), "\n")
  assert_contains(written, 'theme = "tokyonight"')
  assert_contains(written, "max_thoughts_width = 120")
  assert_contains(written, "vim_mode = true")
  assert_contains(written, 'installer = "internal"')

  assert_true(grok_config.write_ui_theme("grokday"))
  assert_equal(grok_config.read_ui_theme(), "grokday")
  written = table.concat(vim.fn.readfile(grok_path), "\n")
  assert_contains(written, 'theme = "grokday"')
  local theme_count = 0
  for line in written:gmatch("[^\n]+") do
    if line:match("^theme%s*=") then
      theme_count = theme_count + 1
    end
  end
  assert_equal(theme_count, 1)

  -- Resolve from settings and sync into grok config.
  settings.set_grok_theme("rosepine-moon")
  local theme = settings.resolve_and_sync_grok_theme({}, {})
  assert_equal(theme, "rosepine-moon")
  assert_equal(grok_config.read_ui_theme(), "rosepine-moon")

  -- Setup option wins over settings.
  theme = settings.resolve_and_sync_grok_theme({
    providers = { grok = { theme = "oscura" } },
  }, {})
  assert_equal(theme, "oscura-midnight")
  assert_equal(settings.get_grok_theme(), "oscura-midnight")
  assert_equal(grok_config.read_ui_theme(), "oscura-midnight")

  -- Env wins over settings when setup omits theme.
  settings.set_grok_theme("groknight")
  theme = settings.resolve_and_sync_grok_theme({}, { CODUX_GROK_THEME = "day" })
  assert_equal(theme, "grokday")
  assert_equal(grok_config.read_ui_theme(), "grokday")

  -- Seed settings from existing grok config when Codux has none.
  settings.write({})
  grok_config.write_ui_theme("tokyonight")
  theme = settings.resolve_and_sync_grok_theme({}, {})
  assert_equal(theme, "tokyonight")
  assert_equal(settings.get_grok_theme(), "tokyonight")

  local codux = require("codux")
  local old_env_provider = vim.env.CODUX_AGENT_PROVIDER
  local old_env_theme = vim.env.CODUX_GROK_THEME
  vim.env.CODUX_AGENT_PROVIDER = nil
  vim.env.CODUX_GROK_THEME = nil
  settings.set_grok_theme("auto")
  codux.setup({ token_monitor = false })
  assert_equal(codux.health_info().config.providers.grok.theme, "auto")
  assert_equal(grok_config.read_ui_theme(), "auto")

  assert_true(codux.set_grok_theme("tokyo-night"))
  assert_equal(settings.get_grok_theme(), "tokyonight")
  assert_equal(grok_config.read_ui_theme(), "tokyonight")
  assert_false(codux.set_grok_theme("nope"))

  vim.env.CODUX_AGENT_PROVIDER = old_env_provider
  vim.env.CODUX_GROK_THEME = old_env_theme
  settings.set_path_for_tests(nil)
  grok_config.set_path_for_tests(nil)
  pcall(vim.fn.delete, settings_path)
  pcall(vim.fn.delete, grok_path)
end

print("grok_theme_spec.lua: ok")
