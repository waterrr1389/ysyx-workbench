#ifndef NEMU_DIFFTEST_REFERENCE_HPP
#define NEMU_DIFFTEST_REFERENCE_HPP

#include <difftest/arch/riscv32.h>

#include <cstddef>
#include <cstdint>

namespace difftest {

class Riscv32DifftestReference {
public:
  explicit Riscv32DifftestReference(const char *library_path);
  ~Riscv32DifftestReference();

  Riscv32DifftestReference(const Riscv32DifftestReference &) = delete;
  Riscv32DifftestReference &operator=(const Riscv32DifftestReference &) = delete;
  Riscv32DifftestReference(Riscv32DifftestReference &&) = delete;
  Riscv32DifftestReference &operator=(Riscv32DifftestReference &&) = delete;

  void initialize(int port, uint32_t reset_vector, const void *image, size_t image_size,
                  const riscv32_difftest_state_t &initial_state);
  void copy_memory_to_reference(uint32_t address, const void *data, size_t size);
  void set_state(const riscv32_difftest_state_t &state);
  riscv32_difftest_state_t get_state();
  riscv32_difftest_state_t step();
  void execute(uint64_t count);
  void raise_interrupt(uint64_t cause);

private:
  using QueryU32 = uint32_t (*)(void);
  using MemoryCopy = void (*)(uint32_t, void *, size_t, bool);
  using Execute = void (*)(uint64_t);
  using RaiseInterrupt = void (*)(uint64_t);
  using Initialize = void (*)(int);

  template <typename Symbol> Symbol load_symbol(const char *name) {
    return reinterpret_cast<Symbol>(load_symbol_address(name));
  }

  void *load_symbol_address(const char *name);

  void *handle_ = nullptr;
  MemoryCopy memory_copy_ = nullptr;
  riscv32_difftest_regcpy_t register_copy_ = nullptr;
  Execute execute_ = nullptr;
  RaiseInterrupt raise_interrupt_ = nullptr;
  Initialize initialize_ = nullptr;
};

} // namespace difftest

#endif
