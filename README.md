<p align="center">
  <img src="assets/codux-title.svg" alt="codux.nvim" width="900">
</p>


codux.nvim runs Codex CLI or Grok CLI from Neovim and keeps the session close to
the code you are already editing. It provides a persistent floating terminal,
editor-native prompt helpers, token/status visibility, tmux-backed Codux
workspaces, and Mission Control for coordinated multi-role agent sessions.

Codux is plugin-first. Install it as a Neovim plugin, then use Neovim commands
and mappings to open an agent, send context, manage workspaces, and launch missions.

## Requirements

- Neovim with terminal and floating window support
- OpenAI Codex CLI available as `codex`, or Grok CLI available as `grok`

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

This example uses lazy.nvim and works unchanged in LazyVim:

```lua
{
  "BRONZowl/codux.nvim",
  opts = {},
}
```

With another plugin manager, add codux.nvim to Neovim's `runtimepath` and call
`require("codux").setup({})`.

Install and authenticate the Codex CLI if `codex` is not already available:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex login
codex --version
```

Install and authenticate Grok CLI if you want to use Grok-backed sessions
([official setup](https://docs.x.ai/build/overview)):

```bash
curl -fsSL https://x.ai/cli/install.sh | bash
grok login
grok version
```

Restart Neovim, open a project, then verify Codux:

```vim
:checkhealth codux
:Codux
```

## Quick Start

`:Codux` opens or focuses the persistent agent popup. Closing the popup with
`:CoduxClose` or `<C-q>` hides the window without stopping the agent; `:CoduxExit`
stops the agent process.

Set the global default agent provider with `<leader>zP` or
`:CoduxSetDefaultProvider` (picker keys `g` for Grok, `c` for Codex). That
choice is used by open, workspace create, and mission create, and is saved under
`stdpath("data")/codux/settings.json` so it persists across Neovim restarts.
Startup precedence (highest wins): setup option `default_agent_provider`, then
env `CODUX_AGENT_PROVIDER`, then the saved preference, then `"codex"`.

The default open mapping is `<leader>zc`. When no agent is running, it opens a
permission-profile picker for the global default provider:

- `d` for default
- `a` for auto
- `f` for full access

Those profile choices set only the startup permission profile for the new
session. If the Codux popup is already open, `:Codux` and `<leader>zc` are a
no-op until you hide it with `:CoduxClose` or `<C-q>`. When an agent is still
running but the popup is closed, those commands reopen and focus that session
instead of changing its provider or profile. Mission Control and workspace
dashboard **Switch Profile** menus still use a two-step provider + profile
picker so individual roles or workspaces can differ from the global default.
Use full access only in repositories you trust. `:CoduxOpenDanger` starts Codex
with no approval prompts and no sandbox; `:CoduxOpenGrokDanger` starts Grok with
its full-access command.

Codux can send editor context to the active agent session:

- `:CoduxReview` sends the current file, directory, or supported file explorer
  target.
- `:'<,'>CoduxReviewSelection` sends the visual selection.
- `:CoduxDiagnostics` sends diagnostics, quickfix/location list context, and
  Codux health output.
- `:CoduxDiff` sends the current Git diff.

## Commands

| Action | Default key | Command |
| --- | --- | --- |
| Open or focus agent | `<leader>zc` | `:Codux` or `:CoduxOpen` |
| Set default agent provider | `<leader>zP` | `:CoduxSetDefaultProvider [codex\|grok]` |
| Set preferred Grok TUI theme | none | `:CoduxSetGrokTheme [theme]` |
| Toggle agent popup | none | `:CoduxToggle` |
| Hide the popup | `<C-q>` in popup | `:CoduxClose` |
| Stop agent | none | `:CoduxExit` |
| Open Codex with auto profile | none | `:CoduxOpenAuto` |
| Open Codex with full access | none | `:CoduxOpenDanger` |
| Open a specific provider | none | `:CoduxOpenProvider <codex\|grok> <default\|auto\|danger>` |
| Open Grok | none | `:CoduxOpenGrok` |
| Open Grok with auto profile | none | `:CoduxOpenGrokAuto` |
| Open Grok with full access | none | `:CoduxOpenGrokDanger` |
| Send file, folder, or explorer node | `<leader>zf` | `:CoduxReview` |
| Send visual selection | `<leader>zs` | `:CoduxReviewSelection` |
| Send diagnostics and health output | `<leader>zd` | `:CoduxDiagnostics` |
| Send Git diff | `<leader>zg` | `:CoduxDiff` |
| Toggle agent plan mode | `<leader>zp` in agent terminal | `:CoduxTogglePlan` |
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
| Create a Grok Mission Control crew | none | `:CoduxMissionCreateGrok` |
| Show Mission Control | `<leader>zM` | `:CoduxMissions` or `:CoduxMissionDashboard` |
| Edit a mission objective | none | `:CoduxMissionEdit <mission>` |
| Edit a mission focus packet | none | `:CoduxMissionFocus <mission>` |
| Close a mission | none | `:CoduxMissionClose <mission>` |
| Delete a mission | none | `:CoduxMissionDelete <mission>` |
| Run Neovim health checks | none | `:CoduxHealth` |
| Run Codux Doctor | `h` in workspace / mission dashboard | `:CoduxDoctor` |

By default, Codux maps only the core single-session actions and Mission Control:
open, set default provider, review file, review selection, diagnostics, diff,
and missions. Plan-mode toggle is available as `:CoduxTogglePlan` and as a
buffer-local map inside the agent terminal (`mappings.mode`, default
`<leader>zp`), not as a global leader-z which-key entry. Workspace create/list
mappings are disabled by default, but every workspace command is available
directly.

## Configuration

The key defaults are:

```lua
require("codux").setup({
  default_initial_mode = "plan",
  default_agent_provider = "codex",
  providers = {
    codex = {
      default_cmd = 'codex -s workspace-write -a on-request -c approvals_reviewer="user"',
      auto_cmd = 'codex -s workspace-write -a on-request -c approvals_reviewer="auto_review"',
      danger_cmd = "codex -s danger-full-access -a never",
    },
    grok = {
      default_cmd = "grok --sandbox workspace",
      auto_cmd = "grok --sandbox workspace --always-approve",
      danger_cmd = "grok --sandbox off --always-approve",
      -- theme = "tokyonight", -- or :CoduxSetGrokTheme / CODUX_GROK_THEME
    },
  },
  token_monitor = {
    enabled = true,
    refresh_ms = 60000,
    timeout_ms = 5000,
    -- Optional dedicated CLI for Codex usage checks (defaults to providers.codex executable):
    -- codex_cmd = "codex",
    grok = {
      enabled = true,
      refresh_ms = 15000, -- faster poll; RPM headroom recovers within seconds
      base_url = "https://api.x.ai/v1",
      model = "grok-4.5",
      -- api_key = nil, -- or set XAI_API_KEY / GROK_API_KEY
      -- auth_file = nil, -- default ~/.grok/auth.json (Grok CLI OAuth)
    },
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

The nested `providers.codex` fields are preferred. For backward compatibility,
the top-level `codex_cmd`, `workspace_auto_cmd`, and
`danger_full_access_cmd` options remain supported. When both forms configure
the same profile, the nested provider field takes precedence.

Provider commands can be overridden through setup options or environment
variables:

- `CODEX_CMD` for the default profile
- `CODEX_WORKSPACE_AUTO_CMD` for the auto profile
- `CODEX_DANGER_FULL_ACCESS_CMD` for the full-access profile
- `GROK_CMD` for the default Grok profile
- `GROK_WORKSPACE_AUTO_CMD` for the Grok auto profile
- `GROK_DANGER_FULL_ACCESS_CMD` for the Grok full-access profile

`default_agent_provider` is the startup seed for open, workspace create, and
mission create. Resolution order: setup option → `CODUX_AGENT_PROVIDER` → last
value from `<leader>zP` / `:CoduxSetDefaultProvider` (persisted) → `"codex"`.

Preferred Grok TUI theme is set with `:CoduxSetGrokTheme` (or setup
`providers.grok.theme` / env `CODUX_GROK_THEME`). Codux saves it under
`stdpath("data")/codux/settings.json` and syncs `[ui].theme` in
`~/.grok/config.toml` so new Grok processes start with that theme. Resolution
order: setup `providers.grok.theme` → `CODUX_GROK_THEME` → saved preference →
existing `~/.grok/config.toml`. Themes: `auto`, `groknight`, `grokday`,
`tokyonight`, `rosepine-moon`, `oscura-midnight` (aliases like `dark` / `tokyo`
also work).

New Codux-managed agent sessions start in plan mode. Set
`default_initial_mode = "execute"` to keep older execute-mode startup behavior.

## Workspaces

Codux workspaces are tmux-backed Neovim windows with their own Codex or Grok
session, instruction file, Git worktree, target path, provider/profile, and
saved state.
They are intended for dedicated streams of work such as implementation, review,
debugging, or architecture.

Run `:CoduxWorkspaceCreate` inside tmux to create a guided workspace. Add
`--grok` or `--codex` to force a provider for that workspace. Codux:

- prompts for a workspace name
- uses the global default provider unless the provider was forced
- prompts for default, auto, or full permission profile
- opens a Vim-like instruction editor
- previews the instruction before launch
- requires the current checkout to be clean
- creates `../codux-worktrees/<workspace>` from the current ref
- creates a `dev/<workspace>` branch, or the next available namespace such as
  `dev1/<workspace>` when needed
- writes `.agents/codux/<workspace>.md` in the workspace
- opens a tmux window named for the workspace
- starts the workspace agent session in plan mode

For Grok workspaces, Codux keeps first-launch CLI arguments minimal: it starts
the configured Grok profile command, adds `--rules` only when workspace or
mission instructions exist, and pastes any initial prompt after the Grok TUI is
ready instead of passing it as an argv argument.

Workspace state is stored per project in
`stdpath("data")/codux/workspaces.json`. Instruction files are project-local; if
a non-empty `.agents/codux/<workspace>.md` exists, Codux uses it over the saved
JSON copy.

Use `:CoduxWorkspaces` to open the workspace dashboard. It includes fuzzy search,
`<Tab>` search/list switching, `j`/`k` movement, `<CR>` open, `h` Doctor, and
`m` for the selected-workspace menu. The menu supports start workspace, rename,
edit instructions, switch provider/profile, close workspace, close all
workspaces, and delete workspace. Switching the profile of an active workspace restarts that
workspace with the selected Codex or Grok command; switching an inactive
workspace updates its saved startup provider/profile for the next launch.

Deleting a workspace removes saved state and the matching instruction file,
closes the tmux window, removes the worktree, and deletes the workspace branch.
When `.agents/codux/` is not ignored by Git, Codux warns; run
`:CoduxWorkspaceIgnore` once per project to add the ignore rule.

Outside tmux, workspace creation stops with `no tmux session running`.

## Mission Control

Mission Control launches one or more Codux agent workspaces around a shared
objective. Run `:CoduxMissionCreate`, enter the mission name, choose Codex or
Grok, choose default, auto, or full profile, enter the objective, review the
preview, and launch.

Every new mission always creates a **Manager** role, plus a default worker:

- **Manager**: owns the objective and focus packet, plans work, and coordinates
  worker roles. Selecting the **mission row** in Mission Control previews and
  controls this Manager session (same Output panel and `<C-o>` as a role row).
- **Agent**: creates the requested outcome accurately, keeps context focused,
  validates cheaply, and asks only high-impact questions.

Add more workers anytime from the mission dashboard (create role workspace).
Custom role lists still get a Manager injected when one is missing.

The Manager can request sibling start/prompt/create by writing JSON dispatch
files under `.agents/codux/missions/<mission>/dispatch/pending/`. Codux
processes pending files while Mission Control is open (dashboard monitor) or
when you run `:CoduxMissionProcessDispatch`. Successful files move to `done/`;
failures go to `failed/`. Supported ops: `start`, `prompt`, `start_and_prompt`,
`create_role`, `update_focus`.

Each role gets a clean Git worktree workspace under the project-scoped
`../codux-worktrees/<project>/<workspace>` directory, mission metadata in Codux
workspace state, the chosen permission profile and agent provider, and an initial
plan-mode prompt. If Codux cannot confirm plan mode for a newly created mission
agent, it rolls back the new agent workspace.

Each mission also carries a short focus packet. The packet is separate from each
role's stable workspace instruction and captures the current intent, direction,
preferences, active scope, and next action. Mission startup and role prompts
include the current packet so iteration stays narrow without turning the
workspace instruction into a transcript.

`:CoduxMissions`, `:CoduxMissionDashboard`, and `<leader>zM` open the mission
dashboard. It shows mission and role rows with status, mode, profile, age, and
target, plus a live `Output:` panel. Highlight a **mission** row to drive the
**Manager** console; highlight a **role** row to preview that worker's session.
When an active preview is shown, the dashboard gives more space to the output
panel while keeping the selected row visible. The preview uses the role's Codux
terminal controls, so output control behaves like the default `<leader>zc` Codux
window while staying inside the dashboard layout. Profile labels include the
provider, and switching the profile of a highlighted active role refreshes the
output preview after the restarted session is ready.

Dashboard controls:

- Type in `Search Codux missions:` to fuzzy-filter mission, role, or workspace names.
- `<Tab>` switches between search and the dashboard list.
- `<CR>` focuses the highlighted mission or role from search.
- `j`/`k` moves through selectable mission and role rows.
- `m` opens the mission menu for mission rows or the workspace menu for role
  rows.
- `n` creates a mission.
- `c` cleans empty Mission Control residue.
- `h` runs Codux Doctor (same as `:CoduxDoctor`).
- `<C-o>` enters output control for the highlighted active role workspace.

While controlling role output, type directly into the agent session. `<C-o>`
returns to the mission dashboard and `<C-q>` closes Mission Control. `Esc`
continues to belong to the agent inside the output session.

Mission menu actions include start/reopen mission, **Start Manager**, **Process
Dispatch** (pending Manager handoff files), view/edit objective, edit focus,
**Add Manager** (legacy missions), close mission, delete mission, and create a
mission. Role workspace menus include start workspace, **Prompt Role**, switch
provider/profile, rename role, edit instructions, close workspace, delete
workspace, and create workspace. Recent dispatch results appear as a
`dispatch | N ok | M failed` status line on the dashboard when handoffs run.

Close and delete are separate operations. Closing a mission only closes role
windows and preserves worktrees, branches, instructions, saved state, and mission
metadata. Deleting a mission is destructive cleanup and asks for confirmation;
it removes each role workspace, closes matching tmux windows, removes role
worktrees and branches, deletes instruction files, and cleans empty mission
residue.

## Token and Status Monitoring

The `<leader>z` which-key header shows Codux status and token usage, for example:

```text
codux | 5hr 3% | wk 5%
codux | quota | tpm full 53.0M | rpm full 8300
codux | quota | tpm used 1.2k/53.0M | rpm used 5/8300
```

Token monitoring refreshes in the background while a session is running.
Codex uses `refresh_ms` (default 60s). Grok uses `token_monitor.grok.refresh_ms`
(default 15s) because request rate-limit headroom can recover within seconds.
Mission Control also refreshes usage without an active main-session terminal.
The usage line follows the **selected mission role’s agent provider** (Codex vs
Grok). Metrics are cached per provider so switching selection updates the label
format immediately and each provider is throttled independently.

**Codex** usage is unchanged: each check starts a short-lived `codex app-server`
process and reads account rate limits (`timeout_ms`, default 5s), shown as
`5hr` / `wk` percent used.

**Grok** usage uses a cheap `max_tokens=1` probe against the xAI API and reads
`x-ratelimit-*` headers. That is **rate-limit headroom for the current window**,
not total tokens billed for your chat. xAI tier TPM ceilings are very large
(often tens of millions), so light use often still reports full remaining and
integer **0% used**. Labels therefore show `full <limit>` when nothing is
consumed in the window, `used <n>/<limit>` for small dips that would still
round to the same millions string, and percent + remaining only when used % is
above zero. Auth is resolved from `token_monitor.grok.api_key`, then
`XAI_API_KEY` / `GROK_API_KEY`, then `~/.grok/auth.json` (same OAuth key as
`grok login`). The probe incurs a small API cost per refresh; disable with
`token_monitor.grok = false` without affecting Codex monitoring.

If usage is unavailable (CLI missing, timeout, API error, no credentials),
Codux shows `--%` placeholders; Mission Control may append `(unavailable)`.
Inspect `require("codux").health_info().token_usage.last_error` for the last
failure detail. When an agent is actively working and the popup is hidden,
Codux shows a small `agent is working...` indicator near the bottom-right of the
editor.

## Troubleshooting

Use `:checkhealth codux` or `:CoduxHealth` for Neovim health checks.

Use `:CoduxDoctor` for Codux-specific runtime checks. Doctor reports tmux
availability, Codex/Grok availability, workspace state readability/writability,
project-root detection, `.agents/codux/` ignore status, loaded workspaces, and
workspace window state.

Common checks:

- `codex --version` confirms the Codex CLI is available.
- `grok version` confirms the Grok CLI is available.
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
