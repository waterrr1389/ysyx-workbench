// Self-modifying code: each check rewrites an instruction that is already cached or already fetched,
// executes fence.i, and requires the new instruction to run.
#include <am.h>
#include <klib.h>
#include <klib-macros.h>

// addi a0, zero, v
static uint32_t li_a0(int v) { return ((uint32_t)v << 20) | (10u << 7) | 0x13u; }

// The instruction after fence.i is rewritten by the store just before it, so it has been fetched
// before the store takes effect; only the pipeline flush after fence.i makes the new one run.
__attribute__((noinline)) static int patch_next(uint32_t insn) {
  register int a0 asm("a0");
  asm volatile(
      "la t0, 1f\n"
      "sw %1, 0(t0)\n"
      "fence.i\n"
      "1: addi a0, zero, 0\n"
      : "=r"(a0)
      : "r"(insn)
      : "t0", "memory");
  return a0;
}

// A function body that is called, then rewritten; its old version stays in the icache unless
// fence.i invalidates it.
__attribute__((aligned(16))) static uint32_t func[2] = {0x00000513 /* li a0, 0 */, 0x00008067 /* ret */};

static int call_func(void) { return ((int (*)(void))func)(); }

int main(const char *args) {
  int fail = 0;
  for (int v = 1; v <= 8; v++) {
    int got = patch_next(li_a0(v));
    if (got != v) { printf("patch_next: expected %d, got %d\n", v, got); fail = 1; }
  }
  for (int v = 1; v <= 8; v++) {
    call_func();                 // makes sure the current version is cached
    func[0] = li_a0(v);
    asm volatile("fence.i" ::: "memory");
    int got = call_func();
    if (got != v) { printf("call_func: expected %d, got %d\n", v, got); fail = 1; }
  }
  printf("fence.i test %s\n", fail ? "FAIL" : "PASS");
  return fail;
}
