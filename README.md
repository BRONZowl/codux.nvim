# codux.nvim

A tiny tmux-first Codex workflow for Neovim/LazyVim.

It opens OpenAI Codex in a dedicated tmux window named `CODEX`, then lets Neovim send the current file, a fix request, or a visual selection into that running Codex session.

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
| `<leader>cc` | Open/switch to the Codex tmux window |
| `<leader>cf` | Send current file path for review |
| `<leader>cx` | Ask Codex to fix the current file |
| `<leader>cs` | Send selected code to Codex |

In LazyVim, `<leader>` is usually Space.

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
