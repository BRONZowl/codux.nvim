local M = {}

function M.defaults()
  return {
    codex_cmd = vim.env.CODEX_CMD or 'codex -s workspace-write -a on-request -c approvals_reviewer="user"',
    workspace_auto_cmd = vim.env.CODEX_WORKSPACE_AUTO_CMD
      or 'codex -s workspace-write -a on-request -c approvals_reviewer="auto_review"',
    danger_full_access_cmd = vim.env.CODEX_DANGER_FULL_ACCESS_CMD or "codex -s danger-full-access -a never",
    default_initial_mode = "plan",
    auto_open = true,
    auto_focus = true,
    popup = {
      width = 0.85,
      height = 0.85,
      border = "rounded",
      lock_focus = true,
    },
    working_idle_ms = 3000,
    health_timeout_ms = 10000,
    token_monitor = {
      enabled = true,
      refresh_ms = 60000,
      timeout_ms = 5000,
    },
    workspaces = {
      enabled = true,
      tmux_cmd = vim.env.TMUX_CMD or "tmux",
      state_file = nil,
      worktree = {
        directory = "../codux-worktrees",
        branch_prefix = "dev/",
      },
      instruction_files = {
        enabled = true,
        directory = ".agents/codux",
      },
    },
    mappings = {
      open = "<leader>zc",
      review_file = "<leader>zf",
      review_selection = "<leader>zs",
      diagnostics = "<leader>zd",
      diff = "<leader>zg",
      mission = "",
      missions = "<leader>zM",
      mode = "<leader>zp",
    },
    prompts = {
      file = "Review this %{target_type}, identify issues, and suggest or make fixes where appropriate: %{path}",
      review_selection = "Review this selected code from %{relative_path}%{line_range} (%{filetype}):\n\n%{selection}",
      diagnostics = "Explain these %{diagnostics_source} issues for %{relative_path}, identify the likely causes, and suggest fixes:\n\n%{diagnostics}",
      git_diff = "Review these Git changes on branch %{git_branch} in %{relative_path}. Identify issues, risks, and concrete improvements:\n\n%{git_diff}",
    },
    explorers = {
      neo_tree = true,
      oil = true,
      nvim_tree = true,
      mini_files = true,
    },
    target_providers = {},
  }
end

return M
