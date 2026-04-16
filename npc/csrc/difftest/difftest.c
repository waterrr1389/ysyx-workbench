#include "difftest/difftest.h"
#include "Vtop.h"
#include "sim/sim_main.h"

#define DIFFTEST_GPR_NR 32

typedef struct {
  word_t gpr[DIFFTEST_GPR_NR];
  vaddr_t pc;
} DifftestRegs;

static const char* reg_names[DIFFTEST_GPR_NR] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
};

void (*ref_difftest_memcpy)(paddr_t addr, void *buf, size_t n, bool direction) = NULL;
void (*ref_difftest_regcpy)(void *dut, bool direction) = NULL;
void (*ref_difftest_exec)(uint64_t n) = NULL;
void (*ref_difftest_raise_intr)(uint64_t NO) = NULL;

static void reg_copy(void *dut) {
  DifftestRegs *regs = reinterpret_cast<DifftestRegs *>(dut);
  assert(regs != NULL);

  memset(regs, 0, sizeof(*regs));

  if (top == NULL) {
    regs->pc = RESET_VECTOR;
    return;
  }

  for (int reg_idx = 0; reg_idx < DIFFTEST_GPR_NR; reg_idx++) {
    regs->gpr[reg_idx] = read_gpr(reg_idx);
  }
  regs->pc = top->pc;
}

static void dump_regs(const DifftestRegs *ref, const DifftestRegs *dut) {
  for (int i = 0; i < DIFFTEST_GPR_NR; i++) {
    fprintf(stderr, "%-3s ref=" FMT_WORD " dut=" FMT_WORD "%s\n",
        reg_names[i], ref->gpr[i], dut->gpr[i],
        ref->gpr[i] == dut->gpr[i] ? "" : "  <-- mismatch");
  }
}

static void report_mismatch(vaddr_t pc, vaddr_t npc, const DifftestRegs *ref,
                            const DifftestRegs *dut, int mismatch_idx) {
  word_t inst = host_pmem_read(pc, 4);

  fprintf(stderr, "\nDiffTest mismatch at pc = " FMT_WORD ", npc = " FMT_WORD
      ", inst = 0x%08x\n", pc, npc, inst);

  if (mismatch_idx >= 0) {
    fprintf(stderr, "First mismatch: %s, ref = " FMT_WORD ", dut = " FMT_WORD "\n",
        reg_names[mismatch_idx], ref->gpr[mismatch_idx], dut->gpr[mismatch_idx]);
  }

  dump_regs(ref, dut);
  fflush(stderr);
}

static bool checkregs(const DifftestRegs *ref, const DifftestRegs *dut,
                      vaddr_t pc, vaddr_t npc) {
  for (int i = 0; i < DIFFTEST_GPR_NR; i++) {
    if (ref->gpr[i] != dut->gpr[i]) {
      report_mismatch(pc, npc, ref, dut, i);
      npc_state.state = NPC_ABORT;
      npc_state.halt_pc = pc;
      sim = false;
      return false;
    }
  }
  return true;
}

void init_difftest(const char* ref_so_file, long img_size) {
  assert(ref_so_file != NULL);

  void *handle;
  handle = dlopen(ref_so_file, RTLD_LAZY);
  assert(handle);

  ref_difftest_memcpy =
      reinterpret_cast<decltype(ref_difftest_memcpy)>(dlsym(handle, "difftest_memcpy"));
  assert(ref_difftest_memcpy);

  ref_difftest_regcpy =
      reinterpret_cast<decltype(ref_difftest_regcpy)>(dlsym(handle, "difftest_regcpy"));
  assert(ref_difftest_regcpy);

  ref_difftest_exec =
      reinterpret_cast<decltype(ref_difftest_exec)>(dlsym(handle, "difftest_exec"));
  assert(ref_difftest_exec);

  ref_difftest_raise_intr =
      reinterpret_cast<decltype(ref_difftest_raise_intr)>(dlsym(handle, "difftest_raise_intr"));
  assert(ref_difftest_raise_intr);

  void (*ref_difftest_init)(int) =
      reinterpret_cast<void (*)(int)>(dlsym(handle, "difftest_init"));
  assert(ref_difftest_init);

  // Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
  // Log("The result of every instruction will be compared with %s. "
  //     "This will help you a lot for debugging, but also significantly reduce the performance. "
  //     "If it is not necessary, you can turn it off in menuconfig.", ref_so_file);

  ref_difftest_init(0);
  ref_difftest_memcpy(RESET_VECTOR, guest_to_host(RESET_VECTOR), img_size, DIFFTEST_TO_REF);
  DifftestRegs dut_regs = {};
  reg_copy(&dut_regs);
  ref_difftest_regcpy(&dut_regs, DIFFTEST_TO_REF);
}

void difftest_step(vaddr_t pc, vaddr_t npc) {
  if (ref_difftest_exec == NULL || ref_difftest_regcpy == NULL) {
    return;
  }

  DifftestRegs ref_regs = {};
  DifftestRegs dut_regs = {};

  ref_difftest_exec(1);
  ref_difftest_regcpy(&ref_regs, DIFFTEST_TO_DUT);

  reg_copy(&dut_regs);
  dut_regs.pc = npc;

  checkregs(&ref_regs, &dut_regs, pc, npc);
}
