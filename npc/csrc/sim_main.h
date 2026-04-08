#pragma once

#include <assert.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <iRingBuffer.h>

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
uint32_t read_gpr(uint32_t index);

#define FMT_WORD "0x%08" PRIx32

#define Assert(cond, format, ...) \
  do { \
    if (!(cond)) { \
      fflush(stdout); \
      fprintf(stderr, format "\n", ## __VA_ARGS__); \
      assert(cond); \
    } \
  } while (0)
