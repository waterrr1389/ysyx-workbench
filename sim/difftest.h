#pragma once
#include <cstdint>

// Reference model for DiffTest: Spike's processor_t over the SoC's memory map.
namespace difftest {

void init(uint32_t reset_pc);
uint32_t pc();
// Executes one instruction on the reference model.
void step();
// Overwrites the reference GPRs and PC (used after instructions the reference cannot replay).
void sync(const uint32_t *gpr, uint32_t pc);
uint32_t gpr(int i);
// True when the address is backed by memory in the reference model.
bool is_memory(uint32_t addr);

}  // namespace difftest
