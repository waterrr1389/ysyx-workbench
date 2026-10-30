#include <verilated.h>

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "VysyxSoCFull.h"
#include "difftest.h"
#include "mem.h"

#ifdef TRACE
#include <verilated_fst_c.h>
#endif

namespace {

struct Retire {
  uint32_t pc, wdata, mem_addr;
  uint8_t rd, rd_wen, trap, ebreak, skip, mem_access;
};

std::vector<Retire> retired;

constexpr uint32_t RESET_PC = 0x30000000;
constexpr uint64_t WATCHDOG = 1000000;  // cycles without a retirement before giving up

struct Options {
  std::string mrom, flash, wave;
  bool difftest = false;
  uint64_t max_cycles = 2000000000ull;
};

void usage(const char *prog) {
  fprintf(stderr,
          "usage: %s [--mrom IMG] [--flash IMG] [--difftest] [--max-cycles N] [--wave FILE]\n", prog);
  exit(2);
}

Options parse(int argc, char **argv) {
  Options o;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&]() -> std::string {
      if (i + 1 >= argc) usage(argv[0]);
      return argv[++i];
    };
    if (a == "--mrom") o.mrom = next();
    else if (a == "--flash") o.flash = next();
    else if (a == "--difftest") o.difftest = true;
    else if (a == "--max-cycles") o.max_cycles = strtoull(next().c_str(), nullptr, 0);
    else if (a == "--wave") o.wave = next();
    else if (a.rfind("+", 0) == 0) continue;  // plusargs are for Verilator
    else usage(argv[0]);
  }
  return o;
}

}  // namespace

extern "C" void sim_retire(int pc, char rd, char rd_wen, int wdata, char trap, char ebreak, char skip,
                           char mem_access, int mem_addr) {
  retired.push_back(Retire{(uint32_t)pc, (uint32_t)wdata, (uint32_t)mem_addr, (uint8_t)rd,
                           (uint8_t)rd_wen, (uint8_t)trap, (uint8_t)ebreak, (uint8_t)skip,
                           (uint8_t)mem_access});
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Options opt = parse(argc, argv);
  if (!opt.mrom.empty()) mem::load(opt.mrom, mem::mrom, mem::MROM_SIZE);
  if (!opt.flash.empty()) mem::load(opt.flash, mem::flash, mem::FLASH_SIZE);

  auto *top = new VysyxSoCFull;
#ifdef TRACE
  VerilatedFstC *tfp = nullptr;
  if (!opt.wave.empty()) {
    Verilated::traceEverOn(true);
    tfp = new VerilatedFstC;
    top->trace(tfp, 99);
    tfp->open(opt.wave.c_str());
  }
#endif
  uint64_t cycle = 0;
  auto tick = [&]() {
    top->clock = 0;
    top->eval();
#ifdef TRACE
    if (tfp) tfp->dump(cycle * 2);
#endif
    top->clock = 1;
    top->eval();
#ifdef TRACE
    if (tfp) tfp->dump(cycle * 2 + 1);
#endif
    cycle++;
  };

  top->reset = 1;
  for (int i = 0; i < 20; i++) tick();
  top->reset = 0;
  retired.clear();
  cycle = 0;

  if (opt.difftest) difftest::init(RESET_PC);

  uint32_t gpr[16] = {0};
  uint64_t insts = 0, last_retire = 0;
  int status = -1;  // -1 running, 0 good trap, 1 failure
  std::string reason;

  while (status < 0) {
    if (cycle >= opt.max_cycles) {
      status = 1;
      reason = "cycle limit reached";
      break;
    }
    tick();
    if (Verilated::gotFinish()) {
      status = 1;
      reason = "$finish in RTL";
      break;
    }
    if (retired.empty()) {
      if (cycle - last_retire > WATCHDOG) {
        status = 1;
        reason = "no instruction retired for too long";
      }
      continue;
    }
    last_retire = cycle;
    for (const Retire &r : retired) {
      if (opt.difftest && difftest::pc() != r.pc) {
        fprintf(stderr, "difftest: pc mismatch, dut 0x%08x ref 0x%08x\n", r.pc, difftest::pc());
        status = 1;
        reason = "difftest failure";
        break;
      }
      if (r.ebreak) {
        status = gpr[10] == 0 ? 0 : 1;
        reason = gpr[10] == 0 ? "HIT GOOD TRAP" : "HIT BAD TRAP";
        insts++;
        break;
      }
      if (r.rd_wen) gpr[r.rd] = r.wdata;
      insts++;
      if (!opt.difftest) continue;
      bool device = r.mem_access && !difftest::is_memory(r.mem_addr);
      if (r.skip || (device && !r.trap)) {
        difftest::sync(gpr, r.pc + 4);
        continue;
      }
      difftest::step();
      for (int i = 1; i < 16; i++) {
        if (difftest::gpr(i) != gpr[i]) {
          fprintf(stderr, "difftest: after pc 0x%08x x%d dut 0x%08x ref 0x%08x\n", r.pc, i, gpr[i],
                  difftest::gpr(i));
          status = 1;
          reason = "difftest failure";
        }
      }
      if (status >= 0) break;
    }
    retired.clear();
  }

#ifdef TRACE
  if (tfp) tfp->close();
#endif
  fflush(stdout);
  fprintf(stderr, "\n[sim] %s at cycle %" PRIu64 ", %" PRIu64 " instructions, IPC %.4f\n", reason.c_str(),
          cycle, insts, cycle ? (double)insts / cycle : 0.0);
  top->final();
  delete top;
  return status;
}
