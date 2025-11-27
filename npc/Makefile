VERILATOR := verilator
BUILD_DIR := ./build
VERILATOR_FLAGS := --trace-fst -cc --exe --build -j -Wall --top-module top --Mdir build
CFLAGS := -CFLAGS -Wall -CFLAGS -Werror
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")


sim: $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) $(CFLAGS) $(VSRCS) $(CSRCS)  
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "Write this Makefile by your self."

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	
wave:
	gtkwave waveform.fst

run:
	$(BUILD_DIR)/Vtop

.PHONY:  sim run clean wave

clean: 
	@rm -rf $(BUILD_DIR)

include ../Makefile
