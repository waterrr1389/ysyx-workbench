/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <isa.h>
#include <cpu/cpu.h>
#include <difftest-def.h>
#include <memory/paddr.h>

__EXPORT uint32_t difftest_get_abi_version(void) {
  return RISCV32_DIFFTEST_ABI_VERSION;
}

__EXPORT uint32_t difftest_get_state_size(void) {
  return sizeof(riscv32_difftest_state_t);
}

__EXPORT void difftest_memcpy(paddr_t addr, void *buf, size_t n, bool direction) {
  if (direction == DIFFTEST_TO_REF) {
    memcpy(guest_to_host(addr), buf, n);
  } else if (direction == DIFFTEST_TO_DUT) {
    assert(0);
  }
}

__EXPORT void difftest_regcpy(riscv32_difftest_state_t *dut,
                              uint32_t direction) {
  assert(dut != NULL);

  if (direction == DIFFTEST_TO_REF) {
    isa_difftest_import_state(&cpu, dut);
  } else if (direction == DIFFTEST_TO_DUT) {
    isa_difftest_export_state(dut, &cpu);
  } else {
    panic("Invalid DiffTest direction %u", direction);
  }
}

__EXPORT void difftest_exec(uint64_t n) {
  cpu_exec(n);
}

// We don't need to implement this right now
__EXPORT void difftest_raise_intr(word_t NO) {
  assert(0);
}

__EXPORT void difftest_init(int port) {
  void init_mem();
  init_mem();
  /* Perform ISA dependent initialization. */
  init_isa();
}
