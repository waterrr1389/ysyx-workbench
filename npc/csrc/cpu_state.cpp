#include "sim/cpu_state.h"
#include "sim/sim_main.h"
#include <assert.h>

// DPI callbacks only fill pending data; consumers see it after eval completes.
static riscv32_difftest_state_t accepted;
static CpuReport pending;
static bool available, pc_received, initialized;
static unsigned gpr_count;
static uint32_t gpr_received;

void cpu_state_init() {
  accepted = {};
  pending = {};
  available = pc_received = initialized = false;
  gpr_received = 0;
}

extern "C" void npc_report_commit(unsigned char initial, int pc, int count,
                                  int priv, int mstatus, int mtvec, int mepc, int mcause) {
  assert(!available);
  assert(count == 16 || count == 32);
  pending = {};
  pending.initial = initial;
  pending.commit_pc = pc;
  pending.state.priv = priv;
  pending.state.mstatus = mstatus;
  pending.state.mtvec = mtvec;
  pending.state.mepc = mepc;
  pending.state.mcause = mcause;
  gpr_count = count;
  gpr_received = 0;
  pc_received = false;
  available = true;
}

extern "C" void npc_report_gpr(int index, int value) {
  assert(available && index >= 0 && unsigned(index) < gpr_count);
  uint32_t bit = uint32_t{1} << index;
  assert(!(gpr_received & bit));
  pending.state.gpr[index] = value;
  gpr_received |= bit;
}

extern "C" void npc_report_pc(int pc) {
  assert(available && !pc_received);
  pending.state.pc = pc;
  pc_received = true;
}

bool cpu_report_take(CpuReport *report) {
  if (!available) return false;
  assert(pc_received && gpr_received == (UINT32_MAX >> (32 - gpr_count)));
  assert(pending.state.gpr[0] == 0);
  assert(pending.initial || (initialized && pending.commit_pc == accepted.pc));
  *report = pending;
  available = false;
  return true;
}

void cpu_state_accept(const CpuReport &report) {
  accepted = report.state;
  initialized = true;
}

const riscv32_difftest_state_t &cpu_state() {
  assert(initialized);
  return accepted;
}

uint32_t read_gpr(uint32_t index) {
  return index < RISCV32_DIFFTEST_GPR_COUNT ? cpu_state().gpr[index] : 0;
}
