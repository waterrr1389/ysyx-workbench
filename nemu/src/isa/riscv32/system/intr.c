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

word_t isa_raise_intr(word_t cause, vaddr_t epc) {
  cpu.mcause = cause;
  cpu.mepc = epc;
  IFDEF(CONFIG_ETRACE,
      Log("etrace: cause=" FMT_WORD " epc=" FMT_WORD " mtvec=" FMT_WORD,
          cause, epc, cpu.mtvec));

  return cpu.mtvec;
}

word_t isa_query_intr() {
  return INTR_EMPTY;
}
