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

$(SIM_BIN): $(RTL_SRCS) $(SIM_RTL) $(SOC_SRCS) $(CXX_SRCS) $(CXX_HDRS) Makefile
	@mkdir -p $(SIM_DIR)
	verilator $(VFLAGS) --Mdir $(SIM_DIR) $(RTL_SRCS) $(SIM_RTL) $(SOC_SRCS) $(CXX_SRCS) -o $(SIM_BIN)

# Lint only the core, with all warnings.
lint:
	verilator --lint-only -Wall --top-module ysyx_00000000 $(RTL_SRCS) $(SIM_RTL)

clean:
	rm -rf $(BUILD)

.PHONY: sim lint clean
