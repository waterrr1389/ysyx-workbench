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
  // Bump allocator: nothing is ever freed. Every block starts on an 8-byte
  // boundary so it is suitably aligned for any built-in type.
  static char *addr = NULL;
  if (addr == NULL) addr = (char *)ROUNDUP(heap.start, 8);
  size = ROUNDUP(size, 8);
  if (size > (size_t)((char *)heap.end - addr)) return NULL;
  void *ret = addr;
  addr += size;
  return ret;
}

void free(void *ptr) {
}

#endif
