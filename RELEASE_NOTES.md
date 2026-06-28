# Release Notes

## Unreleased

Workspace conversation resume.

- Saved Codux workspaces now persist the Codex session id after launch.
- Reopening a saved workspace resumes that exact Codex conversation when the local transcript is available.
- Older saved workspaces seed their session id from the most recent local Codex session for the same project root.
- Workspace instructions are now passed to Codex as session guidance instead of an auto-submitted first prompt.
- Codux keeps workspace instructions private in its workspace state and does not write `AGENTS.md`.

## v0.6.2

Workspace dashboard search.

- Added a search field above the workspace dashboard.
- Fuzzy search filters saved workspaces and previews the closest match in the dashboard.
- Pressing `<CR>` in search focuses the highlighted dashboard result so dashboard actions can be run.
- Added `s` to search again from the dashboard and kept `<C-q>` closing the dashboard/search UI.
- Documented the workspace dashboard search flow.

## v0.6.1

Guided workspace creation with custom template prompts.

- Added a no-argument `:CoduxWorkspaceCreate` flow for choosing a workspace name and custom startup instruction.
- Defaulted `:CoduxWorkspaceCreate <name>` to custom workspace instructions, with `--template <template>` still available for explicit templates.
- Added a Vim-like multi-line floating instruction editor with bottom `:w` save and `:q` cancel hints.
- Saved custom instructions as reusable workspace templates that appear in future template lists.
- Added a create preview where users can create, edit the resolved instruction, or cancel safely.
- Stored the resolved startup instruction with each workspace so existing workspaces keep the prompt they were created with.
- Added shorter template commands: `:CoduxTemplateList` and `:CoduxTemplatePreview <template>`.
- Added template removal with `:CoduxTemplateDelete <template>`.
- Stopped appending template names to new workspace tmux window names.
- Added saved-template editing from the workspace dashboard with `e`.
- Expanded the current workspaces window so larger saved workspace lists are visible when the editor has room.
