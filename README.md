<h1 align="center">codux.nvim</h1>

<h2 align="center">What is Codux?</h2>

<p align="center">
  Codux is a Neovim plugin that runs OpenAI Codex inside a persistent floating terminal.
</p>

<p align="center">
  Unlike chat-style AI plugins, Codux keeps you connected to a real Codex CLI session.<br>
  Send files, visual selections, diagnostics, Git diffs, and file explorer targets directly from Neovim without leaving your editor.
</p>

<p align="center">
  Close the window at any time; the Codex session keeps running in the background.
</p>

<h2 align="center">Why Codux?</h2>

<p align="center">
  Persistent Codex sessions<br>
  Floating terminal workflow<br>
  Built-in token monitoring<br>
  Native Neovim experience<br>
  No context loss between prompts
</p>

<p align="center">
  <img src="assets/codux-demo.gif?v=20260619-token-usage-2" alt="codux.nvim showing the Codex menu, persistent terminal, and visual selection workflow" width="900">
</p>

<h2 align="center">Why not just use Codex in a terminal?</h2>

<p align="center">
  Using Codex in a separate terminal works, but it means:
</p>

<p align="center">
  Switching between editor and terminal<br>
  Losing focus while reviewing changes<br>
  Managing window layouts manually<br>
  No editor-native visibility into token usage
</p>

<p align="center">
  codux.nvim keeps your Codex workflow inside Neovim with:
</p>

<p align="center">
  Persistent sessions<br>
  Floating terminal integration<br>
  Built-in token monitoring<br>
  Fast toggling between code and AI
</p>

## Manual Install

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

## Requirements

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
<td><code>&lt;C-q&gt;</code></td>
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
  The <code>&lt;leader&gt;z</code> menu header shows the current Codux-tracked status and token usage while Codux is running:<br>
  <code>codux execute | 5hr 3% | wk 5%</code><br>
  <code>codux plan | 5hr 3% | wk 5%</code>
</p>

<p align="center">
  Token monitoring refreshes in the background only while Codux is running. The popup can be hidden, but the Codex session must still be active. If usage is unavailable while Codux is running, Codux shows <code>--%</code> placeholders. Status text is green for execute, purple for plan, and red when Codex is not running.
</p>

<p align="center">
  When Codex is actively working and the popup is hidden, Codux shows a small <code>codex is working...</code> indicator near the bottom-right of the editor. The indicator clears when Codex goes idle, is interrupted, or exits.
</p>
