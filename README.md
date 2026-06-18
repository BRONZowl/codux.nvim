<h1 align="center">codux.nvim</h1>

<p align="center">
  Codux runs OpenAI Codex in a persistent Neovim floating terminal.<br>
  Send the current file, selected code, diagnostics, Git diffs, or a file explorer target without leaving your editor.
</p>

<p align="center">
  Closing the popup hides it; it does not kill the Codex session.
</p>

<p align="center">
  If Codux fits your workflow, a GitHub star helps other Neovim users find it.
</p>

<p align="center">
  <img src="assets/codux-demo.gif?v=20260618" alt="codux.nvim opening Codex and sending a Git diff from Neovim" width="900">
</p>

<h2 align="center">Manual Install</h2>

1. Add codux.nvim with lazy.nvim or LazyVim:

```lua
{
  "BRONZowl/codux.nvim",
  opts = {},
}
```

2. Run `:Lazy sync`, restart Neovim, then open Codux:

```vim
:Codux
```

In LazyVim, `<leader>` is usually Space. Codux also maps open to `<leader>zc`.

3. Install the Codex CLI and sign in if `codex` is not already available:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex login
```

Confirm the CLI is available:

```bash
codex --version
```

4. Open a project and verify the setup:

```bash
cd ~/Projects/your-project
nvim
```

```vim
:checkhealth codux
:Codux
```

<h3 align="center">
  <strong>Or just have Codex do it.</strong>
</h3>

<p align="center">
  Ask Codex: <code>Install BRONZowl/codux.nvim in my LazyVim config.</code>
</p>

<h2 align="center">Requirements</h2>

- Neovim with terminal and floating window support
- OpenAI Codex CLI available as `codex`
- lazy.nvim or LazyVim

Optional:

- which-key.nvim for the `<leader>z` group label
- Neo-tree, Oil.nvim, nvim-tree, or mini.files for file explorer targets

This plugin was developed using Neo-tree in LazyVim.

Windows users can use WSL2 with the Linux install command above, or follow the official Codex Windows setup guide.

For remote or headless login:

```bash
codex login --device-auth
```

Codux sends requested files, selections, diagnostics, and health output through your configured Codex CLI session.

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
<td><code>:Codux</code></td>
</tr>
<tr>
<td>Open Codex autopilot with approve-for-me permissions</td>
<td><code>&lt;leader&gt;za</code></td>
<td><code>:CoduxOpenAuto</code></td>
</tr>
<tr>
<td>Open Codex danger zone with no sandbox</td>
<td><code>&lt;leader&gt;zA</code></td>
<td><code>:CoduxOpenDanger</code></td>
</tr>
<tr>
<td>Send current file or explorer node</td>
<td><code>&lt;leader&gt;zf</code></td>
<td><code>:CoduxReview</code></td>
</tr>
<tr>
<td>Send selected code</td>
<td><code>&lt;leader&gt;zs</code></td>
<td><code>:&#39;&lt;,&#39;&gt;CoduxReviewSelection</code></td>
</tr>
<tr>
<td>Send diagnostics and health output</td>
<td><code>&lt;leader&gt;zd</code></td>
<td><code>:CoduxDiagnostics</code></td>
</tr>
<tr>
<td>Send Git changes</td>
<td><code>&lt;leader&gt;zg</code></td>
<td><code>:CoduxDiff</code></td>
</tr>
<tr>
<td>Toggle Codex plan mode</td>
<td><code>&lt;leader&gt;zp</code></td>
<td><code>:CoduxTogglePlan</code></td>
</tr>
<tr>
<td>Hide the popup</td>
<td><code>q</code> or <code>&lt;C-q&gt;</code></td>
<td><code>:CoduxClose</code></td>
</tr>
<tr>
<td>Start typing after scrolling</td>
<td>Type normally</td>
<td></td>
</tr>
<tr>
<td>Stop Codex</td>
<td></td>
<td><code>:CoduxExit</code></td>
</tr>
</table>

<p align="center">
  <code>:CoduxOpenDanger</code> starts Codex with no approval prompts and no sandbox. Use it only in repositories you trust.
</p>

<p align="center">
  The <code>&lt;leader&gt;z</code> group label shows the current Codux-tracked status as <code>codux status execute</code>, <code>codux status plan</code>, or <code>codux status not running</code>. Status text is green for execute, purple for plan, and red when Codex is not running.
</p>

<p align="center">
  When Codex is actively working and the popup is hidden, Codux shows a small <code>codex is working...</code> indicator near the bottom-right of the editor. The indicator clears when Codex goes idle, is interrupted, or exits.
</p>
