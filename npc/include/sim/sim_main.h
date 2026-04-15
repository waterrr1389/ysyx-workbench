#pragma once

#include "base/common.h"

#ifdef __cplusplus
class Vtop;
class VerilatedContext;
class VerilatedFstC;
#else
typedef struct Vtop Vtop;
typedef struct VerilatedContext VerilatedContext;
typedef struct VerilatedFstC VerilatedFstC;
#endif

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

long load_img(void);
void step_one_cycle(void);
void sim_init(void);
void sim_exit(void);
uint32_t read_gpr(uint32_t index);

#define FMT_WORD "0x%08" PRIx32
