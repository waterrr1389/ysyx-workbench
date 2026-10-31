#pragma once

#include "base/common.h"
#include "base/debug.h"
#include "base/utils.h"
#include "sim/pmem.h"

void init_difftest(const char *ref_so_file, long img_size);
void difftest_step(vaddr_t pc, vaddr_t npc);
// Called from the memory model during the instruction that will commit next.
void difftest_skip_ref(void);
void difftest_note_store(word_t addr, uint8_t mask);
