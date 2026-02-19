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
#include <cpu/cpu.h>
#include <isa.h>
#include <memory/vaddr.h>
#include <utils.h>

void device_update();

static inline uint32_t rv32_gpr_read(uint8_t idx) {
  return cpu.gpr[idx];
}

static inline void rv32_gpr_write(uint8_t idx, uint32_t val) {
  if (idx != 0) {
    cpu.gpr[idx] = val;
  }
}

static inline int32_t s32(uint32_t val) {
  return (int32_t)val;
}

uint32_t rv32_jit_exec_tb(const rv32_tb_t *tb, uint64_t budget) {
  uint32_t executed = 0;

  for (uint32_t i = 0; i < tb->n_ir && executed < budget; i++) {
    const rv32_ir_op_t *op = &tb->ir[i];
    uint32_t src1 = rv32_gpr_read(op->rs1);
    uint32_t src2 = rv32_gpr_read(op->rs2);
    vaddr_t next_pc = op->pc + 4;
    bool stop = false;

    switch (op->opcode) {
    case RV32_IR_LUI:
      rv32_gpr_write(op->rd, (uint32_t)op->imm);
      cpu.pc = next_pc;
      break;
    case RV32_IR_AUIPC:
      rv32_gpr_write(op->rd, op->pc + (uint32_t)op->imm);
      cpu.pc = next_pc;
      break;
    case RV32_IR_ADDI:
      rv32_gpr_write(op->rd, src1 + (uint32_t)op->imm);
      cpu.pc = next_pc;
      break;
    case RV32_IR_SLTI:
      rv32_gpr_write(op->rd, (s32(src1) < op->imm) ? 1 : 0);
      cpu.pc = next_pc;
      break;
    case RV32_IR_SLTIU:
      rv32_gpr_write(op->rd, (src1 < (uint32_t)op->imm) ? 1 : 0);
      cpu.pc = next_pc;
      break;
    case RV32_IR_XORI:
      rv32_gpr_write(op->rd, src1 ^ (uint32_t)op->imm);
      cpu.pc = next_pc;
      break;
    case RV32_IR_ORI:
      rv32_gpr_write(op->rd, src1 | (uint32_t)op->imm);
      cpu.pc = next_pc;
      break;
    case RV32_IR_ANDI:
      rv32_gpr_write(op->rd, src1 & (uint32_t)op->imm);
      cpu.pc = next_pc;
      break;
    case RV32_IR_SLLI:
      rv32_gpr_write(op->rd, src1 << ((uint32_t)op->imm & 0x1f));
      cpu.pc = next_pc;
      break;
    case RV32_IR_SRLI:
      rv32_gpr_write(op->rd, src1 >> ((uint32_t)op->imm & 0x1f));
      cpu.pc = next_pc;
      break;
    case RV32_IR_SRAI:
      rv32_gpr_write(op->rd, (uint32_t)(s32(src1) >> ((uint32_t)op->imm & 0x1f)));
      cpu.pc = next_pc;
      break;
    case RV32_IR_ADD:
      rv32_gpr_write(op->rd, src1 + src2);
      cpu.pc = next_pc;
      break;
    case RV32_IR_SUB:
      rv32_gpr_write(op->rd, src1 - src2);
      cpu.pc = next_pc;
      break;
    case RV32_IR_SLL:
      rv32_gpr_write(op->rd, src1 << (src2 & 0x1f));
      cpu.pc = next_pc;
      break;
    case RV32_IR_SLT:
      rv32_gpr_write(op->rd, (s32(src1) < s32(src2)) ? 1 : 0);
      cpu.pc = next_pc;
      break;
    case RV32_IR_SLTU:
      rv32_gpr_write(op->rd, (src1 < src2) ? 1 : 0);
      cpu.pc = next_pc;
      break;
    case RV32_IR_XOR:
      rv32_gpr_write(op->rd, src1 ^ src2);
      cpu.pc = next_pc;
      break;
    case RV32_IR_SRL:
      rv32_gpr_write(op->rd, src1 >> (src2 & 0x1f));
      cpu.pc = next_pc;
      break;
    case RV32_IR_SRA:
      rv32_gpr_write(op->rd, (uint32_t)(s32(src1) >> (src2 & 0x1f)));
      cpu.pc = next_pc;
      break;
    case RV32_IR_OR:
      rv32_gpr_write(op->rd, src1 | src2);
      cpu.pc = next_pc;
      break;
    case RV32_IR_AND:
      rv32_gpr_write(op->rd, src1 & src2);
      cpu.pc = next_pc;
      break;
    case RV32_IR_MUL:
      rv32_gpr_write(op->rd, src1 * src2);
      cpu.pc = next_pc;
      break;
    case RV32_IR_MULH:
      rv32_gpr_write(op->rd,
                     (uint32_t)((((int64_t)(int32_t)src1 * (int64_t)(int32_t)src2) >>
                                 32) &
                                0xffffffffu));
      cpu.pc = next_pc;
      break;
    case RV32_IR_MULHSU:
      rv32_gpr_write(op->rd,
                     (uint32_t)((((int64_t)(int32_t)src1 * (uint64_t)src2) >> 32) &
                                0xffffffffu));
      cpu.pc = next_pc;
      break;
    case RV32_IR_MULHU:
      rv32_gpr_write(op->rd,
                     (uint32_t)((((uint64_t)src1 * (uint64_t)src2) >> 32) &
                                0xffffffffu));
      cpu.pc = next_pc;
      break;
    case RV32_IR_DIV:
      if (src2 == 0) {
        rv32_gpr_write(op->rd, 0xffffffffu);
      } else if (src2 == 0xffffffffu && src1 == 0x80000000u) {
        rv32_gpr_write(op->rd, src1);
      } else {
        rv32_gpr_write(op->rd, (uint32_t)((int32_t)src1 / (int32_t)src2));
      }
      cpu.pc = next_pc;
      break;
    case RV32_IR_DIVU:
      rv32_gpr_write(op->rd, src2 == 0 ? 0xffffffffu : (src1 / src2));
      cpu.pc = next_pc;
      break;
    case RV32_IR_REM:
      if (src2 == 0) {
        rv32_gpr_write(op->rd, src1);
      } else if (src2 == 0xffffffffu && src1 == 0x80000000u) {
        rv32_gpr_write(op->rd, 0);
      } else {
        rv32_gpr_write(op->rd, (uint32_t)((int32_t)src1 % (int32_t)src2));
      }
      cpu.pc = next_pc;
      break;
    case RV32_IR_REMU:
      rv32_gpr_write(op->rd, src2 == 0 ? src1 : (src1 % src2));
      cpu.pc = next_pc;
      break;
    case RV32_IR_LB:
      rv32_gpr_write(op->rd,
                     (uint32_t)(int32_t)(int8_t)(vaddr_read(src1 + op->imm, 1) & 0xff));
      cpu.pc = next_pc;
      break;
    case RV32_IR_LH:
      rv32_gpr_write(op->rd,
                     (uint32_t)(int32_t)(int16_t)(vaddr_read(src1 + op->imm, 2) &
                                                  0xffff));
      cpu.pc = next_pc;
      break;
    case RV32_IR_LW:
      rv32_gpr_write(op->rd, (uint32_t)vaddr_read(src1 + op->imm, 4));
      cpu.pc = next_pc;
      break;
    case RV32_IR_LBU:
      rv32_gpr_write(op->rd, (uint8_t)(vaddr_read(src1 + op->imm, 1) & 0xff));
      cpu.pc = next_pc;
      break;
    case RV32_IR_LHU:
      rv32_gpr_write(op->rd, (uint16_t)(vaddr_read(src1 + op->imm, 2) & 0xffff));
      cpu.pc = next_pc;
      break;
    case RV32_IR_SB:
      vaddr_write(src1 + op->imm, 1, src2);
      cpu.pc = next_pc;
      break;
    case RV32_IR_SH:
      vaddr_write(src1 + op->imm, 2, src2);
      cpu.pc = next_pc;
      break;
    case RV32_IR_SW:
      vaddr_write(src1 + op->imm, 4, src2);
      cpu.pc = next_pc;
      break;
    case RV32_IR_BEQ:
      cpu.pc = (src1 == src2) ? (op->pc + op->imm) : next_pc;
      stop = true;
      break;
    case RV32_IR_BNE:
      cpu.pc = (src1 != src2) ? (op->pc + op->imm) : next_pc;
      stop = true;
      break;
    case RV32_IR_BLT:
      cpu.pc = (s32(src1) < s32(src2)) ? (op->pc + op->imm) : next_pc;
      stop = true;
      break;
    case RV32_IR_BGE:
      cpu.pc = (s32(src1) >= s32(src2)) ? (op->pc + op->imm) : next_pc;
      stop = true;
      break;
    case RV32_IR_BLTU:
      cpu.pc = (src1 < src2) ? (op->pc + op->imm) : next_pc;
      stop = true;
      break;
    case RV32_IR_BGEU:
      cpu.pc = (src1 >= src2) ? (op->pc + op->imm) : next_pc;
      stop = true;
      break;
    case RV32_IR_JAL:
      rv32_gpr_write(op->rd, next_pc);
      cpu.pc = op->pc + op->imm;
      stop = true;
      break;
    case RV32_IR_JALR:
      rv32_gpr_write(op->rd, next_pc);
      cpu.pc = (src1 + op->imm) & ~1u;
      stop = true;
      break;
    case RV32_IR_FENCE:
      cpu.pc = next_pc;
      break;
    case RV32_IR_EBREAK:
      NEMUTRAP(op->pc, rv32_gpr_read(10));
      stop = true;
      break;
    default:
      return executed;
    }

    cpu.gpr[0] = 0;
    executed++;

    IFDEF(CONFIG_DEVICE, device_update());

    if (nemu_state.state != NEMU_RUNNING || stop) {
      break;
    }
  }

  return executed;
}
