all:
	@echo "Write this Makefile by your self."

sim:
	verilator --trace --cc --exe --build -j -Wall hello.cpp top.v	
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@echo "Write this Makefile by your self."

include ../Makefile
