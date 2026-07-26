#ifndef __DIFFTEST_ARCH_RISCV32_H__
#define __DIFFTEST_ARCH_RISCV32_H__

#include <stddef.h>
#include <stdint.h>

#define RISCV32_DIFFTEST_ABI_VERSION 1u
#define RISCV32_DIFFTEST_GPR_COUNT 32u
#define RISCV32_DIFFTEST_STATE_SIZE 152u
#define RISCV32_DIFFTEST_TO_DUT 0u
#define RISCV32_DIFFTEST_TO_REF 1u

typedef struct {
  uint32_t gpr[RISCV32_DIFFTEST_GPR_COUNT];
  uint32_t pc;
  uint32_t priv;
  uint32_t mstatus;
  uint32_t mtvec;
  uint32_t mepc;
  uint32_t mcause;
} riscv32_difftest_state_t;

#if defined(__cplusplus)
#define RISCV32_DIFFTEST_STATIC_ASSERT static_assert
#else
#define RISCV32_DIFFTEST_STATIC_ASSERT _Static_assert
#endif

RISCV32_DIFFTEST_STATIC_ASSERT(offsetof(riscv32_difftest_state_t, gpr) == 0,
                               "RV32 DiffTest GPR offset mismatch");
RISCV32_DIFFTEST_STATIC_ASSERT(offsetof(riscv32_difftest_state_t, pc) == 128,
                               "RV32 DiffTest PC offset mismatch");
RISCV32_DIFFTEST_STATIC_ASSERT(offsetof(riscv32_difftest_state_t, priv) == 132,
                               "RV32 DiffTest privilege offset mismatch");
RISCV32_DIFFTEST_STATIC_ASSERT(offsetof(riscv32_difftest_state_t, mstatus) ==
                                   136,
                               "RV32 DiffTest mstatus offset mismatch");
RISCV32_DIFFTEST_STATIC_ASSERT(offsetof(riscv32_difftest_state_t, mtvec) == 140,
                               "RV32 DiffTest mtvec offset mismatch");
RISCV32_DIFFTEST_STATIC_ASSERT(offsetof(riscv32_difftest_state_t, mepc) == 144,
                               "RV32 DiffTest mepc offset mismatch");
RISCV32_DIFFTEST_STATIC_ASSERT(offsetof(riscv32_difftest_state_t, mcause) ==
                                   148,
                               "RV32 DiffTest mcause offset mismatch");
RISCV32_DIFFTEST_STATIC_ASSERT(sizeof(riscv32_difftest_state_t) ==
                                   RISCV32_DIFFTEST_STATE_SIZE,
                               "RV32 DiffTest state size mismatch");

#undef RISCV32_DIFFTEST_STATIC_ASSERT

typedef void (*riscv32_difftest_regcpy_t)(riscv32_difftest_state_t *state,
                                          uint32_t direction);

#ifdef __cplusplus
extern "C" {
#endif

uint32_t difftest_get_abi_version(void);
uint32_t difftest_get_state_size(void);
void difftest_regcpy(riscv32_difftest_state_t *state, uint32_t direction);

#ifdef __cplusplus
}
#endif

#endif
