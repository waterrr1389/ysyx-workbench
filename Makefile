# Run everything from this directory after `source ../env.sh`.
WORK     := $(abspath .)
BUILD    := $(WORK)/build
SIM_DIR  := $(BUILD)/sim
SIM_BIN  := $(SIM_DIR)/VysyxSoCFull

RTL_PKG  := $(WORK)/rtl/ysyx_00000000_pkg.sv
RTL_SRCS := $(RTL_PKG) $(filter-out $(RTL_PKG),$(wildcard $(WORK)/rtl/*.sv))
SIM_RTL  := $(wildcard $(WORK)/rtl/sim/*.sv)
SOC_SRCS := $(YSYXSOC_HOME)/build/ysyxSoCFull.v $(shell find $(YSYXSOC_HOME)/perip -name '*.v')
CXX_SRCS := $(wildcard $(WORK)/sim/*.cpp)
CXX_HDRS := $(wildcard $(WORK)/sim/*.h)

TRACE ?= 0
VFLAGS := --cc --exe --build -j 0 -O3 --x-assign fast --x-initial fast --noassert \
          --timescale "1ns/1ns" --no-timing --autoflush -Wno-fatal -Wno-lint -Wno-style \
          --top-module ysyxSoCFull \
          -I$(YSYXSOC_HOME)/perip/uart16550/rtl -I$(YSYXSOC_HOME)/perip/spi/rtl \
          -CFLAGS "-O2 -std=c++17 -I$(SPIKE_HOME)/include" \
          -LDFLAGS "-L$(SPIKE_HOME)/lib -Wl,-rpath,$(SPIKE_HOME)/lib -lriscv -lsoftfloat -ldl -lpthread"
ifeq ($(TRACE),1)
VFLAGS += --trace-fst -CFLAGS -DTRACE
endif

sim: $(SIM_BIN)

# ysyxSoCFull.v is generated from the ysyxSoC Chisel sources and not tracked there.
$(YSYXSOC_HOME)/build/ysyxSoCFull.v: $(shell find $(YSYXSOC_HOME)/src -name '*.scala')
	timeout 1800 $(MAKE) -C $(YSYXSOC_HOME) verilog

$(SIM_BIN): $(RTL_SRCS) $(SIM_RTL) $(SOC_SRCS) $(CXX_SRCS) $(CXX_HDRS) Makefile
	@mkdir -p $(SIM_DIR)
	verilator $(VFLAGS) --Mdir $(SIM_DIR) $(RTL_SRCS) $(SIM_RTL) $(SOC_SRCS) $(CXX_SRCS) -o $(SIM_BIN)
	@touch $(SIM_BIN)

# Interactive build with NVBoard (LEDs, switches, 7-segment, PS/2 keyboard, VGA, UART terminal).
NVB_DIR  := $(BUILD)/nvboard
NVB_BIN  := $(NVB_DIR)/VysyxSoCFull
NVB_BIND := $(NVB_DIR)/auto_bind.cpp
include $(NVBOARD_HOME)/scripts/nvboard.mk

$(NVB_BIND): nvboard/ysyxSoCFull.nxdc
	@mkdir -p $(NVB_DIR)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $< $@

$(NVB_BIN): $(RTL_SRCS) $(SIM_RTL) $(SOC_SRCS) $(CXX_SRCS) $(CXX_HDRS) $(NVB_BIND) $(NVBOARD_ARCHIVE) Makefile
	verilator $(VFLAGS) -CFLAGS "-DNVBOARD -I$(NVBOARD_USR_INC) $$(sdl2-config --cflags)" \
	  -LDFLAGS "$$(sdl2-config --libs) -lSDL2_image -lSDL2_ttf" \
	  --Mdir $(NVB_DIR) $(RTL_SRCS) $(SIM_RTL) $(SOC_SRCS) $(CXX_SRCS) $(NVB_BIND) $(NVBOARD_ARCHIVE) -o $(NVB_BIN)
	@touch $(NVB_BIN)

nvboard: $(NVB_BIN)

# Run an image on NVBoard (no DiffTest, no cycle limit beyond MAX_CYCLES).
run-nvboard: $(NVB_BIN)
	$(NVB_BIN) --$(BOOT) $(IMG) --max-cycles $(MAX_CYCLES)

# Run one raw image. BOOT selects where the image is placed; DIFFTEST=0 disables the reference model.
IMG        ?=
BOOT       ?= flash
DIFFTEST   ?= 1
MAX_CYCLES ?= 500000000
SIM_ARGS   := --$(BOOT) $(IMG) --max-cycles $(MAX_CYCLES) $(if $(filter 1,$(DIFFTEST)),--difftest)

run-img: $(SIM_BIN)
	timeout 1800 $(SIM_BIN) $(SIM_ARGS)

AM_KERNELS_HOME ?= $(YSYX_HOME)/deps/am-kernels
CPU_TESTS := $(AM_KERNELS_HOME)/tests/cpu-tests

# All am-kernels cpu-tests on ysyxSoC (DiffTest on by default).
test-cpu: $(SIM_BIN)
	scripts/test-cpu.sh $(CPU_TESTS)

# The handout's PSRAM and SDRAM memory tests; MEM_KIB limits the tested size (default: all).
MEM_KIB ?=
test-mem: $(SIM_BIN)
	scripts/test-mem.sh $(SIM_BIN) $(AM_KERNELS_HOME) $(MEM_KIB)

# RT-Thread on ysyxSoC with a shell command typed over UART.
RT_THREAD_BSP ?= $(YSYX_HOME)/deps/rt-thread-am/bsp/abstract-machine
test-rtthread: $(SIM_BIN)
	scripts/test-rtthread.sh $(SIM_BIN) $(RT_THREAD_BSP)

# Lint only the core, with all warnings.
lint:
	verilator --lint-only -Wall --top-module ysyx_00000000 $(RTL_SRCS) $(SIM_RTL)

clean:
	rm -rf $(BUILD)

.PHONY: sim lint clean run-img test-cpu test-mem test-rtthread nvboard run-nvboard
