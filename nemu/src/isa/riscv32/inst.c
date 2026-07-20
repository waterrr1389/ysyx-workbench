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

#include "../../monitor/sdb/ftrace.h"
#include "capstone/arm.h"
#include "isa.h"
#include "local-include/reg.h"
#include <cpu/cpu.h>
#include <cpu/decode.h>
#include <cpu/ifetch.h>
#include <stdint.h>

#define R(i) gpr(i)
#define Mr vaddr_read
#define Mw vaddr_write

enum {
  TYPE_I,
  TYPE_U,
  TYPE_S,
  TYPE_J,
  TYPE_R,
  TYPE_B,
  TYPE_CSR_R,
  TYPE_CSR_I,
  TYPE_N,
  TYPE_F // none
};

#define src1R()                                                                \
  do {                                                                         \
    *src1 = R(rs1);                                                            \
  } while (0)
#define src2R()                                                                \
  do {                                                                         \
    *src2 = R(rs2);                                                            \
  } while (0)
#define immI()                                                                 \
  do {                                                                         \
    *imm = SEXT(BITS(i, 31, 20), 12);                                          \
  } while (0)
#define immU()                                                                 \
  do {                                                                         \
    *imm = SEXT(BITS(i, 31, 12), 20) << 12;                                    \
  } while (0)
#define immS()                                                                 \
  do {                                                                         \
    *imm = (SEXT(BITS(i, 31, 25), 7) << 5) | BITS(i, 11, 7);                   \
  } while (0)
#define immJ()                                                                 \
  do {                                                                         \
    *imm = ((SEXT(BITS(i, 31, 31), 1) << 20) | (BITS(i, 19, 12) << 12) |       \
            (BITS(i, 20, 20) << 11) | (BITS(i, 30, 21) << 1));                 \
  } while (0)
#define immB()                                                                 \
  do {                                                                         \
    *imm = ((SEXT(BITS(i, 31, 31), 1) << 12) | (BITS(i, 30, 25) << 5) |        \
            (BITS(i, 11, 8) << 1) | (BITS(i, 7, 7) << 11));                    \
  } while (0)

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

static void decode_operand(Decode *s, int *rd, word_t *src1, word_t *src2,
                           word_t *imm, int type) {
  uint32_t i = s->isa.inst;
  int rs1 = BITS(i, 19, 15);
  int rs2 = BITS(i, 24, 20);
  *rd = BITS(i, 11, 7);
  switch (type) {
  case TYPE_I:
    src1R();
    immI();
    break;
  case TYPE_U:
    immU();
    break;
  case TYPE_S:
    src1R();
    src2R();
    immS();
    break;
  case TYPE_J:
    immJ();
    break;
  case TYPE_R:
    src1R();
    src2R();
    break;
  case TYPE_B:
    src1R();
    src2R();
    immB();
    break;
  case TYPE_CSR_R:
    src1R();
    *rd = BITS(i, 11, 7);
    *imm = BITS(i, 31, 20);
    break;
  case TYPE_CSR_I:
    *src1 = BITS(i, 19, 15);
    *rd = BITS(i, 11, 7);
    *imm = BITS(i, 31, 20);
    break;
  case TYPE_N:
    break;
  case TYPE_F:
    break;
  default:
    panic("unsupported type = %d", type);
  }
}

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

static int decode_exec(Decode *s) {
  s->dnpc = s->snpc;

#define INSTPAT_INST(s) ((s)->isa.inst)
#define INSTPAT_MATCH(s, name, type, ... /* execute body */)                   \
  {                                                                            \
    int rd = 0;                                                                \
    word_t src1 = 0, src2 = 0, imm = 0;                                        \
    decode_operand(s, &rd, &src1, &src2, &imm, concat(TYPE_, type));           \
    __VA_ARGS__;                                                               \
  }

  INSTPAT_START();
  INSTPAT("??????? ????? ????? ??? ????? 00101 11", auipc, U,
          R(rd) = s->pc + imm); //
  INSTPAT("??????? ????? ????? ??? ????? 01101 11", lui, U, R(rd) = imm);
  INSTPAT("0000000 ????? ????? 000 ????? 01100 11", add, R,
          R(rd) = src1 + src2);
  INSTPAT("0100000 ????? ????? 000 ????? 01100 11", sub, R,
          R(rd) = src1 - src2);

  // set less than
  INSTPAT("0000000 ????? ????? 010 ????? 01100 11", slt, R,
          if ((int)src1 < (int)src2) R(rd) = 1;
          else R(rd) = 0);
  INSTPAT("0000000 ????? ????? 011 ????? 01100 11", sltu, R,
          if (src1 < src2) R(rd) = 1;
          else R(rd) = 0);
  INSTPAT("??????? ????? ????? 010 ????? 00100 11", slti, I,
          if ((int)src1 < (int)imm) R(rd) = 1;
          else R(rd) = 0);
  INSTPAT("??????? ????? ????? 011 ????? 00100 11", sltiu, I,
          if (src1 < imm) R(rd) = 1;
          else R(rd) = 0); //

  // shift
  INSTPAT("0000000 ????? ????? 001 ????? 01100 11", sll, R,
          R(rd) = src1 << (src2 % 32));
  INSTPAT("0000000 ????? ????? 101 ????? 01100 11", srl, R,
          R(rd) = src1 >> (src2 % 32));
  INSTPAT("0100000 ????? ????? 101 ????? 01100 11", sra, R,
          R(rd) = (int)src1 >> (src2 % 32));
  INSTPAT("0100000 ????? ????? 101 ????? 00100 11", srai, I,
          R(rd) = (int)src1 >> (imm % 32));
  INSTPAT("0000000 ????? ????? 101 ????? 00100 11", srli, I,
          R(rd) = src1 >> (imm % 32));
  INSTPAT("0000000 ????? ????? 001 ????? 00100 11", slli, I,
          R(rd) = src1 << (imm % 32));

  // bit-wise operation
  INSTPAT("0000000 ????? ????? 100 ????? 01100 11", xor, R,
          R(rd) = src1 ^ src2);
  INSTPAT("0000000 ????? ????? 110 ????? 01100 11", or, R, R(rd) = src1 | src2);
  INSTPAT("0000000 ????? ????? 111 ????? 01100 11", and, R,
          R(rd) = src1 & src2);
  INSTPAT("??????? ????? ????? 100 ????? 00100 11", xori, I,
          R(rd) = src1 ^ imm);
  INSTPAT("??????? ????? ????? 110 ????? 00100 11", ori, I, R(rd) = src1 | imm);
  INSTPAT("??????? ????? ????? 111 ????? 00100 11", andi, I,
          R(rd) = src1 & imm);

  INSTPAT("??????? ????? ????? 000 ????? 00100 11", addi, I,
          R(rd) = src1 + imm;); //

  // Load && Store
  INSTPAT("??????? ????? ????? 010 ????? 00000 11", lw, I,
          R(rd) = Mr(src1 + imm, 4));
  INSTPAT("??????? ????? ????? 000 ????? 00000 11", lb, I,
          R(rd) = (int8_t)(Mr(src1 + imm, 1) & 0xFF));
  INSTPAT("??????? ????? ????? 100 ????? 00000 11", lbu, I,
          R(rd) = (uint8_t)(Mr(src1 + imm, 1) & 0xFF));
  INSTPAT("??????? ????? ????? 001 ????? 00000 11", lh, I,
          R(rd) = (int16_t)(Mr(src1 + imm, 2) & 0xFFFF));
  INSTPAT("??????? ????? ????? 101 ????? 00000 11", lhu, I,
          R(rd) = (uint16_t)(Mr(src1 + imm, 2) & 0xFFFF));
  INSTPAT("??????? ????? ????? 000 ????? 01000 11", sb, S,
          Mw(src1 + imm, 1, src2));
  INSTPAT("??????? ????? ????? 010 ????? 01000 11", sw, S,
          Mw(src1 + imm, 4, src2)); //
  INSTPAT("??????? ????? ????? 001 ????? 01000 11", sh, S,
          Mw(src1 + imm, 2, src2));

  // control flow
  INSTPAT("??????? ????? ????? 100 ????? 11000 11", blt, B,
          if ((int)src1 < (int)src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 110 ????? 11000 11", bltu, B,
          if (src1 < src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 101 ????? 11000 11", bge, B,
          if ((int)src1 >= (int)src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 111 ????? 11000 11", bgeu, B,
          if (src1 >= src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 000 ????? 11000 11", beq, B,
          if (src1 == src2) s->dnpc = s->pc + imm); //
  INSTPAT("??????? ????? ????? 001 ????? 11000 11", bne, B,
          if (src1 != src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? ??? ????? 11011 11", jal, J,
          s->dnpc = s->pc + imm;
          R(rd) = s->snpc; JAL_CASE(s->pc, s->dnpc););
  INSTPAT("??????? ????? ????? 000 ????? 11001 11", jalr, I, R(rd) = s->snpc;
          s->dnpc = (src1 + imm) & ~1UL; JALR_CASE(s->pc, s->dnpc););
  INSTPAT("0000001 ????? ????? 000 ????? 01100 11", mul, R,
          R(rd) = src1 * src2);
  INSTPAT("0000001 ????? ????? 001 ????? 01100 11", mulh, R,
          R(rd) = (((int64_t)(int32_t)src1 * (int64_t)(int32_t)src2) >> 32) &
                  0xFFFFFFFFu);
  INSTPAT("0000001 ????? ????? 011 ????? 01100 11", mulhu, R,
          R(rd) =
              (((uint64_t)(uint32_t)src1 * (uint64_t)(uint32_t)src2) >> 32) &
              0xFFFFFFFFu);
  INSTPAT("0000001 ????? ????? 010 ????? 01100 11", mulhsu, R,
          R(rd) = (((int64_t)(int32_t)src1 * (uint64_t)(uint32_t)src2) >> 32) &
                  0xFFFFFFFFu);

  INSTPAT("0000001 ????? ????? 100 ????? 01100 11", div, R,
          if (src2 == 0) R(rd) = 0xFFFFFFFFu;
          else if (src2 == 0xFFFFFFFFu && src1 == 0x80000000u) R(rd) = src1;
          else R(rd) = (int32_t)src1 / (int32_t)src2);
  INSTPAT("0000001 ????? ????? 101 ????? 01100 11", divu, R,
          if (src2 == 0) R(rd) = 0xFFFFFFFFu;
          else R(rd) = src1 / src2);
  INSTPAT("0000001 ????? ????? 110 ????? 01100 11", rem, R,
          if (src2 == 0) R(rd) = src1;
          else if (src2 == 0xFFFFFFFFu && src1 == 0x80000000u) R(rd) = 0;
          else R(rd) = (int32_t)src1 % (int32_t)src2);
  INSTPAT("0000001 ????? ????? 111 ????? 01100 11", remu, R,
          if (src2 == 0) R(rd) = src1;
          else R(rd) = src1 % src2);
  INSTPAT("??????? ????? ????? 000 ????? 00011 11", fence, F, ;);
  INSTPAT("0000000 00001 00000 000 00000 11100 11", ebreak, N,
          NEMUTRAP(s->pc, R(10))); // R(10) is $a0

  // 8 - Environment call from U-mode
  INSTPAT("000000000000 00000 000 00000 1110011", ecall, N, s->dnpc = isa_raise_intr(8, s->snpc);); 
  INSTPAT("??????? ????? ????? 001 ????? 11100 11", csrrw, CSR_R, word_t old = csr_read(imm); csr_write(imm, src1); if (rd != 0) R(rd) = old;);
  INSTPAT("??????? ????? ????? 010 ????? 11100 11", csrrs, CSR_R, word_t old = csr_read(imm); csr_write(imm, old | src1); if (rd != 0) R(rd) = old;);
  INSTPAT("??????? ????? ????? 011 ????? 11100 11", csrrc, CSR_R, word_t old = csr_read(imm); csr_write(imm, old & ~src1); if (rd != 0) R(rd) = old;);
  INSTPAT("??????? ????? ????? 101 ????? 11100 11", csrrwi, CSR_I, word_t old = csr_read(imm); csr_write(imm, src1); if (rd != 0) R(rd) = old;);
  INSTPAT("??????? ????? ????? 110 ????? 11100 11", csrrsi, CSR_I, word_t old = csr_read(imm); csr_write(imm, old | src1); if (rd != 0) R(rd) = old;);
  INSTPAT("??????? ????? ????? 111 ????? 11100 11", csrrci, CSR_I, word_t old = csr_read(imm); csr_write(imm, old & ~src1); if (rd != 0) R(rd) = old;);
  INSTPAT("001100000010 00000 000 00000 11100 11", mret, N, s->dnpc = cpu.mepc; IFDEF(CONFIG_ETRACE, Log("etrace: mret mepc=" FMT_WORD, cpu.mepc)););
  INSTPAT("??????? ????? ????? ??? ????? ????? ??", inv, N, INV(s->pc));

  INSTPAT_END();

  R(0) = 0; // reset $zero to 0

  return 0;
}

int isa_exec_once(Decode *s) {
  s->isa.inst = inst_fetch(&s->snpc, 4);
  return decode_exec(s);
}