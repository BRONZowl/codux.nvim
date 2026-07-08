local h = require("tests.helpers")
local assert_equal = h.assert_equal
local assert_false = h.assert_false
local assert_true = h.assert_true

local residue = require("codux.workspace_residue")

local function with_fs(fs, callback)
  local old_isdirectory = vim.fn.isdirectory
  local old_readdir = vim.fn.readdir
  local old_delete = vim.fn.delete
  local removed = {}

  vim.fn.isdirectory = function(path)
    local node = fs[path]
    return type(node) == "table" and node.type == "dir" and 1 or 0
  end
  vim.fn.readdir = function(path)
    local node = fs[path]
    if type(node) ~= "table" or node.type ~= "dir" then
      error("not a directory")
    end
    local entries = {}
    for name, _ in pairs(node.children or {}) do
      table.insert(entries, name)
    end
    table.sort(entries)
    return entries
  end
  vim.fn.delete = function(path, flags)
    if flags ~= "d" then
      return 1
    end
    local node = fs[path]
    if type(node) ~= "table" or node.type ~= "dir" then
      return 1
    end
    if next(node.children or {}) ~= nil then
      return 1
    end
    fs[path] = nil
    local parent, name = path:match("^(.*)/([^/]+)$")
    if fs[parent] and fs[parent].children then
      fs[parent].children[name] = nil
    end
    table.insert(removed, path)
    return 0
  end

  local ok, err = pcall(function()
    callback(removed)
  end)
  vim.fn.isdirectory = old_isdirectory
  vim.fn.readdir = old_readdir
  vim.fn.delete = old_delete
  if not ok then
    error(err, 0)
  end
end

local function dir(children)
  return { type = "dir", children = children or {} }
end

local function file()
  return { type = "file" }
end

local function runtime(opts)
  opts = type(opts) == "table" and opts or {}
  local state_data = opts.state_data or { projects = {} }
  return {
    worktree_config = function()
      return { directory = "../codux-worktrees" }
    end,
    read_state = function()
      return state_data, nil
    end,
    write_state = function(_, next_state)
      state_data = next_state
      return true, nil
    end,
    system = function(args)
      local command = table.concat(args, " ")
      if opts.git_dirs and opts.git_dirs[args[3]] then
        return "true\n", 0
      end
      return "", 1
    end,
    state_data = function()
      return state_data
    end,
  }
end

do
  local fs = {
    ["/codux-worktrees"] = dir({
      ["debug-builder"] = true,
      ["debug-reviewer"] = true,
      ["orphan-worktree"] = true,
      ["real-worktree"] = true,
    }),
    ["/codux-worktrees/debug-builder"] = dir({ [".agents"] = true }),
    ["/codux-worktrees/debug-builder/.agents"] = dir({ codux = true }),
    ["/codux-worktrees/debug-builder/.agents/codux"] = dir(),
    ["/codux-worktrees/debug-reviewer"] = dir({ note = true }),
    ["/codux-worktrees/debug-reviewer/note"] = file(),
    ["/codux-worktrees/orphan-worktree"] = dir(),
    ["/codux-worktrees/real-worktree"] = dir(),
  }
  with_fs(fs, function()
    local rt = runtime({
      git_dirs = {
        ["/codux-worktrees/orphan-worktree"] = true,
        ["/codux-worktrees/real-worktree"] = true,
      },
      state_data = {
        projects = {
          ["/codux-worktrees/debug-builder"] = { workspaces = {} },
          ["/codux-worktrees/real-worktree"] = { workspaces = { real = { name = "real" } } },
          ["/repo"] = { workspaces = {} },
        },
      },
    })

    local found = residue.inspect(rt, "/repo")
    assert_equal(found.count, 4)
    assert_equal(#found.empty_project_buckets, 1)
    assert_equal(found.empty_project_buckets[1].path, "/codux-worktrees/debug-builder")
    assert_equal(#found.leftover_directories, 3)
    assert_true(found.leftover_directories[1].cleanable)
    assert_false(found.leftover_directories[2].cleanable)
    assert_equal(found.leftover_directories[3].kind, "orphaned_worktree")
  end)
end

do
  local fs = {
    ["/codux-worktrees"] = dir({ repo = true }),
    ["/codux-worktrees/repo"] = dir({
      ["empty-shell"] = true,
      ["orphan-worktree"] = true,
      ["real-worktree"] = true,
    }),
    ["/codux-worktrees/repo/empty-shell"] = dir(),
    ["/codux-worktrees/repo/orphan-worktree"] = dir(),
    ["/codux-worktrees/repo/real-worktree"] = dir(),
  }
  with_fs(fs, function()
    local rt = runtime({
      git_dirs = {
        ["/codux-worktrees/repo/orphan-worktree"] = true,
        ["/codux-worktrees/repo/real-worktree"] = true,
      },
      state_data = {
        projects = {
          ["/codux-worktrees/repo/empty-bucket"] = { workspaces = {} },
          ["/codux-worktrees/repo/real-worktree"] = { workspaces = { real = { name = "real" } } },
        },
      },
    })

    local found = residue.inspect(rt, "/repo")
    assert_equal(found.count, 3)
    assert_equal(#found.empty_project_buckets, 1)
    assert_equal(found.empty_project_buckets[1].path, "/codux-worktrees/repo/empty-bucket")
    assert_equal(#found.leftover_directories, 2)
    assert_equal(found.leftover_directories[1].path, "/codux-worktrees/repo/empty-shell")
    assert_true(found.leftover_directories[1].cleanable)
    assert_equal(found.leftover_directories[2].path, "/codux-worktrees/repo/orphan-worktree")
    assert_equal(found.leftover_directories[2].kind, "orphaned_worktree")
    assert_false(found.leftover_directories[2].cleanable)
  end)
end

do
  local fs = {
    ["/codux-worktrees"] = dir({ ["debug-builder"] = true, ["debug-reviewer"] = true }),
    ["/codux-worktrees/debug-builder"] = dir({ [".agents"] = true }),
    ["/codux-worktrees/debug-builder/.agents"] = dir({ codux = true }),
    ["/codux-worktrees/debug-builder/.agents/codux"] = dir(),
    ["/codux-worktrees/debug-reviewer"] = dir({ note = true }),
    ["/codux-worktrees/debug-reviewer/note"] = file(),
  }
  with_fs(fs, function(removed)
    local rt = runtime({
      state_data = {
        projects = {
          ["/codux-worktrees/debug-builder"] = { workspaces = {} },
          ["/codux-worktrees/debug-reviewer"] = { workspaces = {} },
        },
      },
    })

    local ok, result = residue.cleanup(rt, "/repo")
    assert_true(ok)
    assert_equal(result.removed_buckets, 2)
    assert_equal(result.removed_directories, 1)
    assert_equal(result.skipped_directories, 1)
    assert_equal(rt.state_data().projects["/codux-worktrees/debug-builder"], nil)
    assert_equal(removed[#removed], "/codux-worktrees/debug-builder")
  end)
end

print("workspace_residue_spec.lua: ok")
