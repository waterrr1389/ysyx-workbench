ifeq ($(CONFIG_RISCV_HIERARCHICAL_DECODE),y)
SRCS-BLACKLIST-y += src/isa/riscv32/inst.c
else
SRCS-BLACKLIST-y += src/isa/riscv32/inst-hierarchical.cc
endif
