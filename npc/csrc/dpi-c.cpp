#include "sim/dpi-c.h"
#include "sim/sim_main.h"

void npc_trap(void) {
  npc_state.state = NPC_END;
  npc_state.halt_pc = current_pc;
  sim = false;
}
