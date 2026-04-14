VERILATOR := verilator
BUILD_DIR := ./build
VERILATOR_FLAGS := --trace-fst -cc --exe --build -j -Wall --top-module top --Mdir build
# 每个传递给C编译器的参数前面都要加-CFLAGS
CFLAGS := -CFLAGS -Wall -CFLAGS -Werror -CFLAGS -Wno-unused-function -CFLAGS -DNPC_FTRACE -CFLAGS -ggdb3
# 每个传递给链接器的参数前面都要加-LDFLAGS
LDFLAGS := -LDFLAGS -lreadline
INC_PATH += $(NPC_HOME)/include
INCFLAGS += $(addprefix -CFLAGS -I, $(INC_PATH))
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v")
CSRCS = $(shell find $(abspath ./csrc) $(abspath ./trace) -name "*.c" -or -name "*.cc" -or -name "*.cpp")
ALL := ./dummy.bin

sim: $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) $(CFLAGS) $(LDFLAGS) $(INCFLAGS) $(VSRCS) $(CSRCS)  
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "Write this Makefile by your self."

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)
	
wave:
	gtkwave waveform.fst

run:
	$(BUILD_DIR)/Vtop $(ALL)

gdb:
	gdb $(BUILD_DIR)/Vtop

.PHONY:  sim run clean wave

clean: 
	@rm -rf $(BUILD_DIR)

include ../Makefile
