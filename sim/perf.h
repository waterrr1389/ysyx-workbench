#pragma once
#include <cstdint>
#include <string>

// Simulation-side performance counters fed by the RTL SimHook.
namespace perf {

// Starts writing every instruction fetch address (little-endian uint32) to `path`.
void open_itrace(const std::string &path);
// Counters start from zero at the cycle given here (end of reset).
void start(uint64_t cycle);
void tick(uint64_t cycle);  // current cycle, called before each clock edge
void retire(uint64_t cycle, int cls);
void report(uint64_t cycle);
void close();

}  // namespace perf
