#pragma once

class Vtop;
class VerilatedContext;
class VerilatedFstC;

extern Vtop* top;
extern VerilatedContext* contextp;
extern VerilatedFstC* tfp;
extern bool sim;

void __step_and_dump_wave();

long load_img();
int getIndex(int pc);
void fetch_inst();
void step_and_dump_wave();
void step_one_cycle();
void sim_init();
void sim_exit();
