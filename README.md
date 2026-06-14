<h1 align="center">codux.nvim</h1>

<p align="center">
  Codux runs OpenAI Codex in a persistent Neovim floating terminal.
  Send the current file, selected code, diagnostics, or a file explorer target without leaving your editor.
</p>

<p align="center">
  Closing the popup hides it; it does not kill the Codex session.
</p>

<h2 align="center">Manual Install</h2>

1. Install the Codex CLI and sign in:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex login
```

Confirm the CLI is available:

```bash
codex --version
```

2. Add codux.nvim with lazy.nvim or LazyVim.

Create a plugin spec such as `lua/plugins/codux.lua`:

```lua
return {
  "BRONZowl/codux.nvim",
  config = function()
    require("codux").setup()
  end,
}
```

3. Open Neovim and install the plugin:

```bash
nvim
```

```vim
:Lazy sync
```

Restart Neovim after lazy.nvim finishes installing the plugin.

4. Open a project and verify the setup:

```bash
cd ~/Projects/your-project
nvim
```

```vim
:checkhealth codux
:CoduxOpen
```

In LazyVim, `<leader>` is usually Space.

<h3 align="center">
  <strong>Or just have Codex do it.</strong>
</h3>

<h2 align="center">Requirements</h2>

- Neovim with terminal and floating window support
- OpenAI Codex CLI available as `codex`
- lazy.nvim or LazyVim

Optional:

- which-key.nvim for the `<leader>z` group label
- Neo-tree, Oil.nvim, nvim-tree, or mini.files for file explorer targets

This plugin was developed using Neo-tree in LazyVim.

Windows users can install Codex with PowerShell:

```powershell
irm https://chatgpt.com/codex/install.ps1 | iex
```

For remote or headless login:

```bash
codex login --device-auth
```

<h2 align="center">Usage</h2>

<table align="center">
<tr>
<th>Action</th>
<th>Key</th>
<th>Command</th>
</tr>
<tr>
<td>Open or focus Codex</td>
<td><code>&lt;leader&gt;zc</code></td>
<td><code>:CoduxOpen</code></td>
</tr>
<tr>
<td>Send current file or explorer node</td>
<td><code>&lt;leader&gt;zf</code></td>
<td><code>:CoduxReview</code></td>
</tr>
<tr>
<td>Send selected code</td>
<td><code>&lt;leader&gt;zs</code></td>
<td><code>:CoduxReviewSelection</code></td>
</tr>
<tr>
<td>Send diagnostics and health output</td>
<td><code>&lt;leader&gt;zd</code></td>
<td><code>:CoduxDiagnostics</code></td>
</tr>
<tr>
<td>Hide the popup</td>
<td><code>q</code> or <code>&lt;C-q&gt;</code></td>
<td><code>:CoduxClose</code></td>
</tr>
<tr>
<td>Stop Codex</td>
<td></td>
<td><code>:CoduxExit</code></td>
</tr>
</table>
