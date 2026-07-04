local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_true = h.assert_true

local ui = require("codux.ui")

do
  local checked_bufnr
  local ok = ui.disable_buffer_completion(99, {
    is_loaded_buf = function(bufnr)
      checked_bufnr = bufnr
      return false
    end,
  })

  assert_false(ok)
  assert_equal(checked_bufnr, 99)
end

if type(vim.api) == "table" then
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("completefunc", "v:lua.SomeComplete", { buf = bufnr })
  vim.api.nvim_set_option_value("omnifunc", "v:lua.SomeOmni", { buf = bufnr })

  assert_true(ui.disable_buffer_completion(bufnr))
  assert_equal(vim.api.nvim_get_option_value("completefunc", { buf = bufnr }), "")
  assert_equal(vim.api.nvim_get_option_value("omnifunc", { buf = bufnr }), "")
  assert_equal(vim.b[bufnr].codux_disable_completion, true)
  assert_equal(vim.b[bufnr].blink_cmp_enabled, false)
  assert_equal(vim.b[bufnr].cmp_enabled, false)
  assert_equal(vim.b[bufnr].copilot_enabled, false)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

print("ui_spec.lua: ok")
