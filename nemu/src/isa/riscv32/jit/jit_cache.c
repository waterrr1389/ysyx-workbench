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
#include <memory/vaddr.h>
#include <string.h>

extern rv32_jit_stats_t rv32_jit_stats;

static rv32_tb_t tb_cache[RV32_JIT_CACHE_SIZE];

static inline uint32_t tb_index(vaddr_t pc) {
  return (pc >> 2) & (RV32_JIT_CACHE_SIZE - 1);
}

rv32_tb_t *rv32_jit_cache_lookup(vaddr_t pc) {
  rv32_tb_t *tb = &tb_cache[tb_index(pc)];
  if (!(tb->valid && tb->pc_start == pc)) {
    return NULL;
  }

  for (uint32_t i = 0; i < tb->n_insn; i++) {
    uint32_t cur = vaddr_ifetch(pc + i * 4, 4);
    if (cur != tb->insts[i]) {
      tb->valid = false;
      rv32_jit_stats.tb_invalidate++;
      return NULL;
    }
  }

  return tb;
}

rv32_tb_t *rv32_jit_cache_alloc(vaddr_t pc) {
  rv32_tb_t *tb = &tb_cache[tb_index(pc)];
  memset(tb, 0, sizeof(*tb));
  tb->pc_start = pc;
  return tb;
}
