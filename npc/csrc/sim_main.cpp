#include <cstdint>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
#include "Vtop.h"
#include "Vtop__Dpi.h"
#include "difftest/difftest.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include "svdpi.h"
#include "base/config.h"
#include "base/debug.h"
#include "sim/dpi-c.h"
#include "sim/pmem.h"
#include "sim/sdb.h"
#include "sim/sim_main.h"
#include "trace/disasm.h"
#include "trace/ftrace.h"
#include "trace/iRingBuffer.h"

#define RESET_CYCLES    11
#define NOP_INST        0x00000013u
#define A0_REG_INDEX    10u
#define GPR_SCOPE_NAME  "TOP.top.rf0"
static const char* REF_SO_FILE = "/home/frisk/ysyx-workbench/nemu/build/riscv32-nemu-interpreter-so";

Vtop* top;
VerilatedContext* contextp;
VerilatedFstC* tfp;
bool sim;
uint32_t current_pc;
NPCState npc_state = { .state = NPC_STOP, .halt_pc = 0, .halt_ret = 0 };
svScope gpr_scope = nullptr;
static const char* img_file = NULL;
static const char* elf_file = NULL;
static char* inst_buf = NULL;
static long img_size = 0;

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

uint32_t read_gpr(uint32_t index) {
  svSetScope(gpr_scope);
  return get_gpr(index);
}

static void print_trap_result() {
  if (npc_state.state == NPC_END) {
    npc_state.halt_ret = read_gpr(A0_REG_INDEX);
    printf("npc: %s at pc = 0x%08x\n",
        npc_state.halt_ret == 0
            ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN)
            : ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED),
        npc_state.halt_pc);
  } else if (npc_state.state == NPC_ABORT) {
    printf("npc: %s at pc = 0x%08x\n",
        ANSI_FMT("ABORT", ANSI_FG_RED), npc_state.halt_pc);
  }
}

static void cleanup() {
  tfp->close();
  delete top;
  delete contextp;
#if NPC_ITRACE
  free(inst_buf);
#endif
  free_mem();
}

long load_img(void) {
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

  Assert((unsigned long)size <= PMEM_SIZE,
      "Image '%s' is too large: %ld bytes exceeds pmem size %u",
      img_file, size, PMEM_SIZE);

  size_t ret = fread(guest_to_host(PMEM_BASE), 1, size, fp);
  assert(ret == (size_t)size);
  fclose(fp);

  printf("The image is %s, size = %ld\n", img_file, size);
  return size;
}

static void trace_inst() {
  current_pc = top->pc;
#if NPC_NEED_INST_TRACE
  uint32_t inst = host_pmem_read(current_pc, 4);

#if NPC_FTRACE
  ftrace_check(current_pc, inst);
#endif

#if NPC_ITRACE
	char *p = inst_buf;
  p += snprintf(p, 128, FMT_WORD ":", current_pc);
  int ilen = 4; 
  int i;

  for (i = ilen - 1; i >= 0; i--) {
    uint8_t byte = (uint8_t)((inst >> (i * 8)) & 0xffu);
    p += snprintf(p, 4, " %02x", byte);
  }
  int ilen_max = 4;
  int space_len = ilen_max - ilen; // space_len空格长度
  if (space_len < 0)
    space_len = 0;
  space_len = space_len * 3 + 1; // 对于RV来说,space=1
  memset(p, ' ', space_len);
  p += space_len;

  int disassemble_size = 128 - (int)(p - inst_buf);
  disassemble(p, disassemble_size, current_pc,
              (const uint8_t*)&inst, ilen);
  iRingBufferWrite(p, disassemble_size);
#endif
#endif
}

static void step_and_dump_wave() {
  top->eval();
  contextp->timeInc(1);
  tfp->dump(contextp->time());
  top->clk = !top->clk;
}

void step_one_cycle(void) {
  trace_inst();
  uint32_t pc = current_pc;
  step_and_dump_wave();
  step_and_dump_wave();
  if (sim) {
    difftest_step(pc, top->pc);
  }
}

void sim_init(void) {
  contextp = new VerilatedContext;
  top = new Vtop{contextp};
  tfp = new VerilatedFstC;
  Verilated::traceEverOn(true);

#if NPC_ITRACE
	inst_buf = (char*)malloc(128);
	Assert(inst_buf, "Failed to alloc memory for itarce buffer");
#endif

  top->trace(tfp, 99);
  tfp->open("waveform.fst");

  top->reset = 1;
  top->clk = 0;

  init_npc_state();
  init_gpr_scope();

  for (int i = 0; i < RESET_CYCLES; i++) {
    step_and_dump_wave();
  }
  top->reset = 0;
  current_pc = top->pc;

#if NPC_ITRACE
  init_disasm();
  iRingBufferInit();
#endif
}

void sim_exit(void) {
  print_trap_result();
#if NPC_ITRACE
  iRingBufferDump();
#endif
  cleanup();
}

int sim_status(void) {
  switch (npc_state.state) {
    case NPC_END:
      return npc_state.halt_ret == 0 ? 0 : 1;
    case NPC_ABORT:
      return 1;
    case NPC_QUIT:
      return 0;
    default:
      return 1;
  }
}

int main(int argc, char** argv) {
  const struct option table[] = {
      {"batch", no_argument, NULL, 'b'},
      {"elf", required_argument, NULL, 'e'},
      {0, 0, NULL, 0},
  };

  int opt = 0;
  while ((opt = getopt_long(argc, argv, "be:", table, NULL)) != -1) {
    switch (opt) {
    case 'b':
      sdb_set_batch_mode();
      break;
    case 'e':
      elf_file = optarg;
      break;
    default:
      fprintf(stderr, "Usage: %s [-b] IMAGE.bin [-e IMAGE.elf]\n", argv[0]);
      return 1;
    }
  }

  if (optind >= argc) {
    fprintf(stderr, "Usage: %s [-b] IMAGE.bin [-e IMAGE.elf]\n", argv[0]);
    return 1;
  }

  img_file = argv[optind];

  init_mem();
  img_size = load_img();
#if NPC_FTRACE
  readelf(elf_file);
#endif
  init_difftest(REF_SO_FILE, img_size);

  sim_init();
  sdb_mainloop();
  sim_exit();

  return sim_status();
}
