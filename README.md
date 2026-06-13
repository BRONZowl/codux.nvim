<div align="center">

# codux.nvim

<strong>OpenAI Codex, wired into Neovim as a persistent floating terminal.</strong>

<br>
<br>

[![Neovim](https://img.shields.io/badge/Neovim-floating%20terminal-57A143?style=for-the-badge&logo=neovim&logoColor=white)](#requirements)
[![Codex CLI](https://img.shields.io/badge/Codex-CLI-111827?style=for-the-badge)](#install)
[![lazy.nvim](https://img.shields.io/badge/lazy.nvim-ready-7C3AED?style=for-the-badge)](#install)
[![License](https://img.shields.io/badge/license-MIT-0F766E?style=for-the-badge)](LICENSE)

<br>

<pre>
+================================================+
|                  CODUX.NVIM                    |
|------------------------------------------------|
|  send context -> keep flow -> stay in Neovim   |
|  files | selections | diagnostics | explorers  |
+================================================+
</pre>

</div>

```text
  file buffer         visual selection        diagnostics        explorer node
      \                    |                     |                    /
       \                   |                     |                   /
        +------------------+---------------------+------------------+
                                   |
                                   v
                     codux.nvim floating terminal
                                   |
                                   v
                             OpenAI Codex CLI
```

Codux opens Codex inside Neovim, sends rich editor context on demand, and lets you hide the popup without killing the session. No tmux launcher. No context switching. No ceremony.

## Install

<table>
<tr>
<td width="50%">

<strong>1. Install Codex CLI</strong>

<pre><code class="language-bash">$ curl -fsSL https://chatgpt.com/codex/install.sh | sh
$ codex login</code></pre>

</td>
<td width="50%">

<strong>2. Add codux.nvim</strong>

<pre><code class="language-lua">return {
  "BRONZowl/codux.nvim",
  config = function()
    require("codux").setup()
  end,
}</code></pre>

</td>
</tr>
</table>

Then open a project and light it up:

```bash
$ cd ~/Projects/your-project
$ nvim
```

```vim
:checkhealth codux
:CoduxOpen
```

Press <kbd>&lt;leader&gt;zc</kbd> any time you want the popup back.

> In LazyVim, `<leader>` is usually Space.

## What You Get

<table>
<tr>
<td width="33%">

<strong>Persistent Codex popup</strong>

Hide the floating terminal without killing Codex. Bring the same session back with <code>:CoduxOpen</code>.

</td>
<td width="33%">

<strong>Context launchers</strong>

Send the current file, explorer target, selected code, diagnostics, quickfix items, and health output.

</td>
<td width="33%">

<strong>Explorer aware</strong>

Neo-tree, Oil.nvim, nvim-tree, and mini.files targets are detected before falling back to the active buffer.

</td>
</tr>
<tr>
<td width="33%">

<strong>LazyVim friendly</strong>

Default mappings live under <code>&lt;leader&gt;z</code> and register cleanly with which-key when it is available.

</td>
<td width="33%">

<strong>Prompt templates</strong>

Customize prompts with tokens like <code>%{relative_path}</code>, <code>%{line_range}</code>, <code>%{diagnostics}</code>, and <code>%{selection}</code>.

</td>
<td width="33%">

<strong>Simple health checks</strong>

<code>:checkhealth codux</code> verifies terminal support, floating windows, Codex command setup, popup state, and job state.

</td>
</tr>
</table>

## Command Deck

```text
+------------------------+----------------+----------------------------------------------+
| Move                   | Key            | Result                                       |
+------------------------+----------------+----------------------------------------------+
| Open Codex             | <leader>zc     | Open or focus the floating Codex terminal    |
| Review file            | <leader>zf     | Send current file or explorer target         |
| Review selection       | <leader>zs     | Send selected code with file and line range  |
| Diagnose project       | <leader>zd     | Send diagnostics, lists, and health output   |
| Hide popup             | q / <C-q>      | Hide Codex, keep the session alive           |
| Stop Codex             | :CoduxExit     | Stop Codex and clear the terminal            |
+------------------------+----------------+----------------------------------------------+
```

## First Run Flow

### Open Codex

```vim
:CoduxOpen
```

Codux starts Codex in a floating terminal. If the popup is hidden later, `:CoduxOpen` brings the existing session back.

### Send A File

```vim
:CoduxReview
```

Or press <kbd>&lt;leader&gt;zf</kbd>.

Codux sends the active buffer path. From a supported explorer, it sends the highlighted file or directory instead.

### Send A Selection

Select code, then press <kbd>&lt;leader&gt;zs</kbd>.

```text
visual selection
      |
      v
file path + line range + selected code
      |
      v
Codex prompt
```

You can also use the command form:

```vim
:'<,'>CoduxReviewSelection
```

In normal mode, `<leader>zs` sends the most recent visual selection.

### Send Diagnostics

```vim
:CoduxDiagnostics
```

Or press <kbd>&lt;leader&gt;zd</kbd>.

Codux collects current-buffer diagnostics, the location list, the quickfix list, and headless `:LazyHealth` / `:checkhealth` output. If nothing needs attention, Codux reports `No Issues Found` and exits the popup session.

## Commands

| Command | What it does |
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

## Keymaps

| Mode | Key | Action |
| --- | --- | --- |
| Normal | `<leader>zc` | Open or focus the Codex popup |
| Normal | `<leader>zf` | Review current file or explorer node |
| Normal / Visual | `<leader>zs` | Send selected code to Codex |
| Normal | `<leader>zd` | Send diagnostics, lists, and health output |

## Requirements

```text
required
  Neovim with terminal and floating window support
  Codex CLI available on PATH as `codex`
  lazy.nvim or LazyVim

optional
  which-key.nvim for the <leader>z group label
  Neo-tree, Oil.nvim, nvim-tree, or mini.files for explorer targets
```

Windows users can install Codex natively with PowerShell:

```powershell
irm https://chatgpt.com/codex/install.ps1 | iex
```

Remote or headless login:

```bash
$ codex login --device-auth
```

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

## Explorer Targets

```text
detected automatically
  Neo-tree
  Oil.nvim
  nvim-tree
  mini.files

fallback
  active buffer path
```

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

| Problem | Fix |
| --- | --- |
| `codex` is not found | Run `codex --version`. If it fails, install the Codex CLI and make sure its install directory is on PATH. |
| Browser login does not work | Run `codex login --device-auth`. |
| Selection sends nothing | Select text first, then press `<leader>zs`. From normal mode, `<leader>zs` uses the most recent visual selection. |
| Explorer sends the wrong path | Confirm the explorer is Neo-tree, Oil.nvim, nvim-tree, or mini.files, or add a custom target provider. |
| Popup disappeared | `q`, `<C-q>`, and `:CoduxClose` only hide the popup. Run `:CoduxOpen` to bring the session back. |
| Need a clean restart | Run `:CoduxExit`, then `:CoduxOpen`. |

## Health Check

```vim
:checkhealth codux
```

The health check verifies terminal support, floating window support, the configured Codex command, popup state, and terminal job state.
