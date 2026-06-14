<h1 align="center">codux.nvim</h1>

<p align="center">
  Codux runs OpenAI Codex in a persistent Neovim floating terminal.
  Send the current file, selected code, diagnostics, or a file explorer target without leaving your editor.
</p>

<p align="center">
  Closing the popup hides it; it does not kill the Codex session.
</p>

<h2 align="center">Install</h2>

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

<h2 align="center">Requirements</h2>

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
