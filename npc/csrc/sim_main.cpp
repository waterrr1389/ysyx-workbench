#include <cstdint>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
#include "Vtop.h"
#include "sim/cpu_state.h"
#include "difftest/difftest.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include "base/config.h"
#include "base/debug.h"
#include "sim/dpi-c.h"
#include "sim/pmem.h"
#include "sim/sdb.h"
#include "sim/sim_main.h"
#include "trace/disasm.h"
#include "trace/ftrace.h"
#include "trace/iRingBuffer.h"

// The standalone top names its clock clk; ysyxSoCFull uses the SoC's name.
#if NPC_SOC
#define TOP_CLOCK clock
#else
#define TOP_CLOCK clk
#endif

#define RESET_CYCLES    5
#define NOP_INST        0x00000013u
#define A0_REG_INDEX    10u

static Vtop* top;
static VerilatedContext* contextp;
static VerilatedFstC* tfp;
bool sim;
uint32_t current_pc;
NPCState npc_state = { .state = NPC_STOP, .halt_pc = 0, .halt_ret = 0 };
static const char* img_file = NULL;
static const char* elf_file = NULL;
static const char* wave_file = NULL;
// 0 disables the limit.
static uint64_t max_cycles = 0;
// A hung bus or a stuck stage shows up as cycles without a commit.
static uint64_t watchdog_cycles = 1000000;
static uint64_t cycles = 0;
static uint64_t insts = 0;
static uint64_t last_commit_cycle = 0;
static char* inst_buf = NULL;
static long img_size = 0;

static void init_npc_state() {
  sim = true;
  current_pc = 0;
  npc_state.state = NPC_RUNNING;
  npc_state.halt_pc = 0;
  npc_state.halt_ret = 0;
  npc_state.reason = NULL;
}

void npc_abort(const char* reason, uint32_t pc) {
  npc_state.state = NPC_ABORT;
  npc_state.halt_pc = pc;
  npc_state.reason = reason;
  sim = false;
}

// Every run ends with exactly one line of this shape, so scripts can grep "npc: result=".
static void print_summary() {
  const char* result;
  bool good = false;
  switch (npc_state.state) {
    case NPC_END:
      npc_state.halt_ret = read_gpr(A0_REG_INDEX);
      good = npc_state.halt_ret == 0;
      result = good ? "good-trap" : "bad-trap";
      break;
    case NPC_ABORT: result = npc_state.reason; break;
    case NPC_QUIT:  result = "quit"; good = true; break;
    default:        result = "stopped"; break;
  }
  printf("npc: result=%s%s%s pc=0x%08x cycles=%" PRIu64 " insts=%" PRIu64 " ipc=%.4f\n",
      good ? ANSI_FG_GREEN : ANSI_FG_RED, result, ANSI_NONE, npc_state.halt_pc,
      cycles, insts, cycles ? (double)insts / cycles : 0.0);
}

static void cleanup() {
  if (tfp) tfp->close();
  delete tfp;
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

static void dump_wave() {
  contextp->timeInc(1);
  if (tfp) tfp->dump(contextp->time());
}

// One cycle has one rising edge followed by the snapshot reporting edge.
static void tick() {
  top->TOP_CLOCK = 1; top->eval(); dump_wave();
  top->TOP_CLOCK = 0; top->eval(); dump_wave();
}

bool step_one_cycle(void) {
  current_pc = cpu_state().pc;
  tick();
  cycles++;
  CpuReport report;
  bool commit = cpu_report_take(&report);
  if (commit) {
    assert(!report.initial);
    current_pc = report.commit_pc;
    // JALR tracing must see the source register before this commit's writeback.
    trace_inst();
    cpu_state_accept(report);
    insts++;
    last_commit_cycle = cycles;
  }
#if NPC_DIFFTEST
  if (commit && sim) {
    difftest_step(current_pc, report.state.pc);
  }
#endif
  if (sim && cycles - last_commit_cycle >= watchdog_cycles) {
    npc_abort("watchdog", current_pc);
  } else if (sim && max_cycles != 0 && cycles >= max_cycles) {
    npc_abort("cycle-limit", current_pc);
  }
  return commit;
}

void step_one_inst(void) {
  while (sim && !step_one_cycle()) {
  }
}

void sim_init(void) {
  top = new Vtop{contextp};
  tfp = NULL;
  Verilated::traceEverOn(wave_file != NULL);

#if NPC_ITRACE
	inst_buf = (char*)malloc(128);
	Assert(inst_buf, "Failed to alloc memory for itarce buffer");
#endif

  if (wave_file != NULL) {
    tfp = new VerilatedFstC;
    top->trace(tfp, 99);
    tfp->open(wave_file);
  }

  top->reset = 1;
  top->TOP_CLOCK = 0;

  init_npc_state();
  cpu_state_init();
  top->eval();

  for (int i = 0; i < RESET_CYCLES; i++) {
    tick();
  }
  top->reset = 0;
  top->eval();
  CpuReport initial;
  bool received = cpu_report_take(&initial);
  assert(received && initial.initial);
  cpu_state_accept(initial);
  current_pc = initial.state.pc;

#if NPC_ITRACE
  init_disasm();
  iRingBufferInit();
#endif
}

void sim_exit(void) {
  print_summary();
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
  // Before option parsing: the model reads plusargs from its own context.
  contextp = new VerilatedContext;
  contextp->commandArgs(argc, argv);

  const struct option table[] = {
      {"batch", no_argument, NULL, 'b'},
      {"elf", required_argument, NULL, 'e'},
      {"wave", required_argument, NULL, 'w'},
      {"max-cycles", required_argument, NULL, 'c'},
      {"watchdog", required_argument, NULL, 'd'},
      {0, 0, NULL, 0},
  };
  const char* usage =
      "Usage: %s [-b] [-e IMAGE.elf] [-w WAVE.fst] [--max-cycles N] [--watchdog N] IMAGE.bin\n";

  int opt = 0;
  while ((opt = getopt_long(argc, argv, "be:w:", table, NULL)) != -1) {
    switch (opt) {
    case 'b':
      sdb_set_batch_mode();
      break;
    case 'e':
      elf_file = optarg;
      break;
    case 'w':
      wave_file = optarg;
      break;
    case 'c':
      max_cycles = strtoull(optarg, NULL, 0);
      break;
    case 'd':
      watchdog_cycles = strtoull(optarg, NULL, 0);
      break;
    default:
      fprintf(stderr, usage, argv[0]);
      return 1;
    }
  }

  if (optind >= argc) {
    fprintf(stderr, usage, argv[0]);
    return 1;
  }

  img_file = argv[optind];

  init_mem();
  img_size = load_img();
#if NPC_FTRACE
  readelf(elf_file);
#endif
  sim_init();
#if NPC_DIFFTEST
  init_difftest(REF_SO_FILE, img_size);
#endif
  sdb_mainloop();
  sim_exit();

  return sim_status();
}
