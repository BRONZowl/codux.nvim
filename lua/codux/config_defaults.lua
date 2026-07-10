local M = {}

function M.defaults()
  return {
    default_agent_provider = vim.env.CODUX_AGENT_PROVIDER or "codex",
    providers = {
      codex = {
        default_cmd = vim.env.CODEX_CMD or 'codex -s workspace-write -a on-request -c approvals_reviewer="user"',
        auto_cmd = vim.env.CODEX_WORKSPACE_AUTO_CMD
          or 'codex -s workspace-write -a on-request -c approvals_reviewer="auto_review"',
        danger_cmd = vim.env.CODEX_DANGER_FULL_ACCESS_CMD or "codex -s danger-full-access -a never",
      },
      grok = {
        default_cmd = vim.env.GROK_CMD or "grok --sandbox workspace",
        auto_cmd = vim.env.GROK_WORKSPACE_AUTO_CMD or "grok --sandbox workspace --always-approve",
        danger_cmd = vim.env.GROK_DANGER_FULL_ACCESS_CMD or "grok --sandbox off --always-approve",
      },
    },
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

function M.apply_legacy_codex_aliases(config, opts)
  config = type(config) == "table" and config or {}
  opts = type(opts) == "table" and opts or {}
  config.providers = type(config.providers) == "table" and config.providers or {}
  config.providers.codex = type(config.providers.codex) == "table" and config.providers.codex or {}

  local configured_providers = type(opts.providers) == "table" and opts.providers or {}
  local configured_codex = type(configured_providers.codex) == "table" and configured_providers.codex or {}
  local aliases = {
    { legacy = "codex_cmd", current = "default_cmd" },
    { legacy = "workspace_auto_cmd", current = "auto_cmd" },
    { legacy = "danger_full_access_cmd", current = "danger_cmd" },
  }

  for _, alias in ipairs(aliases) do
    if opts[alias.legacy] ~= nil and configured_codex[alias.current] == nil then
      config.providers.codex[alias.current] = opts[alias.legacy]
    end
  end

  return config
end

return M
