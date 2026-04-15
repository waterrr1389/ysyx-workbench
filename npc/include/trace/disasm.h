#pragma once

#include "base/common.h"

#ifdef __cplusplus
extern "C" {
#endif

void init_disasm(void);
void disassemble(char* str, int size, uint64_t pc, const uint8_t* code, int nbyte);

#ifdef __cplusplus
}
#endif
