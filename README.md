<p align="center">
  <img src="assets/codux-title.svg" alt="codux.nvim" width="900">
</p>


codux.nvim runs the OpenAI Codex CLI from Neovim and keeps the session close to
the code you are already editing. It provides a persistent floating terminal,
editor-native prompt helpers, token/status visibility, tmux-backed Codux
workspaces, and Mission Control for coordinated multi-role Codex sessions.

Codux is plugin-first. Install it as a Neovim plugin, then use Neovim commands
and mappings to open Codex, send context, manage workspaces, and launch missions.

## Requirements

- Neovim with terminal and floating window support
- OpenAI Codex CLI available as `codex`
- lazy.nvim or LazyVim

Optional:

- which-key.nvim for the `<leader>z` group label and live Codux status header
- tmux for Codux workspaces and Mission Control
- Neo-tree, Oil.nvim, nvim-tree, or mini.files for file explorer targets

Windows users can use WSL2 with the Linux Codex CLI install flow. For remote or
headless login, run:

```bash
codex login --device-auth
```

## Install

Add codux.nvim with lazy.nvim or LazyVim:

```lua
{
  "BRONZowl/codux.nvim",
  opts = {},
}
```

Install and authenticate the Codex CLI if `codex` is not already available:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex login
codex --version
```

Restart Neovim, open a project, then verify Codux:

```vim
:checkhealth codux
:Codux
```

## Quick Start

`:Codux` opens or focuses the persistent Codex popup. Closing the popup with
`:CoduxClose` or `<C-q>` hides the window without stopping Codex; `:CoduxExit`
stops the Codex process.

The default open mapping is `<leader>zc`. When Codex is not running, it opens a
small profile picker:

- `d` starts the default Codex command.
- `a` starts the workspace-auto command.
- `f` starts the danger/full-access command.

Use full access only in repositories you trust. `:CoduxOpenDanger` starts Codex
with no approval prompts and no sandbox.

Codux can send editor context to the active Codex session:

- `:CoduxReview` sends the current file, directory, or supported file explorer
  target.
- `:'<,'>CoduxReviewSelection` sends the visual selection.
- `:CoduxDiagnostics` sends diagnostics, quickfix/location list context, and
  Codux health output.
- `:CoduxDiff` sends the current Git diff.

## Commands

| Action | Default key | Command |
| --- | --- | --- |
| Open or focus Codex | `<leader>zc` | `:Codux` or `:CoduxOpen` |
| Toggle Codex popup | none | `:CoduxToggle` |
| Hide the popup | `<C-q>` in popup | `:CoduxClose` |
| Stop Codex | none | `:CoduxExit` |
| Open Codex with auto profile | picker key `a` | `:CoduxOpenAuto` |
| Open Codex with full access | picker key `f` | `:CoduxOpenDanger` |
| Send file, folder, or explorer node | `<leader>zf` | `:CoduxReview` |
| Send visual selection | `<leader>zs` | `:CoduxReviewSelection` |
| Send diagnostics and health output | `<leader>zd` | `:CoduxDiagnostics` |
| Send Git diff | `<leader>zg` | `:CoduxDiff` |
| Toggle Codex plan mode | `<leader>zp` | `:CoduxTogglePlan` |
| Create a tmux workspace | none | `:CoduxWorkspace` or `:CoduxWorkspaceCreate` |
| Show current workspaces | none | `:CoduxWorkspaces` |
| Open a saved workspace | none | `:CoduxWorkspaceOpen <name>` |
| Select a saved workspace | none | `:CoduxWorkspaceSelect <name>` |
| Rename a workspace | none | `:CoduxWorkspaceRename <old> <new>` |
| Delete a workspace | none | `:CoduxWorkspaceDelete <name>` |
| Restore workspace state from tmux | none | `:CoduxWorkspaceRestore` |
| Close all workspace windows | none | `:CoduxWorkspaceCloseAll` |
| Ignore local workspace files | none | `:CoduxWorkspaceIgnore` |
| Create a Mission Control crew | none | `:CoduxMissionCreate` |
| Show Mission Control | `<leader>zM` | `:CoduxMissions` or `:CoduxMissionDashboard` |
| Edit a mission objective | none | `:CoduxMissionEdit <mission>` |
| Edit a mission focus packet | none | `:CoduxMissionFocus <mission>` |
| Close a mission | none | `:CoduxMissionClose <mission>` |
| Delete a mission | none | `:CoduxMissionDelete <mission>` |
| Run Neovim health checks | none | `:CoduxHealth` |
| Run Codux Doctor | `h` in workspace dashboard | `:CoduxDoctor` |

By default, Codux maps only the core single-session actions and Mission Control:
open, review file, review selection, diagnostics, diff, plan-mode toggle, and
missions. Workspace create/list mappings are disabled by default, but every
workspace command is available directly.

## Configuration

The default setup is:

```lua
require("codux").setup({
  default_initial_mode = "plan",
  token_monitor = {
    enabled = true,
  },
  workspaces = {
    enabled = true,
    tmux_cmd = "tmux",
    worktree = {
      directory = "../codux-worktrees",
      branch_prefix = "dev/",
    },
    instruction_files = {
      enabled = true,
      directory = ".agents/codux",
    },
  },
})
```

The Codex commands can be overridden through setup options or environment
variables:

- `CODEX_CMD` for the default profile
- `CODEX_WORKSPACE_AUTO_CMD` for the auto profile
- `CODEX_DANGER_FULL_ACCESS_CMD` for the full-access profile

New Codux-managed Codex sessions start in plan mode. Set
`default_initial_mode = "execute"` to keep older execute-mode startup behavior.

## Workspaces

Codux workspaces are tmux-backed Neovim windows with their own Codex session,
instruction file, Git worktree, target path, permission profile, and saved state.
They are intended for dedicated streams of work such as implementation, review,
debugging, or architecture.

Run `:CoduxWorkspaceCreate` inside tmux to create a guided workspace. Codux:

- prompts for a workspace name
- opens a Vim-like instruction editor
- previews the instruction before launch
- requires the current checkout to be clean
- creates `../codux-worktrees/<workspace>` from the current ref
- creates a `dev/<workspace>` branch, or the next available namespace such as
  `dev1/<workspace>` when needed
- writes `.agents/codux/<workspace>.md` in the workspace
- opens a tmux window named for the workspace
- starts the workspace Codex session in plan mode

Workspace state is stored per project in
`stdpath("data")/codux/workspaces.json`. Instruction files are project-local; if
a non-empty `.agents/codux/<workspace>.md` exists, Codux uses it over the saved
JSON copy.

Use `:CoduxWorkspaces` to open the workspace dashboard. It includes fuzzy search,
`<Tab>` search/list switching, `j`/`k` movement, `<CR>` open, `h` Doctor, and
`m` for the selected-workspace menu. The menu supports rename, edit
instructions, close workspace, close all workspaces, and delete workspace.

Deleting a workspace removes saved state and the matching instruction file,
closes the tmux window, removes the worktree, and deletes the workspace branch.
When `.agents/codux/` is not ignored by Git, Codux warns; run
`:CoduxWorkspaceIgnore` once per project to add the ignore rule.

Outside tmux, workspace creation stops with `no tmux session running`.

## Mission Control

Mission Control launches a small crew of Codux workspaces for one objective. Run
`:CoduxMissionCreate`, enter the objective, review the preview, and launch.

The default crew is:

- Agent: creates the requested outcome accurately, keeps context focused,
  validates cheaply, and asks only high-impact questions.

Each role gets a clean Git worktree workspace under the project-scoped
`../codux-worktrees/<project>/<workspace>` directory, mission metadata in Codux
workspace state, workspace-auto permissions, and an initial plan-mode prompt. If
Codux cannot confirm plan mode for a newly created mission role, it rolls back
the new role workspaces.

Each mission also carries a short focus packet. The packet is separate from each
role's stable workspace instruction and captures the current intent, direction,
preferences, active scope, and next action. Mission startup and role prompts
include the current packet so iteration stays narrow without turning the
workspace instruction into a transcript.

`:CoduxMissions`, `:CoduxMissionDashboard`, and `<leader>zM` open the mission
dashboard. It shows mission and role rows with status, mode, profile, age, and
target, plus a live `Output:` panel for the highlighted role. Mission rows do
not control output directly; active role rows preview that role workspace's
Codex session. When an active role preview is shown, the dashboard gives more
space to the output panel while keeping the selected row visible. The preview
uses the role's Codux terminal controls, so output control behaves like the
default `<leader>zc` Codux window while staying inside the dashboard layout.

Dashboard controls:

- Type in `Search Codux missions:` to fuzzy-filter mission, role, or workspace names.
- `<Tab>` switches between search and the dashboard list.
- `<CR>` focuses the highlighted mission or role from search.
- `j`/`k` moves through selectable mission and role rows.
- `m` opens the mission menu for mission rows or the workspace menu for role
  rows.
- `n` creates a mission.
- `c` cleans empty Mission Control residue.
- `<C-o>` enters output control for the highlighted active role workspace.

While controlling role output, type directly into the Codex session. `<C-o>`
returns to the mission dashboard and `<C-q>` closes Mission Control. `Esc`
continues to belong to Codex inside the output session.

Mission menu actions include start/reopen mission, view objective, edit
objective, edit focus, close mission, delete mission, and create a mission. Role
workspace menus include prompt or answer when available, interrupt, switch mode,
rename role, edit instructions, close workspace, delete workspace, and create
workspace.

Close and delete are separate operations. Closing a mission only closes role
windows and preserves worktrees, branches, instructions, saved state, and mission
metadata. Deleting a mission is destructive cleanup and asks for confirmation;
it removes each role workspace, closes matching tmux windows, removes role
worktrees and branches, deletes instruction files, and cleans empty mission
residue.

## Token and Status Monitoring

When Codux is running, the `<leader>z` which-key header shows the current Codux
mode and token usage, for example:

```text
codux exec | 5hr 3% | wk 5%
codux plan | 5hr 3% | wk 5%
```

Token monitoring refreshes in the background only while Codux is running. If
usage is unavailable, Codux shows `--%` placeholders. When Codex is actively
working and the popup is hidden, Codux shows a small `codex is working...`
indicator near the bottom-right of the editor.

## Troubleshooting

Use `:checkhealth codux` or `:CoduxHealth` for Neovim health checks.

Use `:CoduxDoctor` for Codux-specific runtime checks. Doctor reports tmux
availability, Codex availability, workspace state readability/writability,
project-root detection, `.agents/codux/` ignore status, loaded workspaces, and
workspace window state.

Common checks:

- `codex --version` confirms the Codex CLI is available.
- `:checkhealth codux` confirms Neovim can load the plugin.
- `:CoduxDoctor` confirms tmux/workspace state for Codux workspaces.
- `:CoduxWorkspaceRestore` reconciles saved workspace state with tmux after
  restarts.
- Mission dashboards and output previews reconcile moved mission worktrees before
  using saved paths.

## Development

Run the test suite with:

```bash
make test
```

The suite runs plain Lua specs, headless Neovim specs with
`--headless -u NONE -i NONE --cmd 'set shadafile=NONE'`, LuaJIT syntax loading,
plugin setup, and `checkhealth codux`.
