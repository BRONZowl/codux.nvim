local h = require("tests.helpers")
local assert_equal = h.assert_equal

local workspace_lifecycle = require("codux.workspace_lifecycle")

assert_equal(workspace_lifecycle.renamed_worktree_path("/repo/worktrees/old", "new"), "/repo/worktrees/new")
assert_equal(
  workspace_lifecycle.retarget_path_after_worktree_move(
    "/repo/worktrees/old/lua/codux/init.lua",
    "/repo/worktrees/old",
    "/repo/worktrees/new"
  ),
  "/repo/worktrees/new/lua/codux/init.lua"
)
assert_equal(
  workspace_lifecycle.retarget_path_after_worktree_move(
    "/repo/other/lua/codux/init.lua",
    "/repo/worktrees/old",
    "/repo/worktrees/new"
  ),
  "/repo/other/lua/codux/init.lua"
)

print("workspace_lifecycle_spec.lua: ok")
