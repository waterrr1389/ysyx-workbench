#include "base/debug.h"
#include "base/config.h"
#include "sim/dpi-c.h"
#include "sim/pmem.h"
#include "sim/sim_main.h"

#include <time.h>

#define RTC_ADDR 0xa0000048u

// Reading the low word samples the host clock; the high word returns the same
// sample, so a low-then-high read pair forms one consistent 64-bit value.
static uint64_t rtc_us;

static uint64_t host_time_us(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

#if NPC_MTRACE
static int popcount4(uint8_t mask) {
  int count = 0;
  for (int i = 0; i < 4; i++) {
    if ((mask & (1u << i)) != 0) {
      count++;
    }
  }
  return count;
}
#endif

int pmem_read(int raddr) {
  word_t addr = (word_t)raddr & ~0x3u;
#if NPC_MTRACE
  Log("mtrace: read addr = " FMT_WORD ", len = %d", addr, 4);
#endif
  if (addr == RTC_ADDR) {
    rtc_us = host_time_us();
    return (int)(uint32_t)rtc_us;
  }
  if (addr == RTC_ADDR + 4) return (int)(uint32_t)(rtc_us >> 32);
  return (int)host_pmem_read(addr, 4);
}

void pmem_write(int waddr, int wdata, char wmask) {
  word_t addr = (word_t)waddr & ~0x3u;
  word_t data = (word_t)wdata;
  uint8_t mask = (uint8_t)wmask;
#if NPC_MTRACE
  Log("mtrace: write addr = " FMT_WORD ", len = %d, data = " FMT_WORD ", wmask = 0x%02x",
      addr, popcount4(mask), data, mask);
#endif

  for (int i = 0; i < 4; i++) {
    if ((mask & (1u << i)) != 0) {
      word_t byte_addr = addr + (word_t)i;
      word_t byte_data = (data >> (i * 8)) & 0xffu;
      host_pmem_write(byte_addr, 1, byte_data);
    }
  }
}

void npc_trap(void) {
  npc_state.state = NPC_END;
  npc_state.halt_pc = current_pc;
  sim = false;
}
