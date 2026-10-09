#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)
static unsigned long int next = 1;

int rand(void) {
  // RAND_MAX assumed to be 32767
  next = next * 1103515245 + 12345;
  return (unsigned int)(next/65536) % 32768;
}

void srand(unsigned int seed) {
  next = seed;
}

int abs(int x) {
  return (x < 0 ? -x : x);
}

int atoi(const char* nptr) {
  int x = 0;
  while (*nptr == ' ') { nptr ++; }
  while (*nptr >= '0' && *nptr <= '9') {
    x = x * 10 + *nptr - '0';
    nptr ++;
  }
  return x;
}

void *malloc(size_t size) {
  // On native, malloc() will be called during initializaion of C runtime.
  // Therefore do not call panic() here, else it will yield a dead recursion:
  //   panic() -> putchar() -> (glibc) -> malloc() -> panic()
  // Bump allocator: nothing is ever freed. Every block is aligned to
  // max_align_t, which suits any object type that fits in it.
  static char *addr = NULL;
  if (addr == NULL) addr = (char *)ROUNDUP(heap.start, _Alignof(max_align_t));
  // Check before rounding: ROUNDUP wraps to 0 for sizes near SIZE_MAX.
  size_t avail = (char *)heap.end - addr;
  if (size > avail) return NULL;
  // size 0 still takes a slot so the returned pointer stays unique.
  size = ROUNDUP(size == 0 ? 1 : size, _Alignof(max_align_t));
  if (size > avail) return NULL;
  void *ret = addr;
  addr += size;
  return ret;
}

void free(void *ptr) {
}

#endif
