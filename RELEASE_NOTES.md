# Release Notes

## Unreleased

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
- Added `s` to search again from the dashboard and kept `<C-q>` closing the dashboard/search UI.
- Documented the workspace dashboard search flow.

## v0.6.1

Guided workspace creation with custom instruction prompts.

- Added a no-argument `:CoduxWorkspaceCreate` flow for choosing a workspace name and custom startup instruction.
- Defaulted `:CoduxWorkspaceCreate <name>` to custom workspace instructions.
- Added a Vim-like multi-line floating instruction editor with bottom `:w` save and `:q` cancel hints.
- Added a create preview where users can create, edit the resolved instruction, or cancel safely.
- Stored the resolved startup instruction with each workspace so existing workspaces keep the prompt they were created with.
- Expanded the current workspaces window so larger saved workspace lists are visible when the editor has room.
