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

bool rv32_jit_translate_tb(rv32_tb_t *tb, vaddr_t pc) {
  memset(tb, 0, sizeof(*tb));
  tb->pc_start = pc;

  for (uint32_t i = 0; i < RV32_JIT_TB_MAX_INSNS; i++) {
    rv32_ir_op_t op = {};
    bool is_control = false;
    uint32_t inst = vaddr_ifetch(pc, 4);

    if (!rv32_jit_decode_op(inst, pc, &op, &is_control)) {
      if (tb->n_insn == 0) {
        return false;
      }
      break;
    }

    tb->insts[tb->n_insn] = inst;
    tb->ir[tb->n_ir] = op;
    tb->n_insn++;
    tb->n_ir++;

    pc += 4;
    if (is_control) {
      break;
    }
  }

  if (tb->n_insn == 0) {
    return false;
  }

  tb->pc_fallthrough = pc;
  tb->valid = true;
  return true;
}
