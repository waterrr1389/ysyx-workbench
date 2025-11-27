#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include "Vtop.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include "dpi-c.h"

#define MBASE 0x80000000

Vtop* top;
VerilatedContext* contextp;
VerilatedFstC* tfp;
bool sim;

void __step_and_dump_wave();

static const uint32_t img [] = {
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

int getIndex(int pc) {
	return (pc-MBASE) / 4;
}

void fetch_inst() {
    int index = getIndex(top->pc);
    
    // 2. 增加安全检查 (这一步非常重要！)
    // 计算数组元素的总数量
    int max_size = sizeof(img) / sizeof(img[0]);

    if (index >= 0 && index < max_size) {
		printf("Current index is %d\n", index);
        top->inst = img[index];
	} else {
        // 如果 PC 超出范围（比如跑飞了，或者程序结束了）
        // 喂入一个 NOP 指令 (addi x0, x0, 0)，防止仿真器读取非法内存崩溃
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
}

int main(int argc, char** argv) {
	sim_init();
	
	while (sim) {
		step_one_cycle();
	}

	sim_exit();

	return 0;
}
