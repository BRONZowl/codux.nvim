# codux.nvim

A small tmux-first Codex workflow for Neovim and LazyVim.

`codux.nvim` keeps Codex in a dedicated tmux window and lets Neovim send work directly into it: review the current file, ask Codex to fix a file, review selected code, or target the highlighted Neo-tree node. After sending, Codux switches you to the Codex tmux window so you can continue the conversation immediately.

## Highlights

- Dedicated Codex tmux window, named `CODEX` by default.
- LazyVim-friendly mappings for file review, file fixes, and visual selections.
- Neo-tree support for sending the highlighted file or directory.
- Automatic fallback to the active buffer when Neo-tree is not focused.
- Simple launcher script with configurable Codex command and tmux window name.

## Requirements

- tmux
- Neovim
- OpenAI Codex CLI available as `codex`
- `~/.local/bin` in your shell `PATH`

## Quick Start

Clone the plugin:

```bash
git clone https://github.com/BRONZowl/codux.nvim.git
cd codux.nvim
```

Install the tmux launcher:

```bash
mkdir -p ~/.local/bin
cp bin/codux ~/.local/bin/codux
chmod +x ~/.local/bin/codux
```

Make sure `~/.local/bin` is in your shell `PATH`.

For bash:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

For zsh:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## LazyVim Setup

Create a plugin spec:

```bash
nvim ~/.config/nvim/lua/plugins/codux.lua
```

For a local checkout:

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

For a GitHub-hosted install:

```lua
return {
  "BRONZowl/codux.nvim",
  config = function()
    require("codux").setup()
  end,
}
```

To override the defaults:

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

## Workflow

Start inside tmux, enter your project, and open Neovim:

```bash
tmux
cd ~/Projects/FPS
nvim
```

Use `<leader>zc` to open or switch to the Codex tmux window. The launcher creates a `CODEX` window in the current directory if it does not already exist; otherwise it selects the existing window.

| Key | Action |
| --- | --- |
| `<leader>zc` | Open or switch to the Codex tmux window |
| `<leader>zf` | Send current file or selected Neo-tree node for review, then switch to Codex |
| `<leader>zx` | Ask Codex to fix the current file or selected Neo-tree node, then switch to Codex |
| `<leader>zs` | Send selected code to Codex, then switch to Codex |

In LazyVim, `<leader>` is usually Space.

## Neo-tree

Codux understands Neo-tree when the Neo-tree window is focused.

With the Neo-tree LazyVim extra enabled, highlight a file or directory and press `<leader>zf` or `<leader>zx`. Codux sends that selected path to the running Codex tmux window instead of sending the Neo-tree buffer path.

If Neo-tree is not installed, or if the current window is not Neo-tree, Codux uses the active buffer path.

## tmux And Codex

The `codux` launcher expects to run inside tmux. By default it starts Codex with:

```bash
codex -s workspace-write -a on-request
```

That gives Codex workspace-write access and keeps higher-risk actions behind approval prompts.

Override the Codex command:

```bash
export CODEX_CMD="codex"
```

Rename the tmux window:

```bash
export CODUX_WINDOW_NAME="AI"
```

If you rename the tmux window, use the same name in your plugin setup:

```lua
require("codux").setup({
  tmux_window = "AI",
})
```

## Notes

- Keep the Codex tmux window open while using Codux.
- Neovim sends prompts with `tmux send-keys`.
- Send mappings switch to the configured Codex tmux window after the prompt is delivered.
