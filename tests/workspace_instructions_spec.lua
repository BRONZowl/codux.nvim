local h = require("tests.helpers")
local fixtures = require("tests.workspace_fixtures")
local assert_equal = h.assert_equal
local assert_true = h.assert_true
local assert_false = h.assert_false
local assert_contains = h.assert_contains

local runtime_mod = require("codux.workspace_runtime")

local default_workspace_config = fixtures.default_workspace_config

do
  local calls = {}
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function(args)
      table.insert(calls, table.concat(args, " "))
      return "", 0
    end,
  })

  local status = runtime:workspace_instruction_ignore_status("/repo")
  assert_equal(status.status, "ignored")
  assert_equal(status.relative_dir, ".agents/codux")
  assert_equal(status.rule, ".agents/")
  assert_equal(calls[1], "git -C /repo check-ignore --quiet -- .agents/codux/.codux-ignore-check")
end

do
  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })

  local status = runtime:workspace_instruction_ignore_status("/repo")
  assert_equal(status.status, "not_ignored")
  assert_contains(runtime:workspace_instruction_ignore_warning("/repo"), "run :CoduxWorkspaceIgnore")
end

do
  local calls = 0
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            enabled = false,
          },
        },
      }
    end,
    system = function()
      calls = calls + 1
      return "", 1
    end,
  })

  assert_equal(runtime:workspace_instruction_ignore_status("/repo").status, "skipped")
  assert_equal(calls, 0)
end

do
  local checked
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            directory = "codux-workspaces",
          },
        },
      }
    end,
    system = function(args)
      checked = table.concat(args, " ")
      return "", 1
    end,
  })

  local status = runtime:workspace_instruction_ignore_status("/repo")
  assert_equal(status.status, "not_ignored")
  assert_equal(status.rule, "codux-workspaces/")
  assert_equal(checked, "git -C /repo check-ignore --quiet -- codux-workspaces/.codux-ignore-check")
end

do
  local calls = 0
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            directory = "/tmp/codux-workspaces",
          },
        },
      }
    end,
    system = function()
      calls = calls + 1
      return "", 1
    end,
  })

  assert_equal(runtime:workspace_instruction_ignore_status("/repo").status, "skipped")
  assert_equal(calls, 0)
end

do
  local calls = 0
  local runtime = runtime_mod.new({
    get_config = function()
      return {
        workspaces = {
          instruction_files = {
            directory = "../codux-workspaces",
          },
        },
      }
    end,
    system = function()
      calls = calls + 1
      return "", 1
    end,
  })

  assert_equal(runtime:workspace_instruction_ignore_status("/repo").status, "skipped")
  assert_equal(calls, 0)
end

do
  local messages = {}
  local runtime = runtime_mod.new({
    state = {},
    get_config = default_workspace_config,
    notify = function(message)
      table.insert(messages, message)
    end,
    system = function()
      return "", 1
    end,
  })

  assert_true(runtime:warn_workspace_instruction_ignore("/repo"))
  assert_false(runtime:warn_workspace_instruction_ignore("/repo"))
  assert_equal(#messages, 1)
  assert_contains(messages[1], "Add .agents/ to .gitignore")
end

do
  local old_filereadable = vim.fn.filereadable
  local old_writefile = vim.fn.writefile
  local written_path
  local written_lines
  vim.fn.filereadable = function()
    return 0
  end
  vim.fn.writefile = function(lines, path)
    written_lines = lines
    written_path = path
    return 0
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.writefile = old_writefile

  assert_true(ok)
  assert_equal(message, "Added .agents/ to .gitignore")
  assert_equal(written_path, "/repo/.gitignore")
  assert_equal(written_lines[#written_lines], ".agents/")
end

do
  local old_filereadable = vim.fn.filereadable
  local old_readfile = vim.fn.readfile
  local old_writefile = vim.fn.writefile
  local written_lines
  vim.fn.filereadable = function()
    return 1
  end
  vim.fn.readfile = function()
    return { "*.log" }
  end
  vim.fn.writefile = function(lines)
    written_lines = lines
    return 0
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 0
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.readfile = old_readfile
  vim.fn.writefile = old_writefile

  assert_true(ok)
  assert_equal(message, "Added .agents/ to .gitignore")
  assert_equal(written_lines[#written_lines], ".agents/")
end

do
  local old_filereadable = vim.fn.filereadable
  local old_readfile = vim.fn.readfile
  local old_writefile = vim.fn.writefile
  local wrote = false
  vim.fn.filereadable = function()
    return 1
  end
  vim.fn.readfile = function()
    return { ".agents/" }
  end
  vim.fn.writefile = function()
    wrote = true
    return 0
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.readfile = old_readfile
  vim.fn.writefile = old_writefile

  assert_true(ok)
  assert_equal(message, "Codux workspace instructions are already ignored by Git")
  assert_false(wrote)
end

do
  local old_filereadable = vim.fn.filereadable
  local old_writefile = vim.fn.writefile
  vim.fn.filereadable = function()
    return 0
  end
  vim.fn.writefile = function()
    return -1
  end

  local runtime = runtime_mod.new({
    get_config = default_workspace_config,
    system = function()
      return "", 1
    end,
  })
  local ok, message = runtime:ensure_workspace_instruction_gitignore("/repo")
  vim.fn.filereadable = old_filereadable
  vim.fn.writefile = old_writefile

  assert_false(ok)
  assert_equal(message, "Failed to update .gitignore")
end

print("workspace_instructions_spec.lua: ok")
