# Select exactly one RV32 instruction decoder.
ifeq ($(CONFIG_RISCV_DECODER_HIERARCHICAL),y)
SRCS-BLACKLIST-y += src/isa/riscv32/inst.c
else
SRCS-BLACKLIST-y += src/isa/riscv32/inst-hierarchical.cc
endif
