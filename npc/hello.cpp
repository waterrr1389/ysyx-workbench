#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "Vtop.h"
#include "verilated.h"
// #include "verilated_vcd_c.h"
#include "verilated_fst_c.h"

int main(int argc, char** argv) {
	//create context
	VerilatedContext* contextp = new VerilatedContext;
	//pass arguments
	contextp->commandArgs(argc, argv);

	//create a model
	Vtop* top = new Vtop{contextp};
	//
	VerilatedFstC* tfp = new VerilatedFstC;

	Verilated::traceEverOn(true);

	// Trace 99 levels of hierarchy 
	top->trace(tfp, 99); 
	tfp->open("waveform.fst");

	//emulation
	int times = 1000;
	while (times--) {
		contextp->timeInc(1);
		int a = rand() & 1;
		int b = rand() & 1;
		top->a = a;
		top->b = b;
		top->eval();
		printf("a = %d, b = %d, f = %d\n", a, b, top->f);
		assert(top->f == (a ^ b));
		tfp->dump(contextp->time());
	}

	//
	tfp->close();
	delete top;
	delete contextp;
	return 0;
}
