# The model is compiled by Meson (meson.build): one build directory per
# configuration, chosen with meson options. This Makefile keeps the entry points
# AM's `make run` and the formal checks expect.
#   make sim                                   build ../build-npc
#   make sim BUILD_DIR=../build-npc-diff       another configuration, set up with
#                                              meson setup ../build-npc-diff . -Ddifftest=true

BUILD_DIR ?= $(abspath $(NPC_HOME)/../build-npc)
IMG := ./dummy.bin
ARGS ?=

$(BUILD_DIR)/build.ninja:
	meson setup $(BUILD_DIR) $(NPC_HOME)

# Ninja decides what is stale; it also makes the "sim RTL" tracer commit.
sim: $(BUILD_DIR)/build.ninja
	@ninja -C $(BUILD_DIR)

# Style checks off by default in sim; run on demand to catch unused or undriven signals
lint: $(BUILD_DIR)/build.ninja
	@ninja -C $(BUILD_DIR) lint

wave:
	gtkwave waveform.fst

run: sim
	$(BUILD_DIR)/Vtop $(if $(WAVE),-w waveform.fst) $(ARGS) $(IMG)

gdb: sim
	gdb $(BUILD_DIR)/Vtop

clean:
	-rm -rf $(BUILD_DIR)

.PHONY: sim run clean wave lint gdb
