# Release Notes

## v0.8.0

Mission Control release.

codux.nvim v0.8.0 promotes Mission Control into the main Codux workflow and tightens the surrounding workspace, prompt, profile, and dashboard behavior.

- Added Mission Control for creating objective-scoped Codux crews with Git worktree role workspaces, mission metadata, plan-mode startup, workspace-auto permissions, and rollback when role startup cannot be verified.
- Refined the default mission crew to Builder and Reviewer roles, with role prompts that start in plan mode and ask for repo grounding, next steps, blockers, and handoff notes.
- Added the mission dashboard with fuzzy mission/role search, search/list tab switching, selectable mission and role rows, contextual mission/workspace menus, live role output preview, token usage, prompt sending, question answering, role interrupt, mission close, and destructive mission delete.
- Added a keyed Codex open profile picker for default, auto, and full-access starts, and routed prompt actions through the picker when Codex is not already running.
- Extracted shared dashboard search, action palette, mission output panel, and test helpers to support the expanded UI surface.
- Hardened workspace lifecycle behavior around plan-mode gating, created-workspace mission attachment, workspace delete confirmations, inactive workspace state, hidden focus sinks, prompt focus restoration, and Mission Control dashboard refresh paths.
- Refreshed `README.md` to document the current plugin-first command surface, workspaces, Mission Control, token/status monitoring, Doctor, and test workflow while removing GIF embeds.
- Expanded automated coverage for Mission Control, mission output preview, action palettes, profile opening, prompt actions, terminal mode handling, workspace runtime, workspace store, workspace UI, dashboard search, and headless Neovim validation.

## v0.7.1

Workspace worktrees and cleanup.

codux.nvim v0.7.1 makes Codux workspaces isolated Git worktrees and hardens workspace cleanup behavior.

- Made new Codux workspaces Git worktrees under `../codux-worktrees/`, created only when the current checkout is clean, using `dev/<workspace>` or the next available namespace such as `dev1/<workspace>`.
- Added merged-workspace cleanup prompts that remove the saved workspace, worktree, instruction file, and branch after confirmation.
- Upgraded Mission Control with a three-role architect/builder/reviewer crew, plan-mode role startup, selected-role live monitoring, dashboard prompt sending, workspace-style fuzzy search, search/list tab switching, `j`/`k` movement, contextual mission/workspace menus, plus `:CoduxMissionEdit`, `:CoduxMissionClose`, and `:CoduxMissionDelete` for objective updates, non-destructive mission closing, and whole-mission cleanup with dirty-worktree warnings.
- Added `j`/`k` movement for the selected dashboard workspace after confirming a fuzzy-search result.
- Warn when project-local workspace instruction files are not ignored by Git, and added `:CoduxWorkspaceIgnore` to add the ignore rule explicitly.
- Hardened workspace target reopening, renamed-workspace tmux target tracking, instruction cleanup, instruction-only workspace deletes, and stale worktree deletion.
- Removed the branch column from the workspace dashboard because worktree-backed workspaces now show profile, session age, and target.

## v0.7.0

Workspace dashboard ergonomics.

codux.nvim v0.7.0 turns the workspace dashboard into the central control surface for persistent Codex workspaces inside Neovim.

- Simplified the workspace dashboard around fuzzy search with one fixed question/active/idle/inactive, recent-activity order.
- Added workspace profile, branch, session age, and target columns to the dashboard.
- Added an `m` dashboard workspace menu for rename workspace, edit instructions, close workspace, close all workspaces, and delete workspace, with `h` running Doctor directly from the dashboard.
- Added `X` and `:CoduxWorkspaceCloseAll` to close all current-project Codux workspaces after confirmation.
- Treat stale saved tmux windows as `inactive` in the dashboard.
- Checked all tmux panes when deciding whether a workspace window is open in Neovim.

## v0.6.5

Workspace dashboard mode tracking and Codex mode switching fixes.

- Added a workspace dashboard mode column showing `exec`, `plan`, or `--` when mode is unknown or inactive.
- Persisted workspace Codex mode while sessions are running and clear it when workspaces become inactive or Codex exits.
- Fixed Codex mode switching so the z-menu, `:CoduxTogglePlan`, and terminal `<S-Tab>` all use the bidirectional Shift-Tab mode switch.
- Removed terminal-output based mode mutation to avoid false positives from prose or code snippets mentioning plan/execute.
- Hardened repeated setup keymap cleanup, workspace name validation, and timed system command handling.
- Refactored Codux internals into focused modules for terminal, workspace, context, health, prompt, token, and UI behavior.

## v0.6.4

Workspace instruction editor polish.

- Workspace instruction input now opens as a Vim-like editor window with line numbers, normal-mode startup, autocomplete disabled, and a mode indicator in the floating border.

## v0.6.3

Workspace conversation resume and file-backed instructions.

- Saved Codux workspaces now persist the Codex session id after launch.
- Reopening a saved workspace resumes that exact Codex conversation when the local transcript is available.
- Older saved workspaces seed their session id from the most recent local Codex session for the same project root.
- Workspace instructions are now passed to Codex as session guidance instead of an auto-submitted first prompt.
- Workspace instructions are mirrored to `.agents/codux/<workspace>.md`; non-empty files override the saved JSON copy and can recover missing workspace entries.
- Deleting a workspace removes its saved state and matching `.agents/codux/<workspace>.md` instruction file.
- Removed workspace template commands and `--template`; workspace creation now always uses workspace-local instructions.
- Codux keeps workspace instructions out of `AGENTS.md`.

## v0.6.2

Workspace dashboard search.

- Added a search field above the workspace dashboard.
- Fuzzy search filters saved workspaces and previews the closest match in the dashboard.
- Pressing `<CR>` in search focuses the highlighted dashboard result so dashboard actions can be run.
- Added `tab search/list` to switch between the dashboard search field and workspace list, and kept `<C-q>` closing the dashboard/search UI.
- Documented the workspace dashboard search flow.

## v0.6.1

Guided workspace creation with custom instruction prompts.

- Added a no-argument `:CoduxWorkspaceCreate` flow for choosing a workspace name and custom startup instruction.
- Defaulted `:CoduxWorkspaceCreate <name>` to custom workspace instructions.
- Added a Vim-like multi-line floating instruction editor with bottom `:w` save and `:q` cancel hints.
- Added a create preview where users can create, edit the resolved instruction, or cancel safely.
- Stored the resolved startup instruction with each workspace so existing workspaces keep the prompt they were created with.
- Expanded the current workspaces window so larger saved workspace lists are visible when the editor has room.
