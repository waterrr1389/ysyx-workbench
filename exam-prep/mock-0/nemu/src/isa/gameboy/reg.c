/***************************************************************************************
 * Copyright (c) 2014-2024 Zihao Yu, Nanjing University
 *
 * NEMU is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan
 *PSL v2. You may obtain a copy of Mulan PSL v2 at:
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY
 *KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
 *NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 *
 * See the Mulan PSL v2 for more details.
 ***************************************************************************************/

//#include "local-include/reg.h"
#include <isa.h>

#define REG_AF 0
#define REG_BC 1
#define REG_DE 2
#define REG_HL 3
#define REG_SP 4

const char* regsb[] = { "A", "B", "C", "D", "E"};
const char* regsw[] = { "AF", "BC", "DE", "HL", "SP"};

void isa_reg_display() {
  for (int i = 0; i < 5; i++) {
    printf("%s:" FMT_WORD "\n", regsw[i], cpu.gpr[i]._16);
  }
  printf("pc:" FMT_WORD "\n", cpu.pc);
}

word_t isa_reg_str2val(const char* s, bool* success) {
  *success = true;

  const char* name = s + 1; // 去掉 '$' 符号

  // 1. 16位寄存器匹配 (直接读取 _16)
  for (int i = 0; i < 5; i++) {
    if (strcmp(name, regsw[i]) == 0) {
      return cpu.gpr[i]._16;
    }
  }

  // 2.PC
  if (strcmp(name, "pc") == 0) {
    return cpu.pc;
  }

  // 3. 8位寄存器匹配(小端序：High=_8[1], Low=_8[0])
  if (strcmp(name, "a") == 0) return cpu.gpr[REG_AF]._8[1]; // High
  if (strcmp(name, "f") == 0) return cpu.gpr[REG_AF]._8[0]; // Low
  
  if (strcmp(name, "b") == 0) return cpu.gpr[REG_BC]._8[1]; // High
  if (strcmp(name, "c") == 0) return cpu.gpr[REG_BC]._8[0]; // Low
  
  if (strcmp(name, "d") == 0) return cpu.gpr[REG_DE]._8[1]; // High
  if (strcmp(name, "e") == 0) return cpu.gpr[REG_DE]._8[0]; // Low
  
  if (strcmp(name, "h") == 0) return cpu.gpr[REG_HL]._8[1]; // High
  if (strcmp(name, "l") == 0) return cpu.gpr[REG_HL]._8[0]; // Low

  *success = false;
  return 0;
}