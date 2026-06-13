# codux.nvim

```text
     _            _
 ___| | ___   __| |_   ___  __
/ __| |/ _ \ / _` | | | \ \/ /
| (__| | (_) | (_| | |_| |>  <
\___|_|\___/ \__,_|\__,_/_/\_\

Codex in a Neovim popup.
Send files, selections, diagnostics, and explorer targets without leaving your editor.
```

```text
nvim buffer / explorer / selection / diagnostics
        |
        v
codux.nvim floating terminal
        |
        v
OpenAI Codex CLI
```

No tmux launcher required. Codux starts Codex directly inside Neovim and keeps the session alive when you hide the popup.

## Quick Start

Install the Codex CLI:

```bash
$ curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

Sign in:

```bash
$ codex login
```

Add the plugin with lazy.nvim or LazyVim:

```lua
return {
  "BRONZowl/codux.nvim",
  config = function()
    require("codux").setup()
  end,
}
```

Open a project:

```bash
$ cd ~/Projects/your-project
$ nvim
```

Check the install:

```vim
:checkhealth codux
```

Start Codex:

```vim
:CoduxOpen
```

Or press `<leader>zc`.

## Requirements

```text
required:
  - Neovim with terminal and floating window support
  - Codex CLI on PATH as `codex`
  - lazy.nvim or LazyVim

optional:
  - which-key.nvim for the <leader>z group label
  - Neo-tree, Oil.nvim, nvim-tree, or mini.files for explorer targets
```

On Windows, install Codex natively with PowerShell or use WSL2 for a Linux-style setup:

```powershell
irm https://chatgpt.com/codex/install.ps1 | iex
```

For remote or headless machines where browser login is awkward:

```bash
$ codex login --device-auth
```

## Daily Use

```text
open       <leader>zc     open or focus the Codex popup
file       <leader>zf     send current file or explorer node
selection  <leader>zs     send selected code
diagnose   <leader>zd     send diagnostics, quickfix, location list, and health output
hide       q or <C-q>     hide the popup, keep Codex running
exit       :CoduxExit     stop Codex and clear the terminal
```

In LazyVim, `<leader>` is usually Space.

### Open Codex

```vim
:CoduxOpen
```

The popup opens as a floating terminal. Closing it with `q`, `<C-q>`, or `:CoduxClose` hides the window but leaves the Codex process alive.

### Send A File

```vim
:CoduxReview
```

Or press `<leader>zf`.

Codux sends the active buffer path. If your cursor is in a supported file explorer, Codux sends the highlighted file or directory instead.

### Send A Selection

Select code, then press `<leader>zs`.

```text
visual select -> <leader>zs -> Codex receives file path, line range, and code
```

You can also use the command:

```vim
:'<,'>CoduxReviewSelection
```

In normal mode, `<leader>zs` sends the most recent visual selection.

### Send Diagnostics

```vim
:CoduxDiagnostics
```

Or press `<leader>zd`.

Codux collects current-buffer diagnostics, the location list, the quickfix list, and headless `:LazyHealth` / `:checkhealth` output. If nothing needs attention, Codux reports `No Issues Found` and exits the popup session.

## Commands

```text
:CoduxOpen              open or focus the Codex popup
:CoduxToggle            toggle the Codex popup
:CoduxClose             hide the popup without stopping Codex
:CoduxExit              stop Codex and close the popup
:CoduxReview            send current file or explorer node to Codex
:CoduxReviewSelection   send selected code to Codex
:CoduxDiagnostics       send diagnostics and health output to Codex
:CoduxHealth            run codux.nvim health checks
:checkhealth codux      run Neovim's health check for codux.nvim
```

## Keymaps

| Mode | Key | Action |
| --- | --- | --- |
| Normal | `<leader>zc` | Open or focus the Codex popup |
| Normal | `<leader>zf` | Review current file or explorer node |
| Normal / Visual | `<leader>zs` | Send selected code to Codex |
| Normal | `<leader>zd` | Send diagnostics, lists, and health output |

## Explorer Targets

Codux detects supported file explorer buffers and sends the highlighted file or directory instead of the explorer buffer itself.

```text
supported explorers:
  - Neo-tree
  - Oil.nvim
  - nvim-tree
  - mini.files
```

When no explorer target is found, Codux falls back to the active buffer path.

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

Use an argument list when you want to avoid shell parsing:

```lua
require("codux").setup({
  codex_cmd = { "codex", "-s", "workspace-write", "-a", "on-request" },
})
```

Set `auto_focus = false` if you want send actions to keep your cursor in the original window.

## Prompt Templates

Prompt templates can be strings with `%{token}` placeholders or functions that return a string.

```lua
require("codux").setup({
  prompts = {
    file = "Review this %{target_type}, identify issues, and suggest or make fixes where appropriate: %{path}",
    review_selection = "Review this selected code from %{relative_path}%{line_range} (%{filetype}):\n\n%{selection}",
    diagnostics = "Explain these %{diagnostics_source} issues for %{relative_path}, identify the likely causes, and suggest fixes:\n\n%{diagnostics}",
  },
})
```

Available tokens:

```text
path
absolute_path
relative_path
target_type
target_source
filetype
git_branch
diagnostics
diagnostics_source
line_range
selection
```

## Custom Targets

Custom target providers can return a file or directory target before Codux falls back to built-in explorer detection.

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

## Local Checkout

Use this only when developing the plugin from a local clone:

```bash
$ git clone https://github.com/BRONZowl/codux.nvim.git
$ cd codux.nvim
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

```text
codex not found:
  Run `codex --version`.
  If that fails, install the Codex CLI and make sure its install directory is on PATH.

login does not open a browser:
  Use `codex login --device-auth`.

selection sends nothing:
  Select text first, then press <leader>zs.
  From normal mode, <leader>zs uses the most recent visual selection.

explorer sends the wrong path:
  Confirm the explorer is one of Neo-tree, Oil.nvim, nvim-tree, or mini.files.
  Unsupported explorers fall back to the active buffer path unless you add a custom target provider.

popup disappeared:
  `q`, `<C-q>`, and `:CoduxClose` only hide the popup.
  Use `:CoduxOpen` to bring the same Codex session back.

need a clean Codex restart:
  Run `:CoduxExit`, then `:CoduxOpen`.
```

## Health Check

```vim
:checkhealth codux
```

The health check verifies terminal support, floating window support, the configured Codex command, popup state, and terminal job state.
