#include <stdio.h>
#include "svdpi.h"
#include "dpi-c.h"
extern bool sim;

void npc_trap() {
    sim = false;
}