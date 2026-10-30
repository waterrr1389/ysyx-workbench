#pragma once
#include <cstdint>
#include <cstddef>
#include <string>

// Backing storage the SoC models read through DPI-C, plus the address map shared with DiffTest.
namespace mem {

constexpr uint32_t MROM_BASE  = 0x20000000, MROM_SIZE  = 0x1000;
constexpr uint32_t SRAM_BASE  = 0x0f000000, SRAM_SIZE  = 0x2000;
constexpr uint32_t FLASH_BASE = 0x30000000, FLASH_SIZE = 0x1000000;
constexpr uint32_t PSRAM_BASE = 0x80000000, PSRAM_SIZE = 0x400000;
constexpr uint32_t SDRAM_BASE = 0xa0000000, SDRAM_SIZE = 0x2000000;

extern uint8_t mrom[MROM_SIZE];
extern uint8_t flash[FLASH_SIZE];

// Loads a raw binary into the given storage; returns its size or exits on error.
size_t load(const std::string &path, uint8_t *dst, size_t cap);

}  // namespace mem
