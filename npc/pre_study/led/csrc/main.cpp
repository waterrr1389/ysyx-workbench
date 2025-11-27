#include <nvboard.h>
#include <Vtop.h>

//TOP_NAME 会在编译时传入-DTOP_NAME进行替换
static TOP_NAME dut;

void nvboard_bind_all_pins(TOP_NAME* top);

static void single_cycle() {
    dut.clk = 1;
    dut.eval();
    dut.clk = 0;
    dut.eval();
}

void reset(int n) {
  dut.rst = 1;
  while (n -- > 0) single_cycle();
  dut.rst = 0;
}

int main() {
    nvboard_bind_all_pins(&dut);
    nvboard_init();

    reset(10);

    while (true) {
        nvboard_update();
        single_cycle();
    }

    nvboard_quit();
}