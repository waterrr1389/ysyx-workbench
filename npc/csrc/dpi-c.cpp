#include <stdio.h>
#include "dpi-c.h"
extern bool sim;

void npc_trap() {
    sim = false;
}

void info_reg(int reg) {

}