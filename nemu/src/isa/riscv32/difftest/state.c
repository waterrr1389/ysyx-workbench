#include <isa.h>

static bool valid_privilege(uint32_t priv) {
  return priv == RISCV_PRIV_U || priv == RISCV_PRIV_S || priv == RISCV_PRIV_M;
}

void isa_difftest_export_state(riscv32_difftest_state_t *wire,
                               const CPU_state *state) {
  assert(wire != NULL);
  assert(state != NULL);

  for (size_t i = 0; i < RISCV32_DIFFTEST_GPR_COUNT; i++) {
    wire->gpr[i] = state->gpr[i];
  }
  wire->gpr[0] = 0;
  wire->pc = state->pc;
  wire->priv = state->priv;
  wire->mstatus = state->mstatus;
  wire->mtvec = state->mtvec;
  wire->mepc = state->mepc;
  wire->mcause = state->mcause;
}

void isa_difftest_import_state(CPU_state *state,
                               const riscv32_difftest_state_t *wire) {
  assert(state != NULL);
  assert(wire != NULL);
  Assert(valid_privilege(wire->priv), "Invalid RV32 privilege encoding %u",
         wire->priv);

  state->gpr[0] = 0;
  for (size_t i = 1; i < RISCV32_DIFFTEST_GPR_COUNT; i++) {
    state->gpr[i] = wire->gpr[i];
  }
  state->pc = wire->pc;
  state->priv = wire->priv;
  state->mstatus = wire->mstatus;
  state->mtvec = wire->mtvec;
  state->mepc = wire->mepc;
  state->mcause = wire->mcause;
}
