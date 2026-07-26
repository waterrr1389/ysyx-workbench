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
#include <cpu/difftest.h>
#include "../local-include/reg.h"

bool isa_difftest_checkregs(CPU_state *ref_cpu, vaddr_t pc) {
  const word_t *ref_gpr = ref_cpu->gpr;
  const word_t *dut_gpr = cpu.gpr;

  for (int reg_idx = 0; reg_idx < ARRLEN(cpu.gpr); reg_idx++) {
    if (!difftest_check_reg(reg_name(reg_idx), pc, ref_gpr[reg_idx],
                            dut_gpr[reg_idx])) {
      return false;
    }
  }

  return difftest_check_reg("pc", pc, ref_cpu->pc, cpu.pc) &&
         difftest_check_reg("priv", pc, ref_cpu->priv, cpu.priv) &&
         difftest_check_reg("mtvec", pc, ref_cpu->mtvec, cpu.mtvec) &&
         difftest_check_reg("mepc", pc, ref_cpu->mepc, cpu.mepc) &&
         difftest_check_reg("mcause", pc, ref_cpu->mcause, cpu.mcause);
}

void isa_difftest_attach() {
}
