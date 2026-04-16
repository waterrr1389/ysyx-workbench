#include "sim/dpi-c.h"
#include "sim/pmem.h"
#include "sim/sim_main.h"

int pmem_read(int raddr) {
  word_t addr = (word_t)raddr & ~0x3u;
  return (int)host_pmem_read(addr, 4);
}

void pmem_write(int waddr, int wdata, char wmask) {
  word_t addr = (word_t)waddr & ~0x3u;
  word_t data = (word_t)wdata;
  uint8_t mask = (uint8_t)wmask;

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
