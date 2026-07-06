.PHONY: test

LUA ?= lua
LUAJIT ?= luajit
NVIM_BIN ?= nvim
NVIM_HEADLESS ?= $(NVIM_BIN) --headless -u NONE -i NONE --cmd 'set shadafile=NONE'
TEST_SPECS := \
	tests/action_palette_spec.lua \
	tests/compat_spec.lua \
	tests/confirmation_footer_spec.lua \
	tests/commands_spec.lua \
	tests/dashboard_search_spec.lua \
	tests/filetypes_spec.lua \
	tests/mission_spec.lua \
	tests/mission_dashboard_layout_spec.lua \
	tests/mission_dashboard_spec.lua \
	tests/mission_dashboard_viewport_spec.lua \
	tests/mission_dashboard_windows_spec.lua \
	tests/mission_dashboard_actions_spec.lua \
	tests/mission_dashboard_action_palette_spec.lua \
	tests/mission_dashboard_workspace_actions_spec.lua \
	tests/mission_control_dashboard_lines_spec.lua \
	tests/mission_control_dashboard_windows_spec.lua \
	tests/mission_control_preview_actions_spec.lua \
	tests/mission_control_resize_setup_spec.lua \
	tests/mission_lifecycle_spec.lua \
	tests/mission_output_buffer_spec.lua \
	tests/mission_output_preview_spec.lua \
	tests/mission_output_panel_spec.lua \
	tests/open_profile_spec.lua \
	tests/prompt_actions_spec.lua \
	tests/workspace_create_spec.lua \
	tests/workspace_git_spec.lua \
	tests/workspace_instructions_spec.lua \
	tests/workspace_lifecycle_actions_spec.lua \
	tests/workspace_lifecycle_spec.lua \
	tests/workspace_launch_spec.lua \
	tests/workspace_instruction_actions_spec.lua \
	tests/workspace_prepare_spec.lua \
	tests/workspace_registry_spec.lua \
	tests/workspace_residue_spec.lua \
	tests/workspace_remote_actions_spec.lua \
	tests/workspace_remote_spec.lua \
	tests/workspace_runtime_worktree_spec.lua \
	tests/workspace_runtime_lifecycle_spec.lua \
	tests/workspace_runtime_prepare_spec.lua \
	tests/workspace_runtime_remote_spec.lua \
	tests/workspace_runtime_spec.lua \
	tests/workspace_store_spec.lua \
	tests/workspace_sync_spec.lua \
	tests/workspace_manager_spec.lua \
	tests/workspace_manager_selection_spec.lua \
	tests/workspace_ui_spec.lua \
	tests/terminal_spec.lua \
	tests/terminal_window_spec.lua \
	tests/text_spec.lua \
	tests/ui_spec.lua \
	tests/token_monitor_spec.lua

test:
	for f in $(TEST_SPECS); do $(LUA) $$f || exit 1; done
	for f in $(TEST_SPECS); do $(NVIM_HEADLESS) -c 'set rtp+=.' -c "lua dofile('$$f')" -c 'qa!' || exit 1; done
	for f in lua/codux/*.lua tests/*.lua; do $(LUAJIT) -e "assert(loadfile('$$f'))" || exit 1; done
	$(NVIM_HEADLESS) -c 'set rtp+=.' -c 'lua require("codux").setup({ token_monitor = false })' -c 'qa!'
	$(NVIM_HEADLESS) -c 'set rtp+=.' -c 'lua require("codux").setup({ token_monitor = false })' -c 'checkhealth codux' -c 'qa!'
