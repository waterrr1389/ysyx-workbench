V_FLAGS = --trace --cc --exe --build -j -Wall
all:
	@echo "Write this Makefile by your self."

sim:
	verilator $(V_FLAGS) hello.cpp top.v	
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "Write this Makefile by your self."

.PHONY: run
run:
	obj_dir/Vtop
	gtkwave waveform.vcd

include ../Makefile
