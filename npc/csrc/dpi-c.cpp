#include <stdio.h>
#include "dpi-c.h"
extern bool sim;

void ebreak() {
    sim = false;
}

// void display_reg(int regs[]) {
//     for (int i = 1; i < 31; i++) {
//         printf("$%d=%d\n", i, regs[i]);
//     }
// }