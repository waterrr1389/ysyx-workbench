#include "base/debug.h"
#include "sim/pmem.h"
#include "sim/sim_main.h"

static uint8_t* pmem = NULL;

void init_mem(void) {
  pmem = (uint8_t*)malloc(PMEM_SIZE);
  Assert(pmem != NULL, "Failed to allocate pmem");
  memset(pmem, 0, PMEM_SIZE);
}

void free_mem(void) {
  free(pmem);
  pmem = NULL;
}

bool in_pmem(word_t addr) {
  return addr - PMEM_BASE < PMEM_SIZE;
}

uint8_t* guest_to_host(word_t addr) {
  Assert(in_pmem(addr), "address " FMT_WORD " is out of pmem at pc = " FMT_WORD,
      addr, current_pc);
  Assert(pmem != NULL, "pmem is not initialized");
  return pmem + addr - PMEM_BASE;
}

static void out_of_bound(word_t addr) {
  Assert(0, "address " FMT_WORD " is out of pmem [" FMT_WORD ", " FMT_WORD "] at pc = " FMT_WORD,
      addr, (word_t)PMEM_BASE, (word_t)(PMEM_BASE + PMEM_SIZE - 1), current_pc);
}

word_t host_pmem_read(word_t addr, int len) {
  Assert(len >= 1 && len <= 4, "Unsupported pmem read length %d", len);

  word_t last = addr + (word_t)len - 1;
  if (!in_pmem(addr) || !in_pmem(last)) {
    out_of_bound(addr);
  }

  uint8_t* haddr = guest_to_host(addr);
  word_t ret = 0;
  for (int i = 0; i < len; i++) {
    ret |= (word_t)haddr[i] << (i * 8);
  }
  return ret;
}

void host_pmem_write(word_t addr, int len, word_t data) {
  Assert(len >= 1 && len <= 4, "Unsupported pmem write length %d", len);

  word_t last = addr + (word_t)len - 1;
  if (!in_pmem(addr) || !in_pmem(last)) {
    out_of_bound(addr);
  }

  uint8_t* haddr = guest_to_host(addr);
  for (int i = 0; i < len; i++) {
    haddr[i] = (uint8_t)((data >> (i * 8)) & 0xffu);
  }
}
