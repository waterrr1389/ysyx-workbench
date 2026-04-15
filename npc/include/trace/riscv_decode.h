#pragma once

#include "base/common.h"

#define BITMASK(bits) ((1ULL << (bits)) - 1ULL)
#define BITS(x, hi, lo) (((x) >> (lo)) & BITMASK((hi) - (lo) + 1))
#define SEXT(x, len) ({ struct { int64_t n : len; } __x = { .n = (int64_t)(x) }; (int64_t)__x.n; })

#define RV_OPCODE(i) ((uint32_t)BITS((i), 6, 0))
#define RV_RD(i) ((uint32_t)BITS((i), 11, 7))
#define RV_FUNCT3(i) ((uint32_t)BITS((i), 14, 12))
#define RV_RS1(i) ((uint32_t)BITS((i), 19, 15))

#define RV_IMM_I(i) ((int32_t)SEXT(BITS((i), 31, 20), 12))
#define RV_IMM_J(i) \
  ((int32_t)((SEXT(BITS((i), 31, 31), 1) << 20) | (BITS((i), 19, 12) << 12) | \
             (BITS((i), 20, 20) << 11) | (BITS((i), 30, 21) << 1)))
