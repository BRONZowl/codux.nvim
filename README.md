<h1 align="center">codux.nvim</h1>

<table align="center">
<tr>
<td>

<pre>
+----------------------------------------------+
|                  codux.nvim                  |
|           Neovim -> tmux -> Codex            |
|   Send the file. Switch windows. Keep moving.|
+----------------------------------------------+
</pre>

</td>
</tr>
</table>

`codux.nvim` gives Neovim a fast tmux-first Codex workflow. It opens Codex in a dedicated tmux window, sends files or selections into that session, and switches you to Codex after the prompt is delivered.

Built for LazyVim, friendly to Neo-tree, and small enough to understand at a glance.

<h2 align="center">What You Get</h2>

<table align="center">
<tr>
<th>Feature</th>
<th>What it does</th>
</tr>
<tr>
<td>tmux window</td>
<td>Keeps Codex in a dedicated <code>CODEX</code> window</td>
</tr>
<tr>
<td>File review</td>
<td>Sends the current file to Codex</td>
</tr>
<tr>
<td>File fix</td>
<td>Asks Codex to find and fix issues in the current file</td>
</tr>
<tr>
<td>Visual review</td>
<td>Sends selected code to Codex</td>
</tr>
<tr>
<td>Neo-tree support</td>
<td>Sends the highlighted Neo-tree file or directory</td>
</tr>
<tr>
<td>Auto-switch</td>
<td>Jumps to the Codex tmux window after sending</td>
</tr>
</table>

<h2 align="center">Requirements</h2>

- Linux or another Unix-like environment
- tmux
- Neovim
- OpenAI Codex CLI available as `codex`
- Lazy.nvim or LazyVim for the plugin spec examples below

<h2 align="center">Fast Install</h2>

Clone the repo:

```bash
git clone https://github.com/BRONZowl/codux.nvim.git
cd codux.nvim
```

Install the launcher:

```bash
./installcodux.sh
```

The installer:

- Copies `bin/codux` to `~/.local/bin/codux`.
- Makes the launcher executable.
- Adds `~/.local/bin` to common Linux shell startup files when needed:
  - `~/.bashrc`
  - `~/.zshrc`
  - `~/.profile`
  - `~/.bash_profile`
  - `~/.config/fish/config.fish` when fish config exists

Restart your shell after installing, or source your rc file.

<h2 align="center">LazyVim Setup</h2>

Create:

```bash
nvim ~/.config/nvim/lua/plugins/codux.lua
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

That is enough for the default workflow.

<h2 align="center">Run It</h2>

Start tmux, open a project, then open Neovim:

```bash
tmux
cd ~/Projects/your-project
nvim
```

Press `<leader>zc` to open or switch to Codex.

```text
Neovim buffer / Neo-tree node / visual selection
        |
        v
tmux send-keys
        |
        v
Codex window: CODEX
```

<h2 align="center">Keymaps</h2>

In LazyVim, `<leader>` is usually Space.

| Key | Action |
| --- | --- |
| `<leader>zc` | Open or switch to the Codex tmux window |
| `<leader>zf` | Send current file or selected Neo-tree node for review, then switch to Codex |
| `<leader>zx` | Ask Codex to fix the current file or selected Neo-tree node, then switch to Codex |
| `<leader>zs` | Send selected code to Codex, then switch to Codex |

<h2 align="center">Neo-tree</h2>

Codux detects when your cursor is in a Neo-tree window.

When Neo-tree is focused:

- `<leader>zf` reviews the highlighted file or directory.
- `<leader>zx` asks Codex to fix the highlighted file or directory.

When Neo-tree is not focused, Codux uses the active buffer path instead.

<h2 align="center">tmux And Codex</h2>

The `codux` launcher must run inside tmux.

Default behavior:

```bash
codex -s workspace-write -a on-request
```

Default tmux window:

```text
CODEX
```

Override the Codex command:

```bash
export CODEX_CMD="codex"
```

Rename the tmux window:

```bash
export CODUX_WINDOW_NAME="AI"
```

If you rename the tmux window, match it in Neovim:

```lua
require("codux").setup({
  tmux_window = "AI",
})
```

<h2 align="center">Custom Keymaps</h2>

```lua
require("codux").setup({
  tmux_window = "CODEX",
  mappings = {
    open = "<leader>zc",
    review_file = "<leader>zf",
    fix_file = "<leader>zx",
    review_selection = "<leader>zs",
  },
})
```

<h2 align="center">Manual Launcher Install</h2>

Use this instead of `./installcodux.sh` if you want to do the launcher setup yourself:

```bash
mkdir -p ~/.local/bin
cp bin/codux ~/.local/bin/codux
chmod +x ~/.local/bin/codux
```

Then make sure this is in your shell rc file:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

<h2 align="center">Notes</h2>

- Keep the `CODEX` tmux window open while using Codux.
- Neovim sends prompts with `tmux send-keys`.
- Send mappings switch to the configured Codex tmux window after delivery.
