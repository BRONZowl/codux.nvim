local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_true = h.assert_true

local path_util = require("codux.path_util")

assert_equal(path_util.strip_trailing_slashes("/repo///"), "/repo")
assert_equal(path_util.normalize_absolute_path("/repo/app", "../lib/file.lua"), "/repo/lib/file.lua")
assert_equal(path_util.normalize_absolute_path("/repo", "/tmp/../repo/file.lua"), "/repo/file.lua")
assert_equal(path_util.normalize_relative_directory("./.agents/codux/"), ".agents/codux")
assert_true(path_util.starts_with_path("/repo/lua/init.lua", "/repo"))
assert_false(path_util.starts_with_path("/repo-other/init.lua", "/repo"))
assert_true(path_util.relative_path_escapes_root("../outside"))
assert_false(path_util.relative_path_escapes_root(".agents/codux"))
assert_equal(path_util.path_token("/repo with spaces"), "repo-with-spaces")
assert_equal(path_util.path_token(""), "workspace")
assert_equal(path_util.short_path_token("abcdefghijklmnopqrstuvwxyz", 4), "abcd")

print("path_util_spec.lua: ok")
