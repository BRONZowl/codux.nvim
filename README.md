<h1 align="center">codux.nvim</h1>

<p align="center">
  <strong>Codex in a Neovim popup. Send context without leaving your editor.</strong>
</p>

<p align="center">
  <code>files</code> · <code>selections</code> · <code>diagnostics</code> · <code>Neo-tree</code> · <code>floating terminal</code>
</p>

<h2 align="center">What You Get</h2>

<table align="center">
<tr>
<th>Feature</th>
<th>What it does</th>
</tr>
<tr>
<td>Codex popup</td>
<td>Runs Codex in a persistent Neovim floating terminal</td>
</tr>
<tr>
<td>Hide, do not kill</td>
<td>Closing the popup keeps the Codex session alive</td>
</tr>
<tr>
<td>File review/fix</td>
<td>Sends the current file or file explorer node to Codex</td>
</tr>
<tr>
<td>Selection review</td>
<td>Sends selected code with file path and line range</td>
</tr>
<tr>
<td>Diagnostics</td>
<td>Sends current-buffer diagnostics, location list, quickfix entries, and headless <code>:LazyHealth</code>/<code>:checkhealth</code> output without opening health buffers</td>
</tr>
<tr>
<td>Explorer targets</td>
<td>Supports Neo-tree, Oil.nvim, nvim-tree, mini.files, and custom providers</td>
</tr>
<tr>
<td>Health check</td>
<td>Checks Codex CLI, terminal support, popup state, and job state</td>
</tr>
</table>

<h2 align="center">Requirements</h2>

- Neovim with terminal and floating window support
- OpenAI Codex CLI available as `codex`, or a custom command configured with `codex_cmd`
- lazy.nvim or LazyVim for the plugin spec examples below

<h2 align="center">Install</h2>

Clone the repo:

```bash
git clone https://github.com/BRONZowl/codux.nvim.git
cd codux.nvim
```

Use this if you cloned the repo locally:

```lua
return {
  dir = "~/Projects/codux.nvim",
  config = function()
    require("codux").setup()
  end,
}
```

Use this if you install from GitHub:

```lua
return {
  "BRONZowl/codux.nvim",
  config = function()
    require("codux").setup()
  end,
}
```

No tmux launcher is required. Codux starts Codex directly inside Neovim.

<h2 align="center">Run It</h2>

Open Neovim in a project:

```bash
cd ~/Projects/your-project
nvim
```

Press `<leader>zc` to open the Codex popup.

```text
Neovim file / explorer node / visual selection / diagnostics
        |
        v
codux.nvim floating terminal
        |
        v
Codex CLI
```

<h2 align="center">Keymaps</h2>

In LazyVim, `<leader>` is usually Space.

| Key | Action |
| --- | --- |
| `<leader>zc` | Open or focus the Codex popup |
| `<leader>zf` | Review current file or explorer node, identify issues, and suggest fixes |
| `<leader>zs` | Send selected code to Codex |
| `<leader>zd` | Send diagnostics, location list, quickfix entries, and headless health output to Codex |

<h2 align="center">Commands</h2>

```vim
:CoduxOpen
:CoduxToggle
:CoduxClose
:CoduxExit
:CoduxReview
:CoduxReviewSelection
:CoduxDiagnostics
:CoduxHealth
:checkhealth codux
```

`CoduxClose` hides the popup and keeps Codex running. `CoduxExit` stops Codex and clears the terminal.

<h2 align="center">File Explorer Support</h2>

Codux detects supported file explorer buffers and sends the highlighted file or directory instead of the explorer buffer path.

Built-in providers:

- Neo-tree
- Oil.nvim
- nvim-tree
- mini.files

When no supported explorer target is found, Codux falls back to the active buffer path.

<h2 align="center">Configuration</h2>

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

Prompt templates can be strings with `%{token}` placeholders or functions that return a string:

```lua
require("codux").setup({
  prompts = {
    file = "Review this %{target_type}, identify issues, and suggest or make fixes where appropriate: %{path}",
    review_selection = "Review this selected code from %{relative_path}%{line_range} (%{filetype}):\n\n%{selection}",
    diagnostics = "Explain these %{diagnostics_source} issues for %{relative_path}:\n\n%{diagnostics}",
  },
})
```

Available prompt tokens include `path`, `absolute_path`, `relative_path`, `target_type`, `target_source`, `filetype`, `git_branch`, `diagnostics`, `diagnostics_source`, `line_range`, and `selection`.

`codex_cmd` can be a shell command string or an argument list:

```lua
require("codux").setup({
  codex_cmd = { "codex", "-s", "workspace-write", "-a", "on-request" },
})
```

Custom target providers can return a file or directory target:

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

<h2 align="center">Notes</h2>

- The popup can be hidden without losing the Codex session.
- Send actions auto-open the popup when needed.
- Set `auto_focus = false` to send prompts without jumping into the popup.
- Press `q` in normal mode or `<C-q>` from normal/terminal mode inside the popup to hide it.
