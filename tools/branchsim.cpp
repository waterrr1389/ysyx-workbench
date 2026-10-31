// Trace-driven branch predictor model for the fetch stage. The predictor only sees the fetch PC, so a
// taken prediction needs a BTB hit for its target. Replays a --btrace (pairs of PC and next PC, bit 0
// of the next PC set for conditional branches) and counts mispredictions.
//
// usage: branchsim TRACE POLICY ENTRIES [SPAN_W]
//   POLICY: nt     always not taken
//           btb    taken whenever the BTB hits
//           btfn   BTB hit: jumps taken, branches taken when backward
//           bimod  BTB hit: jumps taken, branches by a 2-bit counter in the entry
//   ENTRIES: direct-mapped BTB entries (power of two). SPAN_W (default 32): tags and targets keep
//   PC bits below it, the predicted target takes the upper bits from the PC. Aliasing between control
//   flow instructions is modeled; aliasing with other instructions is not (the trace holds none), so
//   SPAN_W must cover the program's code.
//   Only taken control flow allocates an entry.
//   TRACE may be "-" for stdin, or a .zst file that is decompressed with zstd.
// Output: one line "policy entries span_w branches jumps mispredicts".
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

int main(int argc, char **argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: %s TRACE nt|btb|btfn|bimod ENTRIES [SPAN_W]\n", argv[0]);
    return 2;
  }
  size_t len = strlen(argv[1]);
  FILE *fp = strcmp(argv[1], "-") == 0 ? stdin
           : len > 4 && strcmp(argv[1] + len - 4, ".zst") == 0
               ? popen((std::string("zstd -dcq '") + argv[1] + "'").c_str(), "r")
               : fopen(argv[1], "rb");
  if (!fp) { perror(argv[1]); return 2; }
  const std::string policy = argv[2];
  const uint32_t entries = atoi(argv[3]);
  if (!entries || (entries & (entries - 1))) { fprintf(stderr, "ENTRIES must be a power of two\n"); return 2; }
  int idx_bits = __builtin_ctz(entries);
  const int span = argc > 4 ? atoi(argv[4]) : 32;
  const uint32_t low = span >= 32 ? ~0u : (1u << span) - 1;

  struct Entry { bool valid; uint32_t tag, target; bool branch; uint8_t ctr; };
  std::vector<Entry> btb(entries, Entry{false, 0, 0, false, 0});
  uint64_t branches = 0, jumps = 0, miss = 0;

  std::vector<uint32_t> buf(1 << 16);
  size_t n;
  while ((n = fread(buf.data(), 8, buf.size() / 2, fp)) > 0) {
    for (size_t i = 0; i < n; i++) {
      uint32_t pc = buf[2 * i], next = buf[2 * i + 1] & ~1u;
      bool is_branch = buf[2 * i + 1] & 1;
      bool taken = next != pc + 4;
      (is_branch ? branches : jumps)++;
      uint32_t idx = (pc >> 2) & (entries - 1), tag = (pc & low) >> (2 + idx_bits);
      Entry &e = btb[idx];
      bool hit = e.valid && e.tag == tag;

      uint32_t pred = pc + 4;
      if (hit && policy != "nt") {
        bool t = !e.branch || policy == "btb" ||
                 (policy == "btfn" && e.target < pc) || (policy == "bimod" && e.ctr >= 2);
        if (t) pred = (pc & ~low) | (e.target & low);
      }
      if (pred != next) miss++;

      if (hit) {
        if (taken) e.target = next;
        e.branch = is_branch;
        if (taken && e.ctr < 3) e.ctr++;
        if (!taken && e.ctr > 0) e.ctr--;
      } else if (taken) {
        e = Entry{true, tag, next, is_branch, 2};
      }
    }
  }
  printf("%s %u %d %llu %llu %llu\n", policy.c_str(), entries, span, (unsigned long long)branches,
         (unsigned long long)jumps, (unsigned long long)miss);
  return 0;
}
