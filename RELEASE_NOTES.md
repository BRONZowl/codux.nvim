# Release Notes

## Unreleased

## v1.0.2

Mission Manager dispatch and documentation refresh.

codux.nvim v1.0.2 adds a Mission Manager console with multi-role dispatch,
hardens Grok usage labels, and rewrites the README for clearer dual-provider
workflows.

- Every new mission always creates a **Manager** role (plus default **Agent**); custom role lists still get Manager injected when missing.
- Mission row in Mission Control previews and controls the Manager session (same Output panel and `<C-o>` as a role row).
- Manager can activate workers via JSON dispatch files under `.agents/codux/missions/<mission>/dispatch/pending/` (`start`, `prompt`, `start_and_prompt`, `create_role`, `update_focus`).
- Pending dispatch is processed while Mission Control is open and via `:CoduxMissionProcessDispatch`.
- Mission menu: Start Manager, Process Dispatch, Add Manager (legacy). Role menu: Prompt Role (`t`).
- Dashboard shows last dispatch status (`dispatch | N ok | M failed`).
- Sort Manager role first in mission role lists; fix Manager role preview after compact mission selection.
- Improve Grok token monitor sampling and rate-limit headroom labels.
- Rewrite README with hero/badges, features-first layout, FAQ, showcase, and first-class Codex + Grok documentation.

## v1.0.1

Global default provider and Grok usage polish.

codux.nvim v1.0.1 streamlines provider selection with a session-wide default,
keeps per-workspace switching intact, and hardens Grok token/status monitoring.

- Added `<leader>zP` and `:CoduxSetDefaultProvider` to set the global default agent provider (Grok or Codex) for the Neovim session.
- Open (`<leader>zc` / `:Codux`), workspace create, and mission create now skip the provider step and open the permission-profile picker for the global default.
- Left Mission Control and workspace dashboard Switch Profile menus as full two-step provider + profile pickers so roles and workspaces can still diverge from the default.
- Added Grok API rate-limit usage probing (`tpm` / `rpm`) with OAuth/API-key auth resolution, and cached Mission Control token usage per agent provider.
- Simplified leader-z which-key chrome and menu labels, and fixed Grok dashboard prompt submission and interactive submit paths.
- Hardened token monitor refresh and UI updates, and fixed provider configuration / README guidance for nested provider commands.
- Expanded regression coverage for default-provider selection, open/create profile pickers, and related command wiring.

## v1.0.0

Codex and Grok provider release.

codux.nvim v1.0.0 makes Codex CLI and Grok CLI first-class agent providers across the single-session popup, tmux workspaces, and Mission Control.

- Added Grok CLI provider support with default, auto, and full-access profiles alongside the existing Codex profiles.
- Added two-step provider/profile pickers for `<leader>zc`, workspace creation, mission creation, and workspace profile switching.
- Added provider-aware workspace and mission startup so saved workspaces and mission roles launch with the selected Codex or Grok command.
- Kept Grok startup arguments minimal by using the configured profile command, adding `--rules` only when instructions exist, and pasting initial prompts after the Grok TUI is ready.
- Added active and inactive workspace profile switching, including active workspace restarts and saved startup-profile updates for inactive workspaces.
- Updated workspace and mission dashboards so profile labels identify Codex versus Grok.
- Reduced Mission Control output preview flicker and refreshed highlighted active-role previews correctly after profile-switch restarts.
- Expanded regression coverage for providers, profile pickers, workspace and mission creation, profile switching, Grok startup behavior, dashboard labels, and output-preview refreshes.

## v0.9.1

Mission output and cleanup hardening.

codux.nvim v0.9.1 tightens the v0.9 Mission Control workflow with Codux-terminal-backed output previews, cleaner startup behavior, and reliable destructive cleanup for project-scoped mission worktrees.

- Reworked mission output previews to use Codux terminal controls so active role previews behave like the default Codux window while preserving dashboard layout and output scale.
- Reduced output preview flicker during role startup and while viewing previews outside output-control mode.
- Hardened mission startup sends so role sessions clear stale prompt input before submitting startup instructions.
- Fixed mission deletion from the dashboard so project-scoped role worktrees are resolved from saved state, matching tmux windows are closed by pane cwd when needed, Git worktrees are removed, and role branches are deleted.
- Expanded regression coverage for Mission Control output previews, terminal startup, project-scoped worktree launch, remote workspace actions, and mission worktree deletion rollback.

## v0.9.0

Mission Control focus and output control.

codux.nvim v0.9.0 reshapes Mission Control around a focused single-Agent workflow, tighter role context, direct output control, and sturdier mission worktree handling.

- Changed the default Mission Control crew to one focused Agent role that preserves prompt fidelity, keeps context narrow, validates cheaply, and asks only high-impact questions.
- Added mission focus packets that travel with startup and role prompts while staying separate from stable workspace instructions.
- Added explicit output-control mode for active role previews with `<C-o>`, removed redundant dashboard prompt commands, and kept `Esc` available for Codex inside output sessions.
- Moved mission role worktrees into project-scoped `../codux-worktrees/<project>/<workspace>` directories and reconciled manually moved worktrees before dashboard and output preview use.
- Added role rename support that updates mission/workspace metadata, instruction files, Git worktrees, branches, tmux/session state, and dashboard output paths together.
- Fixed stale output previews, preview session names, active-preview dashboard resizing, and selected-row highlighting when switching between mission and workspace rows.
- Refactored mission output cleanup, focus update flows, and worktree reconciliation helpers with expanded regression coverage.
- Updated the README to document current Mission Control controls, focus packets, output control, project-scoped worktrees, and moved-worktree reconciliation.

## v0.8.2

Mission dashboard stale-residue cleanup.

codux.nvim v0.8.2 fixes Mission Control dashboard behavior when deleted missions leave empty worktree residue behind, and tightens cleanup reporting around those paths.

- Fixed the mission dashboard empty state so stale Mission Control residue opens a cleanup-capable dashboard instead of immediately prompting to create a new mission.
- Added conservative residue detection for empty workspace-state buckets, empty directory shells under the configured worktree directory, and orphaned Git worktrees.
- Added dashboard cleanup for empty residue while preserving non-empty directories and orphaned Git worktrees.
- Hardened mission/workspace delete and rollback cleanup so failed Git worktree or branch cleanup is reported instead of silently leaving confusing residue.
- Expanded regression coverage for residue detection, dashboard empty states, mission lifecycle cleanup, and rollback failure handling.

## v0.8.1

Mission Control polish and internal cleanup.

codux.nvim v0.8.1 tightens Mission Control interactions after the v0.8.0 release, with focused fixes for dashboard creation, prompt handling, output preview focus, and workspace recency state.

- Fixed `<leader>zM` / mission dashboard startup so the create-mission prompt is only shown when there are no existing missions to open.
- Made mission discovery include role workspaces stored under their Git worktree roots, so the mission dashboard sees mission roles created outside the base checkout state bucket.
- Kept the mission dashboard output preview aligned with the active workspace highlight while preserving the existing dashboard selection and scrolling behavior.
- Guarded single-line prompt popups so leader mappings do not run while the user is typing prompt input.
- Preserved workspace recency metadata when workspace state is refreshed, keeping dashboard ordering stable across runtime updates.
- Aligned the mission-create confirmation controls with the workspace-create confirmation flow, including the edit-mission command label.
- Split large Mission Control, workspace runtime, terminal, compatibility, and store modules into focused helpers with expanded regression coverage.

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
