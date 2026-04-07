#pragma once

#include <stdint.h>

class Vtop;
class VerilatedContext;
class VerilatedFstC;

enum { NPC_RUNNING, NPC_STOP, NPC_END, NPC_ABORT, NPC_QUIT };

struct NPCState {
  int state;
  uint32_t halt_pc;
  uint32_t halt_ret;
};

extern Vtop* top;
extern VerilatedContext* contextp;
extern VerilatedFstC* tfp;
extern bool sim;
extern uint32_t current_pc;
extern NPCState npc_state;

long load_img();
void step_one_cycle();
void sim_init();
void sim_exit();
