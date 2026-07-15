local h = require("tests.helpers")
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_equal = h.assert_equal

local fs = require("codux.fs")

do
  local set_calls = {}
  h.with_stubs({
    {
      target = vim.fn,
      key = "setfperm",
      value = function(path, mode)
        table.insert(set_calls, { path = path, mode = mode })
        return 1
      end,
    },
    {
      target = vim.fn,
      key = "mkdir",
      value = function()
        return 1
      end,
    },
    {
      target = vim.fn,
      key = "isdirectory",
      value = function()
        return 1
      end,
    },
    {
      target = vim.fn,
      key = "fnamemodify",
      value = function(path, mod)
        if mod == ":h" then
          return path:match("(.+)/[^/]+$") or "."
        end
        return path
      end,
    },
    {
      target = vim.fn,
      key = "writefile",
      value = function()
        return 0
      end,
    },
  }, function()
    assert_true(fs.set_private_file("/tmp/codux-private.txt"))
    assert_true(fs.set_private_dir("/tmp/codux-private-dir"))
    assert_true(fs.ensure_dir("/tmp/codux-private-dir"))
    local ok, err = fs.write_private("/tmp/codux-private-dir/file.txt", "hello")
    assert_true(ok)
    assert_equal(err, nil)
    local modes = {}
    for _, call in ipairs(set_calls) do
      modes[call.mode] = true
    end
    assert_true(modes["rw-------"])
    assert_true(modes["rwx------"])
  end)
end

do
  assert_false(fs.set_private_file(""))
  assert_false(fs.set_private_dir(nil))
end

print("fs_spec.lua: ok")
