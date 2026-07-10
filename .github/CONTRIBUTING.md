# Contributing

Thanks for your interest in contributing to codux.nvim.

codux.nvim is a Neovim plugin for running Codex CLI or Grok CLI inside a
persistent floating terminal, with optional tmux workspaces and Mission Control.
Contributions that improve reliability, documentation, setup clarity, and
day-to-day editor workflow are welcome.

## Reporting Issues

Before opening an issue, please check whether a similar issue already exists.

For bug reports, include:

- Operating system
- Neovim version (`nvim --version`)
- codux.nvim version or commit
- Plugin manager
- Codex CLI and/or Grok CLI version, if relevant
- Minimal config needed to reproduce the issue
- Steps to reproduce
- Expected behavior
- Actual behavior
- Screenshots, GIFs, logs, or terminal output if helpful

## Feature Requests

Feature requests are welcome. Please include:

- The problem you are trying to solve
- The workflow you want codux.nvim to support
- Any alternatives or workarounds you have tried
- Screenshots, mockups, or examples if useful

## Pull Requests

Pull requests should be focused and easy to review.

Please:

- Keep each pull request scoped to one clear change
- Update documentation when behavior changes
- Avoid unrelated formatting changes
- Include screenshots or GIFs for user-facing UI changes
- Run `make test` before submitting

## Development Setup

Clone the repository:

```sh
git clone https://github.com/BRONZowl/codux.nvim.git
cd codux.nvim
```

Use your preferred Neovim plugin manager to load the local checkout while developing.

Example with lazy.nvim:

```lua
{
  dir = "~/path/to/codux.nvim",
  name = "codux.nvim",
  config = function()
    require("codux").setup()
  end,
}
```

## Testing Changes

Run the full suite:

```sh
make test
```

That target runs pure-Lua specs under Lua 5.1, the same specs under headless
Neovim, LuaJIT syntax checks, a setup smoke test, and `:checkhealth codux`.

If you add a new `tests/*_spec.lua` file, also add it to `TEST_SPECS` in the
`Makefile`.

At minimum, also verify that:

- Neovim starts without errors
- codux.nvim loads successfully
- The main Codux command opens the expected terminal window
- Existing documented commands still behave correctly

For UI or workflow changes, include a short explanation of how you tested the behavior.

## Documentation

Documentation updates are valuable. Small improvements to installation steps, command examples, troubleshooting notes, or README clarity are encouraged.
