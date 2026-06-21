# Release Notes

## v0.6.0

Guided workspace creation with custom template prompts.

- Added a no-argument `:CoduxWorkspaceCreate` flow for choosing a workspace name, template, and startup instruction.
- Added custom workspace instructions with `:CoduxWorkspaceCreate <name> --custom`.
- Added a Vim-like multi-line floating instruction editor with bottom `:w` save and `:q` cancel hints.
- Saved custom instructions as reusable workspace templates that appear in future template lists.
- Added a create preview where users can create, edit the resolved instruction, or cancel safely.
- Stored the resolved startup instruction with each workspace so existing workspaces keep the prompt they were created with.
- Added shorter template commands: `:CoduxTemplateList` and `:CoduxTemplatePreview <template>`.
- Added template removal from the workspace template picker and `:CoduxTemplateDelete <template>`.
