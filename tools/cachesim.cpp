// Trace-driven icache model: replays fetch addresses (little-endian uint32, as written by the
// simulator's --itrace) through a set-associative cache and counts misses. Only metadata is kept.
//
// usage: cachesim TRACE BLOCK_BYTES SETS WAYS [lru|fifo|random]
//   TRACE may be "-" for stdin, so compressed traces can be piped in. The entry 1 marks fence.i,
//   which invalidates the whole cache.
// Output: one line "block sets ways policy accesses misses".
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "usage: %s TRACE BLOCK_BYTES SETS WAYS [lru|fifo|random]\n", argv[0]);
    return 2;
  }
  FILE *fp = strcmp(argv[1], "-") == 0 ? stdin : fopen(argv[1], "rb");
  if (!fp) { perror(argv[1]); return 2; }
  const uint32_t block = atoi(argv[2]), sets = atoi(argv[3]), ways = atoi(argv[4]);
  const char *policy = argc > 5 ? argv[5] : "lru";
  enum { LRU, FIFO, RANDOM } pol = !strcmp(policy, "fifo") ? FIFO : !strcmp(policy, "random") ? RANDOM : LRU;
  if (block < 4 || (block & (block - 1)) || !sets || (sets & (sets - 1)) || !ways) {
    fprintf(stderr, "block and sets must be powers of two, block >= 4\n");
    return 2;
  }

  struct Line { uint32_t tag; bool valid; uint64_t stamp; };
  std::vector<Line> lines((size_t)sets * ways, Line{0, false, 0});
  uint64_t accesses = 0, misses = 0, now = 0;
  uint32_t rng = 1;

  std::vector<uint32_t> buf(1 << 16);
  size_t n;
  while ((n = fread(buf.data(), 4, buf.size(), fp)) > 0) {
    for (size_t i = 0; i < n; i++) {
      if (buf[i] == 1) {
        for (Line &x : lines) x.valid = false;
        continue;
      }
      uint32_t blk = buf[i] / block, set = blk & (sets - 1), tag = blk / sets;
      Line *l = &lines[(size_t)set * ways];
      accesses++;
      now++;
      int hit = -1;
      for (uint32_t w = 0; w < ways; w++)
        if (l[w].valid && l[w].tag == tag) { hit = w; break; }
      if (hit >= 0) {
        if (pol == LRU) l[hit].stamp = now;
        continue;
      }
      misses++;
      uint32_t victim = 0;
      for (uint32_t w = 0; w < ways; w++) if (!l[w].valid) { victim = w; goto fill; }
      if (pol == RANDOM) {
        rng = rng * 1103515245u + 12345u;
        victim = (rng >> 16) % ways;
      } else {
        for (uint32_t w = 1; w < ways; w++) if (l[w].stamp < l[victim].stamp) victim = w;
      }
    fill:
      l[victim] = Line{tag, true, now};
    }
  }
  printf("%u %u %u %s %llu %llu\n", block, sets, ways, policy, (unsigned long long)accesses,
         (unsigned long long)misses);
  return 0;
}
