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

static inline int32_t sext32(uint32_t val, int bits) {
  return ((int32_t)(val << (32 - bits))) >> (32 - bits);
}

static inline uint32_t bits(uint32_t val, int hi, int lo) {
  uint32_t mask = (1u << (hi - lo + 1)) - 1;
  return (val >> lo) & mask;
}

bool rv32_jit_decode_op(uint32_t inst, vaddr_t pc, rv32_ir_op_t *op,
                        bool *is_control) {
  uint32_t opcode = bits(inst, 6, 0);
  uint32_t funct3 = bits(inst, 14, 12);
  uint32_t funct7 = bits(inst, 31, 25);

  op->pc = pc;
  op->rd = bits(inst, 11, 7);
  op->rs1 = bits(inst, 19, 15);
  op->rs2 = bits(inst, 24, 20);
  op->imm = 0;
  *is_control = false;

  switch (opcode) {
  case 0x37:
    op->opcode = RV32_IR_LUI;
    op->imm = (int32_t)(inst & 0xfffff000u);
    return true;
  case 0x17:
    op->opcode = RV32_IR_AUIPC;
    op->imm = (int32_t)(inst & 0xfffff000u);
    return true;
  case 0x13:
    op->imm = sext32(bits(inst, 31, 20), 12);
    switch (funct3) {
    case 0x0:
      op->opcode = RV32_IR_ADDI;
      return true;
    case 0x2:
      op->opcode = RV32_IR_SLTI;
      return true;
    case 0x3:
      op->opcode = RV32_IR_SLTIU;
      return true;
    case 0x4:
      op->opcode = RV32_IR_XORI;
      return true;
    case 0x6:
      op->opcode = RV32_IR_ORI;
      return true;
    case 0x7:
      op->opcode = RV32_IR_ANDI;
      return true;
    case 0x1:
      if (funct7 != 0x00) {
        return false;
      }
      op->opcode = RV32_IR_SLLI;
      return true;
    case 0x5:
      if (funct7 == 0x00) {
        op->opcode = RV32_IR_SRLI;
        return true;
      }
      if (funct7 == 0x20) {
        op->opcode = RV32_IR_SRAI;
        return true;
      }
      return false;
    default:
      return false;
    }
  case 0x33:
    switch (funct7) {
    case 0x00:
      switch (funct3) {
      case 0x0:
        op->opcode = RV32_IR_ADD;
        return true;
      case 0x1:
        op->opcode = RV32_IR_SLL;
        return true;
      case 0x2:
        op->opcode = RV32_IR_SLT;
        return true;
      case 0x3:
        op->opcode = RV32_IR_SLTU;
        return true;
      case 0x4:
        op->opcode = RV32_IR_XOR;
        return true;
      case 0x5:
        op->opcode = RV32_IR_SRL;
        return true;
      case 0x6:
        op->opcode = RV32_IR_OR;
        return true;
      case 0x7:
        op->opcode = RV32_IR_AND;
        return true;
      default:
        return false;
      }
    case 0x20:
      if (funct3 == 0x0) {
        op->opcode = RV32_IR_SUB;
        return true;
      }
      if (funct3 == 0x5) {
        op->opcode = RV32_IR_SRA;
        return true;
      }
      return false;
    case 0x01:
      switch (funct3) {
      case 0x0:
        op->opcode = RV32_IR_MUL;
        return true;
      case 0x1:
        op->opcode = RV32_IR_MULH;
        return true;
      case 0x2:
        op->opcode = RV32_IR_MULHSU;
        return true;
      case 0x3:
        op->opcode = RV32_IR_MULHU;
        return true;
      case 0x4:
        op->opcode = RV32_IR_DIV;
        return true;
      case 0x5:
        op->opcode = RV32_IR_DIVU;
        return true;
      case 0x6:
        op->opcode = RV32_IR_REM;
        return true;
      case 0x7:
        op->opcode = RV32_IR_REMU;
        return true;
      default:
        return false;
      }
    default:
      return false;
    }
  case 0x03:
    op->imm = sext32(bits(inst, 31, 20), 12);
    switch (funct3) {
    case 0x0:
      op->opcode = RV32_IR_LB;
      return true;
    case 0x1:
      op->opcode = RV32_IR_LH;
      return true;
    case 0x2:
      op->opcode = RV32_IR_LW;
      return true;
    case 0x4:
      op->opcode = RV32_IR_LBU;
      return true;
    case 0x5:
      op->opcode = RV32_IR_LHU;
      return true;
    default:
      return false;
    }
  case 0x23:
    op->imm = sext32((bits(inst, 31, 25) << 5) | bits(inst, 11, 7), 12);
    switch (funct3) {
    case 0x0:
      op->opcode = RV32_IR_SB;
      return true;
    case 0x1:
      op->opcode = RV32_IR_SH;
      return true;
    case 0x2:
      op->opcode = RV32_IR_SW;
      return true;
    default:
      return false;
    }
  case 0x63:
    op->imm = sext32((bits(inst, 31, 31) << 12) | (bits(inst, 7, 7) << 11) |
                         (bits(inst, 30, 25) << 5) | (bits(inst, 11, 8) << 1),
                     13);
    *is_control = true;
    switch (funct3) {
    case 0x0:
      op->opcode = RV32_IR_BEQ;
      return true;
    case 0x1:
      op->opcode = RV32_IR_BNE;
      return true;
    case 0x4:
      op->opcode = RV32_IR_BLT;
      return true;
    case 0x5:
      op->opcode = RV32_IR_BGE;
      return true;
    case 0x6:
      op->opcode = RV32_IR_BLTU;
      return true;
    case 0x7:
      op->opcode = RV32_IR_BGEU;
      return true;
    default:
      return false;
    }
  case 0x6f:
    op->imm = sext32((bits(inst, 31, 31) << 20) | (bits(inst, 19, 12) << 12) |
                         (bits(inst, 20, 20) << 11) | (bits(inst, 30, 21) << 1),
                     21);
    op->opcode = RV32_IR_JAL;
    *is_control = true;
    return true;
  case 0x67:
    if (funct3 != 0x0) {
      return false;
    }
    op->imm = sext32(bits(inst, 31, 20), 12);
    op->opcode = RV32_IR_JALR;
    *is_control = true;
    return true;
  case 0x0f:
    op->opcode = RV32_IR_FENCE;
    return true;
  case 0x73:
    if (inst == 0x00100073u) {
      op->opcode = RV32_IR_EBREAK;
      *is_control = true;
      return true;
    }
    return false;
  default:
    return false;
  }
}
