#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <stdint.h>
#include "Vtop.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include "dpi-c.h"
#include "sim_main.h"

#define MBASE 0x80000000

Vtop* top;
VerilatedContext* contextp;
VerilatedFstC* tfp;
bool sim;
static const char *img_file = NULL;
static uint8_t *img_buf = NULL;
static long img_size = 0;

long load_img() {
	if (img_file == NULL) {
		fprintf(stderr, "Error: no image is given.\n");
		exit(1);
	}

	FILE *fp = fopen(img_file, "rb");
	if (fp == NULL) {
		fprintf(stderr, "Error: can not open '%s'\n", img_file);
		exit(1);
	}

	fseek(fp, 0, SEEK_END);
	long size = ftell(fp);
	assert(size >= 0);
	fseek(fp, 0, SEEK_SET);

	img_buf = (uint8_t *)malloc(size);
	assert(img_buf != NULL);

	size_t ret = fread(img_buf, 1, size, fp);
	assert(ret == (size_t)size);
	fclose(fp);

	printf("The image is %s, size = %ld\n", img_file, size);
	return size;
}

int getIndex(int pc) {
	return (pc-MBASE) / 4;
}

void fetch_inst() {
    int index = getIndex(top->pc);

    long byte_index = (long)index * 4;
    if (index >= 0 && byte_index + 4 <= img_size) {
		printf("Current index is %d\n", index);
        top->inst = (uint32_t)img_buf[byte_index] |
                    ((uint32_t)img_buf[byte_index + 1] << 8) |
                    ((uint32_t)img_buf[byte_index + 2] << 16) |
                    ((uint32_t)img_buf[byte_index + 3] << 24);
	} else {
        top->inst = 0x00000013; 
	}
}

void step_and_dump_wave() {
	top->eval();
	contextp->timeInc(1);
	tfp->dump(contextp->time());
	top->clk = !top->clk;
}

void step_one_cycle() {
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
	sim = true;
	// reset
	// 5 cycles
	for (int i = 11; i > 0; i--) {
		step_and_dump_wave();
	}
	top->reset = 0;
}

void sim_exit() {
	tfp->close();
	delete top;
	delete contextp;
	free(img_buf);
}

int main(int argc, char** argv) {
	if (argc < 2) {
		fprintf(stderr, "Usage: %s <image_file>\n", argv[0]);
		return 1;
	}
	img_file = argv[1];
	img_size = load_img();

	sim_init();

	while (sim) {
		step_one_cycle();
	}

	sim_exit();

	return 0;
}
