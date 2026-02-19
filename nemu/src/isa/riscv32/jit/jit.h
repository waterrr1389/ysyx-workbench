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

#ifndef __RISCV32_JIT_H__
#define __RISCV32_JIT_H__

#include <common.h>

#define RV32_JIT_TB_MAX_INSNS 32
#define RV32_JIT_TB_MAX_IR RV32_JIT_TB_MAX_INSNS
#define RV32_JIT_CACHE_SIZE 1024

typedef enum {
  RV32_IR_LUI,
  RV32_IR_AUIPC,
  RV32_IR_ADDI,
  RV32_IR_SLTI,
  RV32_IR_SLTIU,
  RV32_IR_XORI,
  RV32_IR_ORI,
  RV32_IR_ANDI,
  RV32_IR_SLLI,
  RV32_IR_SRLI,
  RV32_IR_SRAI,
  RV32_IR_ADD,
  RV32_IR_SUB,
  RV32_IR_SLL,
  RV32_IR_SLT,
  RV32_IR_SLTU,
  RV32_IR_XOR,
  RV32_IR_SRL,
  RV32_IR_SRA,
  RV32_IR_OR,
  RV32_IR_AND,
  RV32_IR_MUL,
  RV32_IR_MULH,
  RV32_IR_MULHSU,
  RV32_IR_MULHU,
  RV32_IR_DIV,
  RV32_IR_DIVU,
  RV32_IR_REM,
  RV32_IR_REMU,
  RV32_IR_LB,
  RV32_IR_LH,
  RV32_IR_LW,
  RV32_IR_LBU,
  RV32_IR_LHU,
  RV32_IR_SB,
  RV32_IR_SH,
  RV32_IR_SW,
  RV32_IR_BEQ,
  RV32_IR_BNE,
  RV32_IR_BLT,
  RV32_IR_BGE,
  RV32_IR_BLTU,
  RV32_IR_BGEU,
  RV32_IR_JAL,
  RV32_IR_JALR,
  RV32_IR_FENCE,
  RV32_IR_EBREAK,
} rv32_ir_opcode_t;

typedef struct {
  rv32_ir_opcode_t opcode;
  vaddr_t pc;
  uint8_t rd;
  uint8_t rs1;
  uint8_t rs2;
  int32_t imm;
} rv32_ir_op_t;

typedef struct {
  bool valid;
  vaddr_t pc_start;
  vaddr_t pc_fallthrough;
  uint32_t n_insn;
  uint32_t n_ir;
  uint32_t insts[RV32_JIT_TB_MAX_INSNS];
  rv32_ir_op_t ir[RV32_JIT_TB_MAX_IR];
} rv32_tb_t;

typedef struct {
  uint64_t tb_hit;
  uint64_t tb_miss;
  uint64_t tb_translate;
  uint64_t tb_invalidate;
  uint64_t fallback;
  uint64_t unsupported_first;
  uint64_t jit_guest_inst;
} rv32_jit_stats_t;

extern rv32_jit_stats_t rv32_jit_stats;

rv32_tb_t *rv32_jit_cache_lookup(vaddr_t pc);
rv32_tb_t *rv32_jit_cache_alloc(vaddr_t pc);

bool rv32_jit_decode_op(uint32_t inst, vaddr_t pc, rv32_ir_op_t *op,
                        bool *is_control);
bool rv32_jit_translate_tb(rv32_tb_t *tb, vaddr_t pc);
uint32_t rv32_jit_exec_tb(const rv32_tb_t *tb, uint64_t budget);

#endif
