#ifndef __RISCV_NEMU_CONTEXT_OFFSET_H__
#define __RISCV_NEMU_CONTEXT_OFFSET_H__

#if __riscv_xlen == 32
#define RISCV_CONTEXT_WORD_SIZE 4
#elif __riscv_xlen == 64
#define RISCV_CONTEXT_WORD_SIZE 8
#else
#error Unsupported RISC-V XLEN
#endif

#ifdef __riscv_e
#define RISCV_CONTEXT_GPR_COUNT 16
#else
#define RISCV_CONTEXT_GPR_COUNT 32
#endif

#define RISCV_CONTEXT_GPR_OFFSET(n) \
  ((n) * RISCV_CONTEXT_WORD_SIZE)
#define RISCV_CONTEXT_MCAUSE_OFFSET \
  ((RISCV_CONTEXT_GPR_COUNT + 0) * RISCV_CONTEXT_WORD_SIZE)
#define RISCV_CONTEXT_MSTATUS_OFFSET \
  ((RISCV_CONTEXT_GPR_COUNT + 1) * RISCV_CONTEXT_WORD_SIZE)
#define RISCV_CONTEXT_MEPC_OFFSET \
  ((RISCV_CONTEXT_GPR_COUNT + 2) * RISCV_CONTEXT_WORD_SIZE)
#define RISCV_CONTEXT_PDIR_OFFSET \
  ((RISCV_CONTEXT_GPR_COUNT + 3) * RISCV_CONTEXT_WORD_SIZE)
#define RISCV_CONTEXT_SIZE \
  ((RISCV_CONTEXT_GPR_COUNT + 4) * RISCV_CONTEXT_WORD_SIZE)

#ifndef __ASSEMBLER__
#include <stddef.h>

#if defined(__cplusplus)
#define RISCV_CONTEXT_STATIC_ASSERT static_assert
#else
#define RISCV_CONTEXT_STATIC_ASSERT _Static_assert
#endif

RISCV_CONTEXT_STATIC_ASSERT(
    offsetof(Context, gpr) == RISCV_CONTEXT_GPR_OFFSET(0),
    "Context.gpr offset mismatch");
RISCV_CONTEXT_STATIC_ASSERT(
    offsetof(Context, mcause) == RISCV_CONTEXT_MCAUSE_OFFSET,
    "Context.mcause offset mismatch");
RISCV_CONTEXT_STATIC_ASSERT(
    offsetof(Context, mstatus) == RISCV_CONTEXT_MSTATUS_OFFSET,
    "Context.mstatus offset mismatch");
RISCV_CONTEXT_STATIC_ASSERT(
    offsetof(Context, mepc) == RISCV_CONTEXT_MEPC_OFFSET,
    "Context.mepc offset mismatch");
RISCV_CONTEXT_STATIC_ASSERT(
    offsetof(Context, pdir) == RISCV_CONTEXT_PDIR_OFFSET,
    "Context.pdir offset mismatch");
RISCV_CONTEXT_STATIC_ASSERT(
    sizeof(Context) == RISCV_CONTEXT_SIZE,
    "Context size mismatch");

#undef RISCV_CONTEXT_STATIC_ASSERT
#endif

#endif
