#include "sim_main.h"
#include "Vtop.h"
#include "verilated.h"
#include "verilated_fst_c.h"

#include <cstdint>

namespace {
constexpr uint32_t kMbase = 0x80000000u;
constexpr uint32_t kNopInst = 0x00000013u;
constexpr uint32_t kBuiltinImg[] = {
    // 为了证明清除效果，我们先故意把几个寄存器弄脏 (设置成非0值)
    0x00100093, // addi x1, x0, 1   (x1 = 1)
    0x00200113, // addi x2, x0, 2   (x2 = 2)
    0x00300f93, // addi x31, x0, 3  (x31 = 3)

    // --- 开始清理 (Clear x1 - x31) ---
    // 机器码生成公式: (rd << 7) | 0x13
    0x00000093, // addi x1,  x0, 0
    0x00000113, // addi x2,  x0, 0
    0x00000193, // addi x3,  x0, 0
    0x00000213, // addi x4,  x0, 0
    0x00000293, // addi x5,  x0, 0
    0x00000313, // addi x6,  x0, 0
    0x00000393, // addi x7,  x0, 0
    0x00000413, // addi x8,  x0, 0
    0x00000493, // addi x9,  x0, 0
    0x00000513, // addi x10, x0, 0
    0x00000593, // addi x11, x0, 0
    0x00000613, // addi x12, x0, 0
    0x00000693, // addi x13, x0, 0
    0x00000713, // addi x14, x0, 0
    0x00000793, // addi x15, x0, 0
    0x00000813, // addi x16, x0, 0
    0x00000893, // addi x17, x0, 0
    0x00000913, // addi x18, x0, 0
    0x00000993, // addi x19, x0, 0
    0x00000a13, // addi x20, x0, 0
    0x00000a93, // addi x21, x0, 0
    0x00000b13, // addi x22, x0, 0
    0x00000b93, // addi x23, x0, 0
    0x00000c13, // addi x24, x0, 0
    0x00000c93, // addi x25, x0, 0
    0x00000d13, // addi x26, x0, 0
    0x00000d93, // addi x27, x0, 0
    0x00000e13, // addi x28, x0, 0
    0x00000e93, // addi x29, x0, 0
    0x00000f13, // addi x30, x0, 0
    0x00000f93, // addi x31, x0, 0
    0x00100073  // ebreak
};

Vtop *top = nullptr;
VerilatedContext *contextp = nullptr;
VerilatedFstC *tfp = nullptr;
bool sim_running = false;

int pc_to_index(uint32_t pc) { return static_cast<int>((pc - kMbase) / 4u); }

void fetch_inst() {
  const int index = pc_to_index(top->pc);
  const int img_size =
      static_cast<int>(sizeof(kBuiltinImg) / sizeof(kBuiltinImg[0]));

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

bool is_sim_running() { return sim_running; }

void stop_simulation() { sim_running = false; }

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
