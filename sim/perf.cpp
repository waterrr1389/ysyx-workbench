#include "perf.h"

#include <cinttypes>
#include <cstdio>
#include <deque>
#include <vector>

namespace perf {
namespace {

// Matches inst_class_e in ysyx_00000000_pkg.sv.
const char *const CLASS_NAMES[] = {"alu", "branch", "jump", "load", "store", "csr", "system"};
constexpr int NUM_CLASSES = sizeof(CLASS_NAMES) / sizeof(CLASS_NAMES[0]);

enum : uint8_t { IREQ = 1, IRESP = 2, DREQ = 4, DWEN = 8, DRESP = 16 };

struct Latency {
  uint64_t count = 0, total = 0;
  void add(uint64_t c) { count++; total += c; }
  double mean() const { return count ? (double)total / count : 0.0; }
};

uint64_t now = 0, start_cycle = 0, last_retire = 0;
uint64_t class_count[NUM_CLASSES], class_cycles[NUM_CLASSES];
Latency fetch;
uint64_t icache_hits = 0, icache_miss_start = 0;
Latency icache_miss;   // from the missing lookup to the end of its refill

// Data accesses are split by target, since their latencies differ by orders of magnitude.
const char *const REGION_NAMES[] = {"sram", "flash", "psram", "sdram", "device"};
constexpr int NUM_REGIONS = sizeof(REGION_NAMES) / sizeof(REGION_NAMES[0]);
Latency load[NUM_REGIONS], store[NUM_REGIONS];
int data_region = 0;

int region_of(uint32_t a) {
  if (a >> 24 == 0x0f) return 0;
  if (a >> 28 == 0x3) return 1;
  if (a >> 24 == 0x80) return 2;
  if (a >> 28 == 0xa) return 3;
  return 4;
}
std::deque<uint64_t> fetch_pending;
uint64_t data_req_cycle = 0;
bool data_is_store = false;

FILE *itrace = nullptr;
// Trace entry for fence.i; fetch addresses are always word aligned.
constexpr uint32_t ITRACE_FLUSH = 1;
std::vector<uint32_t> itrace_buf;

void flush_itrace() {
  if (itrace && !itrace_buf.empty()) fwrite(itrace_buf.data(), 4, itrace_buf.size(), itrace);
  itrace_buf.clear();
}

}  // namespace

void open_itrace(const std::string &path) {
  itrace = fopen(path.c_str(), "wb");
  if (!itrace) perror(path.c_str());
}

void start(uint64_t cycle) {
  now = start_cycle = last_retire = cycle;
}

void retire(uint64_t cycle, int cls) {
  if (cls < 0 || cls >= NUM_CLASSES) return;
  class_count[cls]++;
  class_cycles[cls] += cycle - last_retire;
  last_retire = cycle;
}

void report(uint64_t cycle) {
  uint64_t cycles = cycle - start_cycle, insts = 0;
  for (int i = 0; i < NUM_CLASSES; i++) insts += class_count[i];
  fprintf(stderr, "[perf] cycles %" PRIu64 ", instructions %" PRIu64 ", IPC %.4f\n", cycles, insts,
          cycles ? (double)insts / cycles : 0.0);
  fprintf(stderr, "[perf] %-7s %12s %7s %14s %10s\n", "class", "count", "share", "cycles", "cyc/inst");
  for (int i = 0; i < NUM_CLASSES; i++) {
    if (!class_count[i]) continue;
    fprintf(stderr, "[perf] %-7s %12" PRIu64 " %6.2f%% %14" PRIu64 " %10.2f\n", CLASS_NAMES[i],
            class_count[i], 100.0 * class_count[i] / insts, class_cycles[i],
            (double)class_cycles[i] / class_count[i]);
  }
  fprintf(stderr, "[perf] fetch %" PRIu64 " requests, mean latency %.2f cycles\n", fetch.count, fetch.mean());
  uint64_t lookups = icache_hits + icache_miss.count;
  if (lookups)
    fprintf(stderr, "[perf] icache %" PRIu64 " hits, %" PRIu64 " misses (hit rate %.4f), mean miss penalty %.2f cycles, TMT %" PRIu64 "\n",
            icache_hits, icache_miss.count, (double)icache_hits / lookups, icache_miss.mean(), icache_miss.total);
  for (int i = 0; i < NUM_REGIONS; i++) {
    if (load[i].count)
      fprintf(stderr, "[perf] load  %-6s %10" PRIu64 " requests, mean latency %.2f cycles\n", REGION_NAMES[i],
              load[i].count, load[i].mean());
    if (store[i].count)
      fprintf(stderr, "[perf] store %-6s %10" PRIu64 " requests, mean latency %.2f cycles\n", REGION_NAMES[i],
              store[i].count, store[i].mean());
  }
}

void close() {
  flush_itrace();
  if (itrace) fclose(itrace);
  itrace = nullptr;
}

}  // namespace perf

// Called from SimHook in the cycle the events happen; the cycle number is tracked by sim_tick.
extern "C" void sim_mem_event(char events, int imem_addr, int dmem_addr) {
  using namespace perf;
  uint8_t e = events;
  if (e & IRESP) {
    if (!fetch_pending.empty()) {
      fetch.add(now - fetch_pending.front());
      fetch_pending.pop_front();
    }
  }
  if (e & IREQ) {
    fetch_pending.push_back(now);
    if (itrace) {
      itrace_buf.push_back((uint32_t)imem_addr);
      if (itrace_buf.size() >= (1u << 16)) flush_itrace();
    }
  }
  if (e & DRESP) (data_is_store ? store : load)[data_region].add(now - data_req_cycle);
  if (e & DREQ) {
    data_req_cycle = now;
    data_is_store = e & DWEN;
    data_region = region_of((uint32_t)dmem_addr);
  }
}

namespace perf {
void tick(uint64_t cycle) { now = cycle; }
}

extern "C" void sim_icache_event(char ev) {
  using namespace perf;
  if (ev == 0) icache_hits++;
  else if (ev == 1) icache_miss_start = now;
  else if (ev == 2) icache_miss.add(now - icache_miss_start + 1);
  else if (itrace) itrace_buf.push_back(ITRACE_FLUSH);
}
