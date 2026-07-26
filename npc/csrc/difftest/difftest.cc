#include "difftest/difftest.h"
#include "Vtop.h"
#include "sim/sim_main.h"

#include <difftest/reference.hpp>

#include <memory>

static const char *reg_names[RISCV32_DIFFTEST_GPR_COUNT] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
};

static std::unique_ptr<difftest::Riscv32DifftestReference> reference;

static riscv32_difftest_state_t export_dut_state() {
  riscv32_difftest_state_t state = {};
  state.priv = 3;
  state.mstatus = 0x1800;

  if (top == NULL) {
    state.pc = RESET_VECTOR;
    return state;
  }

  for (size_t reg_idx = 0; reg_idx < RISCV32_DIFFTEST_GPR_COUNT; reg_idx++) {
    state.gpr[reg_idx] = read_gpr(reg_idx);
  }
  state.pc = top->pc;
  return state;
}

static void dump_regs(const riscv32_difftest_state_t *ref,
                      const riscv32_difftest_state_t *dut) {
  for (size_t i = 0; i < RISCV32_DIFFTEST_GPR_COUNT; i++) {
    fprintf(stderr, "%-3s ref=" FMT_WORD " dut=" FMT_WORD "%s\n",
            reg_names[i], ref->gpr[i], dut->gpr[i],
            ref->gpr[i] == dut->gpr[i] ? "" : "  <-- mismatch");
  }
}

static void report_mismatch(vaddr_t pc, vaddr_t npc, const riscv32_difftest_state_t *ref,
                            const riscv32_difftest_state_t *dut, int mismatch_idx) {
  word_t inst = host_pmem_read(pc, 4);

  fprintf(stderr, "\nDiffTest mismatch at pc = " FMT_WORD ", npc = " FMT_WORD
                  ", inst = 0x%08x\n",
          pc, npc, inst);

  if (ref->pc != dut->pc) {
    fprintf(stderr, "PC mismatch: ref.pc = " FMT_WORD ", dut.pc = " FMT_WORD "\n",
            ref->pc, dut->pc);
  }

  if (mismatch_idx >= 0) {
    fprintf(stderr, "First mismatch: %s, ref = " FMT_WORD ", dut = " FMT_WORD "\n",
            reg_names[mismatch_idx], ref->gpr[mismatch_idx], dut->gpr[mismatch_idx]);
  }

  dump_regs(ref, dut);
  fflush(stderr);
}

static bool checkregs(const riscv32_difftest_state_t *ref,
                      const riscv32_difftest_state_t *dut, vaddr_t pc, vaddr_t npc) {
  if (ref->pc != dut->pc) {
    report_mismatch(pc, npc, ref, dut, -1);
    npc_state.state = NPC_ABORT;
    npc_state.halt_pc = pc;
    sim = false;
    return false;
  }

  for (size_t i = 0; i < RISCV32_DIFFTEST_GPR_COUNT; i++) {
    if (ref->gpr[i] != dut->gpr[i]) {
      report_mismatch(pc, npc, ref, dut, static_cast<int>(i));
      npc_state.state = NPC_ABORT;
      npc_state.halt_pc = pc;
      sim = false;
      return false;
    }
  }
  return true;
}

void init_difftest(const char *ref_so_file, long img_size) {
  assert(ref_so_file != NULL);

  reference.reset(new difftest::Riscv32DifftestReference(ref_so_file));
  riscv32_difftest_state_t initial_state = export_dut_state();
  reference->initialize(0, RESET_VECTOR, guest_to_host(RESET_VECTOR), img_size, initial_state);
}

void difftest_step(vaddr_t pc, vaddr_t npc) {
  if (reference == nullptr) {
    return;
  }

  riscv32_difftest_state_t ref_state = reference->step();
  riscv32_difftest_state_t dut_state = export_dut_state();
  dut_state.pc = npc;

  checkregs(&ref_state, &dut_state, pc, npc);
}
