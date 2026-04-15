#pragma once

#include "base/common.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PMEM_BASE 0x80000000u
#define PMEM_SIZE 0x02000000u
#define RESET_VECTOR 0x80000000u

void init_mem(void);
void free_mem(void);
uint8_t* guest_to_host(word_t addr);
bool in_pmem(word_t addr);
word_t pmem_read(word_t addr, int len);
void pmem_write(word_t addr, int len, word_t data);

#ifdef __cplusplus
}
#endif
