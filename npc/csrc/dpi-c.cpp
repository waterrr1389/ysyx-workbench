#include <stdio.h>
#include "svdpi.h"
#include "dpi-c.h"
#include "sim_main.h"
extern bool sim;

void npc_trap() {
    npc_state.state = NPC_END;
    npc_state.halt_pc = current_pc;
    sim = false;
}
