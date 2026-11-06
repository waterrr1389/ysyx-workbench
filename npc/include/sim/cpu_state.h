#pragma once

#include <difftest/arch/riscv32.h>

struct CpuReport {
  riscv32_difftest_state_t state;
  uint32_t commit_pc;
  bool initial;
};

void cpu_state_init();
bool cpu_report_take(CpuReport *report);
void cpu_state_accept(const CpuReport &report);
const riscv32_difftest_state_t &cpu_state();
