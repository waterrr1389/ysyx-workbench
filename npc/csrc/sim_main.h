#pragma once

class Vtop;
class VerilatedContext;
class VerilatedFstC;

enum { NPC_RUNNING, NPC_STOP, NPC_END, NPC_ABORT, NPC_QUIT };

struct NPCState {
  int state;
  unsigned int halt_pc;
  unsigned int halt_ret;
};

extern Vtop* top;
extern VerilatedContext* contextp;
extern VerilatedFstC* tfp;
extern bool sim;
extern unsigned int current_pc;
extern NPCState npc_state;

void __step_and_dump_wave();

long load_img();
int getIndex(int pc);
void fetch_inst();
void step_and_dump_wave();
void step_one_cycle();
void sim_init();
void sim_exit();
