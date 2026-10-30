#include "mem.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace mem {

uint8_t mrom[MROM_SIZE];
uint8_t flash[FLASH_SIZE];

size_t load(const std::string &path, uint8_t *dst, size_t cap) {
  FILE *fp = fopen(path.c_str(), "rb");
  if (!fp) {
    fprintf(stderr, "cannot open image %s\n", path.c_str());
    exit(1);
  }
  fseek(fp, 0, SEEK_END);
  size_t size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (size > cap) {
    fprintf(stderr, "image %s (%zu bytes) exceeds %zu bytes\n", path.c_str(), size, cap);
    exit(1);
  }
  if (fread(dst, 1, size, fp) != size) {
    fprintf(stderr, "short read on %s\n", path.c_str());
    exit(1);
  }
  fclose(fp);
  return size;
}

}  // namespace mem

extern "C" void mrom_read(int32_t addr, int32_t *data) {
  uint32_t off = ((uint32_t)addr - mem::MROM_BASE) & (mem::MROM_SIZE - 1) & ~3u;
  memcpy(data, &mem::mrom[off], 4);
}

extern "C" void flash_read(int32_t addr, int32_t *data) {
  uint32_t off = (uint32_t)addr & (mem::FLASH_SIZE - 1) & ~3u;
  memcpy(data, &mem::flash[off], 4);
}
