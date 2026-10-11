# AXI4-Lite formal checks of the memory path, run with SymbiYosys.
# Usage: make -C npc/formal [sram|arbiter|ifu|lsu]  (default: all four)
# Needs sby, yosys, yices and sv2v.
# Each job runs its bmc, cover and prove tasks; add TASKS=prove to pick some.
BUILD_DIR := build
JOBS := sram arbiter ifu lsu
TASKS ?=

all: $(JOBS)

# Yosys cannot execute DPI-C: memory reads become a free value and writes are
# dropped. The check fails loudly if SRAM.v changes and a call slips through.
$(BUILD_DIR)/SRAM.v: ../vsrc/SRAM.v Makefile
	@mkdir -p $(BUILD_DIR)
	sed -e 's/import "DPI-C" function int pmem_read.*/(* anyseq *) wire [DATA_LEN-1:0] f_mem_rdata;/' \
	    -e '/import "DPI-C" function void pmem_write/d' \
	    -e 's/pmem_read(araddr)/f_mem_rdata/' \
	    -e 's/pmem_write([^;]*);/;/' \
	    $< > $@
	@if grep -n 'pmem_\|DPI-C' $@; then echo "DPI-C left in $@" >&2; rm -f $@; exit 1; fi

# The Yosys parser rejects an action block on an immediate assertion.
# Keep the assertion itself and drop its `else $fatal` reporting.
$(BUILD_DIR)/IFU.v $(BUILD_DIR)/LSU.v: $(BUILD_DIR)/%.v: ../vsrc/%.v Makefile
	@mkdir -p $(BUILD_DIR)
	sed -e '/^[[:space:]]*assert (.*)[[:space:]]*$$/s/$$/;/' \
	    -e '/else \$$fatal/d' \
	    $< > $@
	@if grep -n 'fatal' $@; then echo "\$$fatal left in $@" >&2; rm -f $@; exit 1; fi

# The Yosys parser lacks SystemVerilog assignment patterns; sv2v lowers them.
# Yosys also cannot resolve hierarchical references, so the converted copy
# exports its route state on an extra f_state port for the induction
# invariants in arbiter_axil.sv.
$(BUILD_DIR)/Arbiter.v: ../vsrc/Arbiter.sv Makefile
	@mkdir -p $(BUILD_DIR)
	sv2v $< | sed -e 's/^module Arbiter (/module Arbiter (f_state,/' \
	    -e 's/^endmodule/output wire [1:0] f_state; assign f_state = state; endmodule/' > $@
	@grep -q 'assign f_state = state;' $@ || { echo "f_state not exported in $@" >&2; rm -f $@; exit 1; }

sram: $(BUILD_DIR)/SRAM.v
arbiter: $(BUILD_DIR)/Arbiter.v
ifu: $(BUILD_DIR)/IFU.v
lsu: $(BUILD_DIR)/LSU.v

$(JOBS):
	sby -f --prefix $(BUILD_DIR)/$@ $@.sby $(TASKS)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all clean $(JOBS)
