local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_true = h.assert_true

local workspace_git = require("codux.workspace_git")

assert_equal(workspace_git.strip_trailing_slashes("/repo///"), "/repo")
assert_equal(workspace_git.normalize_absolute_path("/repo/app", "../lib/file.lua"), "/repo/lib/file.lua")
assert_equal(workspace_git.normalize_absolute_path("/repo", "/tmp/../repo/file.lua"), "/repo/file.lua")
assert_equal(workspace_git.normalize_relative_directory("./.agents/codux/"), ".agents/codux")
assert_true(workspace_git.starts_with_path("/repo/lua/init.lua", "/repo"))
assert_false(workspace_git.starts_with_path("/repo-other/init.lua", "/repo"))
assert_true(workspace_git.relative_path_escapes_root("../outside"))
assert_false(workspace_git.relative_path_escapes_root(".agents/codux"))
assert_equal(workspace_git.normalize_codex_mode("plan"), "plan")
assert_equal(workspace_git.normalize_codex_mode("execute"), "execute")
assert_equal(workspace_git.normalize_codex_mode("read-only"), nil)
assert_true(workspace_git.inactive_like_status("inactive"))
assert_false(workspace_git.inactive_like_status("active"))
assert_equal(table.concat(workspace_git.prepend_command("tmux", { "display-message", "-p" }), " "), "tmux display-message -p")
assert_equal(workspace_git.path_token("/repo with spaces"), "repo-with-spaces")
assert_equal(workspace_git.path_token(""), "workspace")
assert_equal(workspace_git.short_path_token("abcdefghijklmnopqrstuvwxyz", 4), "abcd")
assert_equal(workspace_git.vimscript_string('a"b\\c'), '"a\\"b\\\\c"')
assert_equal(workspace_git.luaeval_expr("require('codux').health_info()"), "luaeval(\"require('codux').health_info()\")")
assert_true(workspace_git.launch_socket_token():match("^[0-9a-f]+$") ~= nil)

print("workspace_git_spec.lua: ok")
