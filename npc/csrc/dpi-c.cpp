#include "dpi-c.h"
#include "sim_main.h"

void ebreak() {
  stop_simulation();
}

// void display_reg(int regs[]) {
//     for (int i = 1; i < 31; i++) {
//         printf("$%d=%d\n", i, regs[i]);
//     }
// }
