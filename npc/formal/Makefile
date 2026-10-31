# AXI4 formal checks of the bus masters and the memory system, run with SymbiYosys.
# Usage: make -C npc/formal [bus|ifu|lsu]  (default: all three)
#        add TASKS=prove or TASKS=cover to run one task
# Needs sby, yosys, yices and sv2v.
BUILD_DIR := build
JOBS := bus ifu lsu
TASKS ?=
RTL := ../vsrc

PKG := $(RTL)/npc_pkg.sv axi_props.sv
bus_SRCS := $(RTL)/Arbiter.sv $(RTL)/Xbar.sv $(RTL)/SRAM.sv $(RTL)/UART.sv bus_check.sv
ifu_SRCS := $(RTL)/IFU.sv ifu_check.sv
lsu_SRCS := $(RTL)/LSU.sv lsu_check.sv

all: $(JOBS)

# Yosys reads neither packages nor packed structs; sv2v lowers each job to one Verilog file.
$(BUILD_DIR)/%.v: $(PKG) Makefile
	@mkdir -p $(BUILD_DIR)
	sv2v -DFORMAL --exclude=Assert $(PKG) $($*_SRCS) > $@

$(BUILD_DIR)/bus.v: $(bus_SRCS)
$(BUILD_DIR)/ifu.v: $(ifu_SRCS)
$(BUILD_DIR)/lsu.v: $(lsu_SRCS)

$(JOBS): %: $(BUILD_DIR)/%.v
	sby -f --prefix $(BUILD_DIR)/$@ $@.sby $(TASKS)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean $(JOBS)
