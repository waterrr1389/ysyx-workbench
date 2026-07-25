/***************************************************************************************
 * Copyright (c) 2014-2024 Zihao Yu, Nanjing University
 *
 * NEMU is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan
 * PSL v2. You may obtain a copy of Mulan PSL v2 at:
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY
 * KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
 * NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 *
 * See the Mulan PSL v2 for more details.
 ***************************************************************************************/

extern "C" {
#include "../../monitor/sdb/ftrace.h"
#include "isa.h"
#include "local-include/reg.h"
#include <cpu/cpu.h>
#include <cpu/decode.h>
#include <cpu/ifetch.h>
}
#include "capstone/arm.h"
#include <stdint.h>

#define R(i) gpr(i)
#define Mr vaddr_read
#define Mw vaddr_write

static inline word_t imm_i(uint32_t i) { return SEXT(BITS(i, 31, 20), 12); }
static inline word_t imm_u(uint32_t i) {
  return SEXT(BITS(i, 31, 12), 20) << 12;
}
static inline word_t imm_s(uint32_t i) {
  return (SEXT(BITS(i, 31, 25), 7) << 5) | BITS(i, 11, 7);
}
static inline word_t imm_b(uint32_t i) {
  return (SEXT(BITS(i, 31, 31), 1) << 12) | (BITS(i, 30, 25) << 5) |
         (BITS(i, 11, 8) << 1) | (BITS(i, 7, 7) << 11);
}
static inline word_t imm_j(uint32_t i) {
  return (SEXT(BITS(i, 31, 31), 1) << 20) | (BITS(i, 19, 12) << 12) |
         (BITS(i, 20, 20) << 11) | (BITS(i, 30, 21) << 1);
}

#define get_rs1(i)                                                             \
  do {                                                                         \
    rs1 = BITS(i, 19, 15);                                                     \
  } while (0)

#ifdef CONFIG_FTRACE
#define JALR_CASE(pc, dst)                                                     \
  do {                                                                         \
    word_t rs1;                                                                \
    get_rs1(s->isa.inst);                                                      \
    if (rd == 1) { /* call */                                                  \
      call_record(pc, dst);                                                    \
    } else if (rd == 0 && rs1 == 1) { /* ret */                                \
      ret_record(pc);                                                          \
    } else { /* Log("ftrace: invalid..."); */                                  \
    }                                                                          \
  } while (0)
#define JAL_CASE(pc, dst)                                                      \
  do {                                                                         \
    if (rd == 1) {                                                             \
      /* call */                                                               \
      call_record(pc, dst);                                                    \
    } else {                                                                   \
      /* Log("ftrace: invalid..."); */                                         \
    }                                                                          \
  } while (0)
#else
#define JALR_CASE(pc, dst) ((void)0)
#define JAL_CASE(pc, dst) ((void)0)
#endif

static word_t csr_read(word_t addr) {
  switch (addr) {
    case 0x300: return cpu.mstatus;
    case 0x305: return cpu.mtvec;
    case 0x341: return cpu.mepc;
    case 0x342: return cpu.mcause;
    default: panic("csr_read: unsupported csr 0x%x", addr); return 0;
  }
}

static void csr_write(word_t addr, word_t val) {
  switch (addr) {
    case 0x300: cpu.mstatus = val; return;
    case 0x305: cpu.mtvec = val; return;
    case 0x341: cpu.mepc = val; return;
    case 0x342: cpu.mcause = val; return;
    default: panic("csr_write: unsupported csr 0x%x", addr);
  }
}

static word_t ecall_cause(void) {
  switch (cpu.priv) {
    case RISCV_PRIV_U: return 8;
    case RISCV_PRIV_S: return 9;
    case RISCV_PRIV_M: return 11;
    default:
      panic("Invalid RISC-V privilege mode %u", (unsigned)cpu.priv);
      return 0;
  }
}

static int decode_exec(Decode *s) {
  s->dnpc = s->snpc;

  uint32_t i = s->isa.inst;
  uint32_t opcode = BITS(i, 6, 0);
  uint32_t funct3 = BITS(i, 14, 12);
  uint32_t funct7 = BITS(i, 31, 25);
  int rd = BITS(i, 11, 7);
  int rs1 = BITS(i, 19, 15);
  int rs2 = BITS(i, 24, 20);
  word_t src1 = R(rs1);
  word_t src2 = R(rs2);
  word_t imm;

  switch (opcode) {
  case 0x37: // lui
    R(rd) = imm_u(i);
    break;
  case 0x17: // auipc
    R(rd) = s->pc + imm_u(i);
    break;

  case 0x6f: // jal
    imm = imm_j(i);
    s->dnpc = s->pc + imm;
    R(rd) = s->snpc;
    JAL_CASE(s->pc, s->dnpc);
    break;
  case 0x67: // jalr
    if (funct3 != 0) {
      INV(s->pc);
      break;
    }
    imm = imm_i(i);
    R(rd) = s->snpc;
    s->dnpc = (src1 + imm) & ~1UL;
    JALR_CASE(s->pc, s->dnpc);
    break;

  case 0x63: // branch
    imm = imm_b(i);
    switch (funct3) {
    case 0: if (src1 == src2) s->dnpc = s->pc + imm; break; // beq
    case 1: if (src1 != src2) s->dnpc = s->pc + imm; break; // bne
    case 4: if ((int)src1 < (int)src2) s->dnpc = s->pc + imm; break; // blt
    case 5: if ((int)src1 >= (int)src2) s->dnpc = s->pc + imm; break; // bge
    case 6: if (src1 < src2) s->dnpc = s->pc + imm; break; // bltu
    case 7: if (src1 >= src2) s->dnpc = s->pc + imm; break; // bgeu
    default: INV(s->pc);
    }
    break;

  case 0x03: // load
    imm = imm_i(i);
    switch (funct3) {
    case 0: R(rd) = (int8_t)(Mr(src1 + imm, 1) & 0xFF); break; // lb
    case 1: R(rd) = (int16_t)(Mr(src1 + imm, 2) & 0xFFFF); break; // lh
    case 2: R(rd) = Mr(src1 + imm, 4); break; // lw
    case 4: R(rd) = (uint8_t)(Mr(src1 + imm, 1) & 0xFF); break; // lbu
    case 5: R(rd) = (uint16_t)(Mr(src1 + imm, 2) & 0xFFFF); break; // lhu
    default: INV(s->pc);
    }
    break;
  case 0x23: // store
    imm = imm_s(i);
    switch (funct3) {
    case 0: Mw(src1 + imm, 1, src2); break; // sb
    case 1: Mw(src1 + imm, 2, src2); break; // sh
    case 2: Mw(src1 + imm, 4, src2); break; // sw
    default: INV(s->pc);
    }
    break;

  case 0x13: // op-imm
    imm = imm_i(i);
    switch (funct3) {
    case 0: R(rd) = src1 + imm; break; // addi
    case 1: // slli
      if (funct7 != 0x00) {
        INV(s->pc);
        break;
      }
      R(rd) = src1 << (imm % 32);
      break;
    case 2: // slti
      if ((int)src1 < (int)imm) R(rd) = 1;
      else R(rd) = 0;
      break;
    case 3: // sltiu
      if (src1 < imm) R(rd) = 1;
      else R(rd) = 0;
      break;
    case 4: R(rd) = src1 ^ imm; break; // xori
    case 5:
      if (funct7 == 0x00) R(rd) = src1 >> (imm % 32); // srli
      else if (funct7 == 0x20) R(rd) = (int)src1 >> (imm % 32); // srai
      else INV(s->pc);
      break;
    case 6: R(rd) = src1 | imm; break; // ori
    case 7: R(rd) = src1 & imm; break; // andi
    default: INV(s->pc);
    }
    break;

  case 0x33: // op
    switch (funct7) {
    case 0x00:
      switch (funct3) {
      case 0: R(rd) = src1 + src2; break; // add
      case 1: R(rd) = src1 << (src2 % 32); break; // sll
      case 2: // slt
        if ((int)src1 < (int)src2) R(rd) = 1;
        else R(rd) = 0;
        break;
      case 3: // sltu
        if (src1 < src2) R(rd) = 1;
        else R(rd) = 0;
        break;
      case 4: R(rd) = src1 ^ src2; break; // xor
      case 5: R(rd) = src1 >> (src2 % 32); break; // srl
      case 6: R(rd) = src1 | src2; break; // or
      case 7: R(rd) = src1 & src2; break; // and
      }
      break;
    case 0x20:
      if (funct3 == 0) R(rd) = src1 - src2; // sub
      else if (funct3 == 5) R(rd) = (int)src1 >> (src2 % 32); // sra
      else INV(s->pc);
      break;
    case 0x01:
      switch (funct3) {
      case 0: R(rd) = src1 * src2; break; // mul
      case 1: // mulh
        R(rd) = (((int64_t)(int32_t)src1 * (int64_t)(int32_t)src2) >> 32) &
                0xFFFFFFFFu;
        break;
      case 2: // mulhsu
        R(rd) = (((int64_t)(int32_t)src1 * (uint64_t)(uint32_t)src2) >> 32) &
                0xFFFFFFFFu;
        break;
      case 3: // mulhu
        R(rd) = (((uint64_t)(uint32_t)src1 * (uint64_t)(uint32_t)src2) >> 32) &
                0xFFFFFFFFu;
        break;
      case 4: // div
        if (src2 == 0) R(rd) = 0xFFFFFFFFu;
        else if (src2 == 0xFFFFFFFFu && src1 == 0x80000000u) R(rd) = src1;
        else R(rd) = (int32_t)src1 / (int32_t)src2;
        break;
      case 5: // divu
        if (src2 == 0) R(rd) = 0xFFFFFFFFu;
        else R(rd) = src1 / src2;
        break;
      case 6: // rem
        if (src2 == 0) R(rd) = src1;
        else if (src2 == 0xFFFFFFFFu && src1 == 0x80000000u) R(rd) = 0;
        else R(rd) = (int32_t)src1 % (int32_t)src2;
        break;
      case 7: // remu
        if (src2 == 0) R(rd) = src1;
        else R(rd) = src1 % src2;
        break;
      }
      break;
    default: INV(s->pc);
    }
    break;

  case 0x0f: // fence (misc-mem)
    if (funct3 != 0) INV(s->pc);
    break;

  case 0x73: // system
    imm = BITS(i, 31, 20);
    switch (funct3) {
    case 0:
      if (i == 0x00000073) { // ecall
        s->dnpc = isa_raise_intr(ecall_cause(), s->pc);
      } else if (i == 0x00100073) { // ebreak
        NEMUTRAP(s->pc, R(10)); // R(10) is $a0
      } else if (i == 0x30200073) { // mret
        s->dnpc = cpu.mepc;
        IFDEF(CONFIG_ETRACE, Log("etrace: mret mepc=" FMT_WORD, cpu.mepc));
      } else {
        INV(s->pc);
      }
      break;
    case 1: { // csrrw
      word_t old = csr_read(imm);
      csr_write(imm, src1);
      if (rd != 0) R(rd) = old;
      break;
    }
    case 2: { // csrrs
      word_t old = csr_read(imm);
      csr_write(imm, old | src1);
      if (rd != 0) R(rd) = old;
      break;
    }
    case 3: { // csrrc
      word_t old = csr_read(imm);
      csr_write(imm, old & ~src1);
      if (rd != 0) R(rd) = old;
      break;
    }
    case 5: { // csrrwi
      word_t old = csr_read(imm);
      csr_write(imm, rs1);
      if (rd != 0) R(rd) = old;
      break;
    }
    case 6: { // csrrsi
      word_t old = csr_read(imm);
      csr_write(imm, old | rs1);
      if (rd != 0) R(rd) = old;
      break;
    }
    case 7: { // csrrci
      word_t old = csr_read(imm);
      csr_write(imm, old & ~((word_t)rs1));
      if (rd != 0) R(rd) = old;
      break;
    }
    default: INV(s->pc);
    }
    break;

  default:
    INV(s->pc);
  }

  R(0) = 0; // reset $zero to 0

  return 0;
}

int isa_exec_once(Decode *s) {
  s->isa.inst = inst_fetch(&s->snpc, 4);
  return decode_exec(s);
}
