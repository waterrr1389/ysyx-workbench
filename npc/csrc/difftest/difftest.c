#include "difftest/difftest.h"
#include "Vtop.h"
#include "sim/sim_main.h"

#define DIFFTEST_GPR_NR 32

typedef struct {
  word_t gpr[DIFFTEST_GPR_NR];
  vaddr_t pc;
} DifftestRegs;

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

void init_difftest(const char* ref_so_file, long img_size) {
  assert(ref_so_file != NULL);

  void *handle;
  dlerror();
  handle = dlopen(ref_so_file, RTLD_LAZY);
  if (handle == NULL) {
    fprintf(stderr, "Warning: failed to load difftest ref '%s': %s\n",
        ref_so_file, dlerror());
    return;
  }

  ref_difftest_memcpy =
      reinterpret_cast<decltype(ref_difftest_memcpy)>(dlsym(handle, "difftest_memcpy"));
  if (ref_difftest_memcpy == NULL) return;

  ref_difftest_regcpy =
      reinterpret_cast<decltype(ref_difftest_regcpy)>(dlsym(handle, "difftest_regcpy"));
  if (ref_difftest_regcpy == NULL) return;

  ref_difftest_exec =
      reinterpret_cast<decltype(ref_difftest_exec)>(dlsym(handle, "difftest_exec"));
  if (ref_difftest_exec == NULL) return;

  ref_difftest_raise_intr =
      reinterpret_cast<decltype(ref_difftest_raise_intr)>(dlsym(handle, "difftest_raise_intr"));
  if (ref_difftest_raise_intr == NULL) return;

  void (*ref_difftest_init)(int) =
      reinterpret_cast<void (*)(int)>(dlsym(handle, "difftest_init"));
  if (ref_difftest_init == NULL) return;

  // Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
  // Log("The result of every instruction will be compared with %s. "
  //     "This will help you a lot for debugging, but also significantly reduce the performance. "
  //     "If it is not necessary, you can turn it off in menuconfig.", ref_so_file);

  ref_difftest_memcpy(RESET_VECTOR, guest_to_host(RESET_VECTOR), img_size, DIFFTEST_TO_REF);
  DifftestRegs dut_regs = {};
  reg_copy(&dut_regs);
  ref_difftest_regcpy(&dut_regs, DIFFTEST_TO_REF);
}
