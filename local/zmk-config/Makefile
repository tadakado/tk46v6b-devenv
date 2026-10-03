CONFIG_DIR = config
SHIELDS_DIR = $(CONFIG_DIR)/boards/shields

CONTAINER_NAME = zmk-dev

TARGET_NAME = tk46v6

# --- Build dependencies ---------------------------------------------------
# A target rebuilds when its own shield files, the shared common/ snippets, or
# any out-of-tree module source changes. (Modules live beside this config dir.)
MODULE_SRCS = $(shell find ../zmk-modules -type f -not -path '*/.git/*' 2>/dev/null)
COMMON_SRCS = $(shell find $(SHIELDS_DIR)/common -type f 2>/dev/null)

SRCS_DEVKIT = $(shell find $(SHIELDS_DIR)/devkit -type f) $(COMMON_SRCS) $(MODULE_SRCS)
SRCS_LEFT   = $(shell find $(SHIELDS_DIR)/tk46v6 -type f ! -name "*_right*") $(COMMON_SRCS) $(MODULE_SRCS)
SRCS_RIGHT  = $(shell find $(SHIELDS_DIR)/tk46v6 -type f ! -name "*_left*") $(COMMON_SRCS) $(MODULE_SRCS)

TARGET_LEFT = ../zmk/app/build/left/zephyr/zmk.uf2
TARGET_RIGHT = ../zmk/app/build/right/zephyr/zmk.uf2
TARGET_SETTINGS_RESET = ../zmk/app/build/settings_reset/zephyr/zmk.uf2
TARGET_DEVKIT = ../zmk/app/build/devkit/zephyr/zmk.uf2

# Named UF2 copies produced by the build recipes (host paths), used for flashing.
FLASH_LEFT = ../zmk/app/build/$(TARGET_NAME)_left.uf2
FLASH_RIGHT = ../zmk/app/build/$(TARGET_NAME)_right.uf2
FLASH_DEVKIT = ../zmk/app/build/devkit.uf2
FLASH_SETTINGS_RESET = ../zmk/app/build/settings_reset.uf2

TTY_FLAG = $(shell [ -t 0 ] && echo "-it" || echo "-i")
DOCKER_EXEC = docker exec -w /workspaces/zmk/app $(TTY_FLAG) -e TERM=xterm-256color $(CONTAINER_NAME)

# --- Common west build arguments ------------------------------------------
# Use the ZMK board *variant* (xiao_ble/nrf52840/zmk), not the bare xiao_ble.
# The variant applies ZMK's board layer (xiao_ble_zmk_defconfig + _zmk.dts),
# which provides BLE, the NVS/flash settings backend AND the storage partition
# so bonds persist. The bare board omits all of that.
BOARD_ARG  = -b xiao_ble/nrf52840/zmk
CONFIG_ARG = -DZMK_CONFIG="/workspaces/zmk-config/config"
# USB-logging + ZMK Studio console (left + devkit; the right peripheral has none).
SNIPPETS    = -S studio-rpc-usb-uart -S zmk-usb-logging
STUDIO_DEFS = -DCONFIG_ZMK_STUDIO=y -DCONFIG_ZMK_STUDIO_LOCKING=n

MOD = /workspaces/zmk-modules
MODULES_FULL  = -DZMK_EXTRA_MODULES="$(MOD)/zmk-ir;$(MOD)/zmk-rgb-indicator;$(MOD)/zmk-ble-debug;$(MOD)/zmk-bootloader-1200;$(MOD)/zmk-ble-mouse-host"
MODULES_RIGHT = -DZMK_EXTRA_MODULES="$(MOD)/zmk-ir;$(MOD)/zmk-rgb-indicator;$(MOD)/zmk-ble-debug;$(MOD)/zmk-bootloader-1200"
# settings_reset is a minimal, single-purpose utility shield -- just enough to
# let flash.sh's 1200bps touch re-enter the bootloader afterward (to flash the
# real firmware next) without a manual RESET button press.
MODULES_SETTINGS_RESET = -DZMK_EXTRA_MODULES="$(MOD)/zmk-bootloader-1200"

# Flash a UF2 to the XIAO bootloader drive (host side, not inside the container).
# Auto-detects the mounted UF2 volume by looking for INFO_UF2.TXT, so it works
# regardless of the bootloader's volume name. Put the board in bootloader mode
# (double-tap RESET) before running.
define flash_uf2
	@uf2="$(1)"; \
	if [ ! -f "$$uf2" ]; then echo "ERROR: UF2 not found: $$uf2"; exit 1; fi; \
	vol=""; n=0; \
	for v in /Volumes/*; do \
		if [ -f "$$v/INFO_UF2.TXT" ]; then vol="$$v"; n=$$((n+1)); fi; \
	done; \
	if [ "$$n" -eq 0 ]; then \
		echo "ERROR: No UF2 bootloader drive mounted."; \
		echo "       Double-tap RESET on the target board, then retry."; \
		exit 1; \
	fi; \
	if [ "$$n" -gt 1 ]; then \
		echo "ERROR: $$n UF2 drives mounted -- can't tell which board is the target:"; \
		for v in /Volumes/*; do [ -f "$$v/INFO_UF2.TXT" ] && echo "         $$v"; done; \
		echo "       Connect/enter-bootloader on ONE board at a time, then retry."; \
		exit 1; \
	fi; \
	echo "Flashing $$uf2 -> $$vol"; \
	cp "$$uf2" "$$vol/"; \
	echo "Done. The board will reboot automatically."
endef

.PHONY: build left right settings_reset devkit clean \
        flash_left flash_right flash_devkit flash_settings_reset

build: $(TARGET_LEFT) $(TARGET_RIGHT)
left: $(TARGET_LEFT)
right: $(TARGET_RIGHT)
settings_reset: $(TARGET_SETTINGS_RESET)
devkit: $(TARGET_DEVKIT)

# Build (if needed) then flash to the bootloader drive. One board at a time.
flash_left: $(TARGET_LEFT)
	$(call flash_uf2,$(FLASH_LEFT))

flash_right: $(TARGET_RIGHT)
	$(call flash_uf2,$(FLASH_RIGHT))

flash_devkit: $(TARGET_DEVKIT)
	$(call flash_uf2,$(FLASH_DEVKIT))

flash_settings_reset: $(TARGET_SETTINGS_RESET)
	$(call flash_uf2,$(FLASH_SETTINGS_RESET))

$(TARGET_LEFT): $(SRCS_LEFT)
	$(DOCKER_EXEC) west build -d build/left $(BOARD_ARG) $(SNIPPETS) -- -DSHIELD="$(TARGET_NAME)_left" $(CONFIG_ARG) $(STUDIO_DEFS) $(MODULES_FULL)
	$(DOCKER_EXEC) cp build/left/zephyr/zmk.uf2 build/$(TARGET_NAME)_left.uf2

$(TARGET_RIGHT): $(SRCS_RIGHT)
	$(DOCKER_EXEC) west build -d build/right $(BOARD_ARG) -- -DSHIELD="$(TARGET_NAME)_right" $(CONFIG_ARG) $(MODULES_RIGHT)
	$(DOCKER_EXEC) cp build/right/zephyr/zmk.uf2 build/$(TARGET_NAME)_right.uf2

$(TARGET_SETTINGS_RESET):
	$(DOCKER_EXEC) west build -d build/settings_reset $(BOARD_ARG) -- -DSHIELD=settings_reset $(MODULES_SETTINGS_RESET)
	$(DOCKER_EXEC) cp build/settings_reset/zephyr/zmk.uf2 build/settings_reset.uf2

$(TARGET_DEVKIT): $(SRCS_DEVKIT)
	$(DOCKER_EXEC) west build -d build/devkit $(BOARD_ARG) $(SNIPPETS) -- -DSHIELD=devkit $(CONFIG_ARG) $(STUDIO_DEFS) $(MODULES_FULL)
	$(DOCKER_EXEC) cp build/devkit/zephyr/zmk.uf2 build/devkit.uf2

clean:
	$(DOCKER_EXEC) rm -rf build
