.PHONY: test

LUA ?= lua
LUAJIT ?= luajit
NVIM_BIN ?= nvim
NVIM_HEADLESS ?= $(NVIM_BIN) --headless -u NONE -i NONE --cmd 'set shadafile=NONE'
TEST_SPECS := \
	tests/action_palette_spec.lua \
	tests/commands_spec.lua \
	tests/dashboard_search_spec.lua \
	tests/filetypes_spec.lua \
	tests/mission_spec.lua \
	tests/mission_dashboard_spec.lua \
	tests/mission_control_spec.lua \
	tests/mission_output_panel_spec.lua \
	tests/open_profile_spec.lua \
	tests/prompt_actions_spec.lua \
	tests/workspace_create_spec.lua \
	tests/workspace_git_spec.lua \
	tests/workspace_lifecycle_spec.lua \
	tests/workspace_launch_spec.lua \
	tests/workspace_remote_spec.lua \
	tests/workspace_runtime_spec.lua \
	tests/workspace_store_spec.lua \
	tests/workspace_manager_spec.lua \
	tests/workspace_ui_spec.lua \
	tests/terminal_spec.lua \
	tests/text_spec.lua \
	tests/ui_spec.lua \
	tests/token_monitor_spec.lua

test:
	for f in $(TEST_SPECS); do $(LUA) $$f || exit 1; done
	for f in $(TEST_SPECS); do $(NVIM_HEADLESS) -c 'set rtp+=.' -c "lua dofile('$$f')" -c 'qa!' || exit 1; done
	for f in lua/codux/*.lua tests/*.lua; do $(LUAJIT) -e "assert(loadfile('$$f'))" || exit 1; done
	$(NVIM_HEADLESS) -c 'set rtp+=.' -c 'lua require("codux").setup({ token_monitor = false })' -c 'qa!'
	$(NVIM_HEADLESS) -c 'set rtp+=.' -c 'lua require("codux").setup({ token_monitor = false })' -c 'checkhealth codux' -c 'qa!'
