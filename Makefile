.PHONY: test

LUA ?= lua
LUAJIT ?= luajit
NVIM_BIN ?= nvim
NVIM_HEADLESS ?= $(NVIM_BIN) --headless -u NONE -i NONE --cmd 'set shadafile=NONE'

test:
	$(LUA) tests/workspace_status_spec.lua
	$(LUA) tests/token_monitor_spec.lua
	$(NVIM_HEADLESS) -c 'set rtp+=.' -c 'lua dofile("tests/workspace_status_spec.lua")' -c 'qa!'
	$(NVIM_HEADLESS) -c 'set rtp+=.' -c 'lua dofile("tests/token_monitor_spec.lua")' -c 'qa!'
	for f in lua/codux/*.lua tests/*.lua; do $(LUAJIT) -e "assert(loadfile('$$f'))" || exit 1; done
	$(NVIM_HEADLESS) -c 'set rtp+=.' -c 'lua require("codux").setup({ token_monitor = false })' -c 'qa!'
	$(NVIM_HEADLESS) -c 'set rtp+=.' -c 'lua require("codux").setup({ token_monitor = false })' -c 'checkhealth codux' -c 'qa!'
