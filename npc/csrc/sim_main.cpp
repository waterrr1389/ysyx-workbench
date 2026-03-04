#include "sim_main.h"
#include "Vtop.h"
#include "verilated.h"
#include "verilated_fst_c.h"

#include <cstdint>

namespace {
constexpr uint32_t kMbase = 0x80000000u;
constexpr uint32_t kNopInst = 0x00000013u;
constexpr uint32_t kBuiltinImg[] = {
    kNopInst,
    0x00000073u, // ebreak
};

Vtop *top = nullptr;
VerilatedContext *contextp = nullptr;
VerilatedFstC *tfp = nullptr;
bool sim_running = false;

int pc_to_index(uint32_t pc) {
  return static_cast<int>((pc - kMbase) / 4u);
}

void fetch_inst() {
  const int index = pc_to_index(top->pc);
  const int img_size = static_cast<int>(sizeof(kBuiltinImg) / sizeof(kBuiltinImg[0]));

  if (index >= 0 && index < img_size) {
    top->inst = kBuiltinImg[index];
    return;
  }

  // PC 越界时喂 NOP，避免访问非法地址导致仿真崩溃
  top->inst = kNopInst;
}

void step_and_dump_wave() {
  top->eval();
  contextp->timeInc(1);
  tfp->dump(contextp->time());
  top->clk = !top->clk;
}
} // namespace

bool is_sim_running() {
  return sim_running;
}

void stop_simulation() {
  sim_running = false;
}

void step_one_cycle() {
  if (!sim_running) {
    return;
  }
  fetch_inst();
  step_and_dump_wave();
  step_and_dump_wave();
}

void sim_init() {
  contextp = new VerilatedContext;
  top = new Vtop{contextp};
  tfp = new VerilatedFstC;
  Verilated::traceEverOn(true);

  top->trace(tfp, 99);
  tfp->open("waveform.fst");

  top->reset = 1;
  top->clk = 0;
  top->inst = 0;
  sim_running = true;

  for (int i = 0; i < 11; ++i) {
    step_and_dump_wave();
  }
  top->reset = 0;
}

void sim_exit() {
  if (tfp != nullptr) {
    tfp->close();
    delete tfp;
    tfp = nullptr;
  }
  delete top;
  top = nullptr;
  delete contextp;
  contextp = nullptr;
  sim_running = false;
}

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;

  sim_init();
  while (is_sim_running()) {
    step_one_cycle();
  }
  sim_exit();

  return 0;
}
