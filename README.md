<h1 align="center">codux.nvim</h1>

<p align="center">
  Codux runs OpenAI Codex in a persistent Neovim floating terminal.
  Send the current file, selected code, diagnostics, or a file explorer target without leaving your editor.
</p>

Closing the popup hides it; it does not kill the Codex session.

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

| Action | Key | Command |
| --- | --- | --- |
| Open or focus Codex | `<leader>zc` | `:CoduxOpen` |
| Send current file or explorer node | `<leader>zf` | `:CoduxReview` |
| Send selected code | `<leader>zs` | `:CoduxReviewSelection` |
| Send diagnostics and health output | `<leader>zd` | `:CoduxDiagnostics` |
| Hide the popup | `q` or `<C-q>` | `:CoduxClose` |
| Stop Codex | | `:CoduxExit` |
