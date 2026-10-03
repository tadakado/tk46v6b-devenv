# Forward every target to the local-only Makefile, run from zmk-config/ (that
# Makefile uses paths relative to it). Usage from here: make build, make flash_left, ...
.DEFAULT_GOAL := build

Makefile: ;

%:
	@$(MAKE) --no-print-directory -C zmk-config -f ../local/zmk-config/Makefile $@
