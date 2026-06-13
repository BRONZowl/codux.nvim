<h1 align="center">codux.nvim</h1>

<p align="center">
  Codux runs OpenAI Codex in a persistent Neovim floating terminal.
  Send the current file, selected code, diagnostics, or a file explorer target without leaving your editor.
</p>

Closing the popup hides it; it does not kill the Codex session.

## Install

Install and sign in to the Codex CLI:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex login
```

Add codux.nvim with lazy.nvim or LazyVim:

```lua
return {
  "BRONZowl/codux.nvim",
  config = function()
    require("codux").setup()
  end,
}
```

Open Neovim in a project and verify the setup:

```bash
cd ~/Projects/your-project
nvim
```

```vim
:checkhealth codux
:CoduxOpen
```

In LazyVim, `<leader>` is usually Space.

## Requirements

- Neovim with terminal and floating window support
- OpenAI Codex CLI available as `codex`
- lazy.nvim or LazyVim

Optional:

- which-key.nvim for the `<leader>z` group label
- Neo-tree, Oil.nvim, nvim-tree, or mini.files for file explorer targets

Windows users can install Codex with PowerShell:

```powershell
irm https://chatgpt.com/codex/install.ps1 | iex
```

For remote or headless login:

```bash
codex login --device-auth
```

## Usage

| Action | Key | Command |
| --- | --- | --- |
| Open or focus Codex | `<leader>zc` | `:CoduxOpen` |
| Send current file or explorer node | `<leader>zf` | `:CoduxReview` |
| Send selected code | `<leader>zs` | `:CoduxReviewSelection` |
| Send diagnostics and health output | `<leader>zd` | `:CoduxDiagnostics` |
| Hide the popup | `q` or `<C-q>` | `:CoduxClose` |
| Stop Codex | | `:CoduxExit` |

### Send A File

Run `:CoduxReview` or press `<leader>zf`.

Codux sends the active buffer path. If your cursor is in a supported file explorer, Codux sends the highlighted file or directory instead.

### Send A Selection

Select code, then press `<leader>zs`.

You can also run:

```vim
:'<,'>CoduxReviewSelection
```

In normal mode, `<leader>zs` sends the most recent visual selection.

### Send Diagnostics

Run `:CoduxDiagnostics` or press `<leader>zd`.

Codux collects current-buffer diagnostics, the location list, the quickfix list, and headless `:LazyHealth` / `:checkhealth` output. If nothing needs attention, Codux reports `No Issues Found` and exits the popup session.

## Commands

| Command | Description |
| --- | --- |
| `:CoduxOpen` | Open or focus the Codex popup |
| `:CoduxToggle` | Toggle the Codex popup |
| `:CoduxClose` | Hide the popup without stopping Codex |
| `:CoduxExit` | Stop Codex and close the popup |
| `:CoduxReview` | Send current file or explorer node to Codex |
| `:CoduxReviewSelection` | Send selected code to Codex |
| `:CoduxDiagnostics` | Send diagnostics and health output to Codex |
| `:CoduxHealth` | Run codux.nvim health checks |
| `:checkhealth codux` | Run Neovim's health check for codux.nvim |

## File Explorer Support

Codux can detect targets from:

- Neo-tree
- Oil.nvim
- nvim-tree
- mini.files

When no supported explorer target is found, Codux falls back to the active buffer path.

## Configuration

The default setup is enough for most users:

```lua
require("codux").setup()
```

Full defaults:

```lua
require("codux").setup({
  codex_cmd = vim.env.CODEX_CMD or "codex -s workspace-write -a on-request",
  auto_open = true,
  auto_focus = true,
  health_timeout_ms = 10000,

  popup = {
    width = 0.85,
    height = 0.85,
    border = "rounded",
  },

  mappings = {
    open = "<leader>zc",
    review_file = "<leader>zf",
    review_selection = "<leader>zs",
    diagnostics = "<leader>zd",
  },

  explorers = {
    neo_tree = true,
    oil = true,
    nvim_tree = true,
    mini_files = true,
  },
})
```

Use an argument list if you want to avoid shell parsing:

```lua
require("codux").setup({
  codex_cmd = { "codex", "-s", "workspace-write", "-a", "on-request" },
})
```

Set `auto_focus = false` to send prompts without moving focus into the Codex popup.

## Prompt Templates

Prompt templates can be strings with `%{token}` placeholders or functions that return a string:

```lua
require("codux").setup({
  prompts = {
    file = "Review this %{target_type}, identify issues, and suggest or make fixes where appropriate: %{path}",
    review_selection = "Review this selected code from %{relative_path}%{line_range} (%{filetype}):\n\n%{selection}",
    diagnostics = "Explain these %{diagnostics_source} issues for %{relative_path}, identify the likely causes, and suggest fixes:\n\n%{diagnostics}",
  },
})
```

Available prompt tokens:

- `path`
- `absolute_path`
- `relative_path`
- `target_type`
- `target_source`
- `filetype`
- `git_branch`
- `diagnostics`
- `diagnostics_source`
- `line_range`
- `selection`

## Custom Targets

Custom target providers can return a file or directory target before Codux falls back to built-in explorer detection:

```lua
require("codux").setup({
  target_providers = {
    function()
      return {
        path = "/path/to/file.lua",
        type = "file",
        source = "custom",
      }
    end,
  },
})
```

## Local Development

Use a local checkout only when developing the plugin:

```bash
git clone https://github.com/BRONZowl/codux.nvim.git
cd codux.nvim
```

```lua
return {
  dir = "~/Projects/codux.nvim",
  config = function()
    require("codux").setup()
  end,
}
```

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `codex` is not found | Run `codex --version`. If it fails, install the Codex CLI and make sure its install directory is on `PATH`. |
| Browser login does not work | Run `codex login --device-auth`. |
| Selection sends nothing | Select text first, then press `<leader>zs`. From normal mode, `<leader>zs` uses the most recent visual selection. |
| Explorer sends the wrong path | Confirm the explorer is Neo-tree, Oil.nvim, nvim-tree, or mini.files, or add a custom target provider. |
| Popup disappeared | `q`, `<C-q>`, and `:CoduxClose` only hide the popup. Run `:CoduxOpen` to bring it back. |
| Need a clean restart | Run `:CoduxExit`, then `:CoduxOpen`. |
