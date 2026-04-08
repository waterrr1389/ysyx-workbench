#include <cstdint>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
#include "Vtop.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include "svdpi.h"
#include "dpi-c.h"
#include "sim_main.h"

#define MBASE 0x80000000u
#define ANSI_FG_RED     "\33[1;31m"
#define ANSI_FG_GREEN   "\33[1;32m"
#define ANSI_NONE       "\33[0m"
#define ANSI_FMT(str, fmt) fmt str ANSI_NONE
#define RESET_CYCLES    11
#define NOP_INST        0x00000013u
#define A0_REG_INDEX    10u
#define GPR_SCOPE_NAME  "TOP.top.rf0"
#define NPC_ITRACE 1

Vtop* top;
VerilatedContext* contextp;
VerilatedFstC* tfp;
bool sim;
uint32_t current_pc;
NPCState npc_state = { .state = NPC_STOP, .halt_pc = 0, .halt_ret = 0 };
static const char* img_file = NULL;
static uint8_t *img_buf = NULL;
static char* inst_buf = NULL;
static long img_size = 0;
static svScope gpr_scope = nullptr;

static void init_npc_state() {
  sim = true;
  current_pc = 0;
  npc_state.state = NPC_RUNNING;
  npc_state.halt_pc = 0;
  npc_state.halt_ret = 0;
}

static void init_gpr_scope() {
  gpr_scope = svGetScopeFromName(GPR_SCOPE_NAME);
  assert(gpr_scope != nullptr);
}

static uint32_t read_gpr(uint32_t index) {
  svSetScope(gpr_scope);
  return get_gpr(index);
}

static void print_trap_result() {
  if (npc_state.state != NPC_END) {
    return;
  }

  npc_state.halt_ret = read_gpr(A0_REG_INDEX);
  printf("npc: %s at pc = 0x%08x\n",
      npc_state.halt_ret == 0
          ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN)
          : ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED),
      npc_state.halt_pc);
}

static void cleanup() {
  tfp->close();
  delete top;
  delete contextp;
  free(inst_buf);
  free(img_buf);
}

long load_img() {
  if (img_file == NULL) {
    fprintf(stderr, "Error: no image is given.\n");
    exit(1);
  }

  FILE* fp = fopen(img_file, "rb");
  if (fp == NULL) {
    fprintf(stderr, "Error: can not open '%s'\n", img_file);
    exit(1);
  }

  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  assert(size >= 0);
  fseek(fp, 0, SEEK_SET);

  img_buf = (uint8_t*)malloc(size);
  assert(img_buf != NULL);

  size_t ret = fread(img_buf, 1, size, fp);
  assert(ret == (size_t)size);
  fclose(fp);

  printf("The image is %s, size = %ld\n", img_file, size);
  return size;
}

static int get_inst_index(uint32_t pc) {
  return (pc - MBASE) / 4;
}

static void fetch_inst() {
  current_pc = top->pc;
  int index = get_inst_index(top->pc);
  long byte_index = (long)index * 4;

	uint32_t inst = (uint32_t)img_buf[byte_index]
              | ((uint32_t)img_buf[byte_index + 1] << 8)
              | ((uint32_t)img_buf[byte_index + 2] << 16)
              | ((uint32_t)img_buf[byte_index + 3] << 24);

  if (index >= 0 && byte_index + 4 <= img_size) {
    top->inst = inst; 
  } else {
  	top->inst = NOP_INST;
	}

#ifdef NPC_ITRACE
	char *p = inst_buf;
  p += snprintf(p, 128, FMT_WORD ":", current_pc);
  int ilen = 8; 
  int i;

  for (i = ilen - 1; i >= 0; i--) { // 以小端序输出指令
    p += snprintf(p, 4, " %02x", img_buf[byte_index+i]);
  }
  int ilen_max = 4;
  int space_len = ilen_max - ilen; // space_len空格长度
  if (space_len < 0)
    space_len = 0;
  space_len = space_len * 3 + 1; // 对于RV来说,space=1
  memset(p, ' ', space_len);
  p += space_len;

  void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte);

  int disassemble_size = 128 - (int)(p - inst_buf);
  disassemble(p, disassemble_size, current_pc,
              (uint8_t*)&inst, ilen);
  iRingBufferWrite(p, disassemble_size);
#endif
}

static void step_and_dump_wave() {
  top->eval();
  contextp->timeInc(1);
  tfp->dump(contextp->time());
  top->clk = !top->clk;
}

void step_one_cycle() {
  fetch_inst();
  step_and_dump_wave();
  step_and_dump_wave();
}

void sim_init() {
  contextp = new VerilatedContext;
  top = new Vtop{contextp};
  tfp = new VerilatedFstC;
  Verilated::traceEverOn(true);

	inst_buf = (char*)malloc(128);
	Assert(inst_buf, "Failed to alloc memory for itarce buffer");

  top->trace(tfp, 99);
  tfp->open("waveform.fst");

  top->reset = 1;
  top->clk = 0;
  top->inst = 0;

  init_npc_state();
  init_gpr_scope();

  for (int i = 0; i < RESET_CYCLES; i++) {
    step_and_dump_wave();
  }
  top->reset = 0;
  current_pc = top->pc;
}

void sim_exit() {
  print_trap_result();
  cleanup();
}

int main(int argc, char** argv) {
  if (argc < 2) {
    fprintf(stderr, "Usage: %s <image_file>\n", argv[0]);
    return 1;
  }

  img_file = argv[1];
  img_size = load_img();

  sim_init();
  while (sim) {
    step_one_cycle();
  }
  sim_exit();

  return 0;
}
