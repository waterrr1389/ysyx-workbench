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
  state.mstatus = top->mstatus;
  state.mtvec = top->mtvec;
  state.mepc = top->mepc;
  state.mcause = top->mcause;
  return state;
}

// Every field compared, in report order. CSRs are included because the DUT
// exports its real values.
struct Field {
  const char *name;
  uint32_t riscv32_difftest_state_t::*member;
};
static const Field csr_fields[] = {
  {"pc", &riscv32_difftest_state_t::pc},
  {"mstatus", &riscv32_difftest_state_t::mstatus},
  {"mtvec", &riscv32_difftest_state_t::mtvec},
  {"mepc", &riscv32_difftest_state_t::mepc},
  {"mcause", &riscv32_difftest_state_t::mcause},
};

static void report_mismatch(vaddr_t pc, const riscv32_difftest_state_t *ref,
                            const riscv32_difftest_state_t *dut) {
  fprintf(stderr, "\nDiffTest mismatch after pc = " FMT_WORD ", inst = 0x%08x\n",
          pc, host_pmem_read(pc, 4));
  for (const Field &f : csr_fields) {
    uint32_t r = ref->*f.member, d = dut->*f.member;
    fprintf(stderr, "%-7s ref=" FMT_WORD " dut=" FMT_WORD "%s\n", f.name, r, d,
            r == d ? "" : "  <-- mismatch");
  }
  for (size_t i = 0; i < RISCV32_DIFFTEST_GPR_COUNT; i++) {
    fprintf(stderr, "%-7s ref=" FMT_WORD " dut=" FMT_WORD "%s\n", reg_names[i], ref->gpr[i],
            dut->gpr[i], ref->gpr[i] == dut->gpr[i] ? "" : "  <-- mismatch");
  }
  fflush(stderr);
}

static bool same_state(const riscv32_difftest_state_t *ref, const riscv32_difftest_state_t *dut) {
  for (const Field &f : csr_fields) {
    if (ref->*f.member != dut->*f.member) return false;
  }
  for (size_t i = 0; i < RISCV32_DIFFTEST_GPR_COUNT; i++) {
    if (ref->gpr[i] != dut->gpr[i]) return false;
  }
  return true;
}

// Set by device accesses and stores during the instruction about to commit.
// The core has one instruction in flight, so whatever touched the bus since the
// last commit belongs to the next one.
static bool skip_pending = false;
static bool store_pending = false;
static word_t store_addr = 0;

void difftest_skip_ref(void) { skip_pending = true; }

void difftest_note_store(word_t addr) {
  store_pending = true;
  store_addr = addr & ~0x3u;
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

  riscv32_difftest_state_t dut_state = export_dut_state();
  dut_state.pc = npc;

  // REF cannot reproduce a device access; take the DUT's result instead.
  if (skip_pending) {
    skip_pending = false;
    store_pending = false;
    reference->set_state(dut_state);
    return;
  }

  riscv32_difftest_state_t ref_state = reference->step();
  if (!same_state(&ref_state, &dut_state)) {
    report_mismatch(pc, &ref_state, &dut_state);
    npc_abort("difftest", pc);
    return;
  }

  // A wrong store shows up in registers only when it is loaded back, so the
  // stored word is compared right away.
  if (store_pending) {
    store_pending = false;
    word_t ref_word = 0;
    reference->copy_memory_from_reference(store_addr, &ref_word, sizeof(ref_word));
    word_t dut_word = host_pmem_read(store_addr, 4);
    if (ref_word != dut_word) {
      fprintf(stderr, "\nDiffTest store mismatch after pc = " FMT_WORD ": mem[" FMT_WORD
                      "] ref=" FMT_WORD " dut=" FMT_WORD "\n",
              pc, store_addr, ref_word, dut_word);
      npc_abort("difftest-store", pc);
    }
  }
}
