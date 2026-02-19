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

#include "jit.h"
#include <isa.h>
#include <utils.h>

rv32_jit_stats_t rv32_jit_stats = {};

uint64_t isa_exec_jit(uint64_t n) {
  uint64_t total = 0;

  while (n > 0) {
    vaddr_t pc = cpu.pc;
    rv32_tb_t *tb = rv32_jit_cache_lookup(pc);

    if (tb == NULL) {
      rv32_jit_stats.tb_miss++;
      tb = rv32_jit_cache_alloc(pc);
      if (!rv32_jit_translate_tb(tb, pc)) {
        rv32_jit_stats.fallback++;
        rv32_jit_stats.unsupported_first++;
        if (total == 0) {
          return 0;
        }
        break;
      }
      rv32_jit_stats.tb_translate++;
    } else {
      rv32_jit_stats.tb_hit++;
    }

    uint32_t ran = rv32_jit_exec_tb(tb, n);
    if (ran == 0) {
      break;
    }

    rv32_jit_stats.jit_guest_inst += ran;
    total += ran;
    n -= ran;

    if (nemu_state.state != NEMU_RUNNING) {
      break;
    }

    if (ran < tb->n_ir) {
      break;
    }
  }

  return total;
}

void jit_print_stats(void) {
#ifdef CONFIG_JIT_STATS
#define NUMBERIC_FMT MUXDEF(CONFIG_TARGET_AM, "%", "%'") PRIu64
  Log("jit: tb_hit = " NUMBERIC_FMT ", tb_miss = " NUMBERIC_FMT,
      rv32_jit_stats.tb_hit, rv32_jit_stats.tb_miss);
  Log("jit: translated = " NUMBERIC_FMT ", invalidated = " NUMBERIC_FMT,
      rv32_jit_stats.tb_translate, rv32_jit_stats.tb_invalidate);
  Log("jit: fallback = " NUMBERIC_FMT ", unsupported-first = " NUMBERIC_FMT,
      rv32_jit_stats.fallback, rv32_jit_stats.unsupported_first);
  Log("jit: guest instructions via jit = " NUMBERIC_FMT,
      rv32_jit_stats.jit_guest_inst);
#endif
}
