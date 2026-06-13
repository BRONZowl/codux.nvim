# codux.nvim

A tiny tmux-first Codex workflow for Neovim/LazyVim.

It opens OpenAI Codex in a dedicated tmux window named `CODEX`, then lets Neovim send the current file, a fix request, or a visual selection into that running Codex session.

It also understands LazyVim's Neo-tree: when your cursor is in Neo-tree, the review and fix mappings use the highlighted file or directory instead of the Neo-tree buffer itself.

## Requirements

- tmux
- Neovim
- OpenAI Codex CLI available as `codex`
- `~/.local/bin` in your shell `PATH`

## Install

Clone this repo:

```bash
git clone https://github.com/BRONZowl/codux.nvim.git
cd codux.nvim
```

Install the launcher:

```bash
mkdir -p ~/.local/bin
cp bin/codux ~/.local/bin/codux
chmod +x ~/.local/bin/codux
```

Make sure `~/.local/bin` is in your PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

For zsh:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## LazyVim setup

Create:

```bash
nvim ~/.config/nvim/lua/plugins/codux.lua
```

Add:

```lua
return {
  dir = "~/path/to/codux.nvim",
  config = function()
    require("codux").setup({
      tmux_window = "CODEX",
    })
  end,
}
```

For a GitHub-hosted plugin, replace `dir` with your repo:

```lua
return {
  "BRONZowl/codux.nvim",
  config = function()
    require("codux").setup()
  end,
}
```

The default mappings match the local LazyVim setup this plugin was extracted from. You can override them if needed:

```lua
return {
  "BRONZowl/codux.nvim",
  config = function()
    require("codux").setup({
      tmux_window = "CODEX",
      mappings = {
        open = "<leader>zc",
        review_file = "<leader>zf",
        fix_file = "<leader>zx",
        review_selection = "<leader>zs",
      },
    })
  end,
}
```

## Usage

Start tmux, enter your project, then open Neovim:

```bash
tmux
cd ~/Projects/FPS
nvim
```

Keybindings:

| Key | Action |
| --- | --- |
| `<leader>zc` | Open/switch to the Codex tmux window |
| `<leader>zf` | Send current file or selected Neo-tree node for review |
| `<leader>zx` | Ask Codex to fix the current file or selected Neo-tree node |
| `<leader>zs` | Send selected code to Codex |

In LazyVim, `<leader>` is usually Space.

## Neo-tree

With the Neo-tree LazyVim extra enabled, focus a file or directory in the tree and use `<leader>zf` or `<leader>zx`. Codux sends that selected path to the running Codex tmux window.

If Neo-tree is not installed or the current window is not Neo-tree, Codux falls back to the active buffer path.

## Codex permissions

By default, the launcher starts Codex with:

```bash
codex -s workspace-write -a on-request
```

That lets Codex work inside the current project workspace and ask before higher-risk actions.

You can override the command:

```bash
export CODEX_CMD="codex"
```

Or rename the tmux window:

```bash
export CODUX_WINDOW_NAME="AI"
```

## Notes

Keep the `CODEX` tmux window open. Neovim sends commands into that running session with `tmux send-keys`.
