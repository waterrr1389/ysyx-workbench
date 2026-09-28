#include <difftest/reference.hpp>

#include <dlfcn.h>

#include <cstdio>
#include <cstdlib>
#include <string>

namespace difftest {

[[noreturn]] static void fail(const std::string &message) {
  fprintf(stderr, "DiffTest client error: %s\n", message.c_str());
  abort();
}

Riscv32DifftestReference::Riscv32DifftestReference(const char *library_path) {
  if (library_path == nullptr) {
    fail("reference path must not be null");
  }

  handle_ = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
  if (handle_ == nullptr) {
    const char *error = dlerror();
    fail("failed to load reference '" + std::string(library_path) +
         "': " + (error == nullptr ? "unknown dlopen error" : error));
  }

  QueryU32 get_abi_version = load_symbol<QueryU32>("difftest_get_abi_version");
  QueryU32 get_state_size = load_symbol<QueryU32>("difftest_get_state_size");
  memory_copy_ = load_symbol<MemoryCopy>("difftest_memcpy");
  register_copy_ = load_symbol<riscv32_difftest_regcpy_t>("difftest_regcpy");
  execute_ = load_symbol<Execute>("difftest_exec");
  raise_interrupt_ = load_symbol<RaiseInterrupt>("difftest_raise_intr");
  initialize_ = load_symbol<Initialize>("difftest_init");

  uint32_t abi_version = get_abi_version();
  if (abi_version != RISCV32_DIFFTEST_ABI_VERSION) {
    fail("RV32 ABI version mismatch: expected " + std::to_string(RISCV32_DIFFTEST_ABI_VERSION) +
         ", got " + std::to_string(abi_version));
  }

  uint32_t state_size = get_state_size();
  if (state_size != sizeof(riscv32_difftest_state_t)) {
    fail("RV32 state size mismatch: expected " + std::to_string(sizeof(riscv32_difftest_state_t)) +
         ", got " + std::to_string(state_size));
  }
}

Riscv32DifftestReference::~Riscv32DifftestReference() {
  if (handle_ != nullptr) {
    dlclose(handle_);
  }
}

void Riscv32DifftestReference::initialize(int port, uint32_t reset_vector, const void *image,
                                          size_t image_size,
                                          const riscv32_difftest_state_t &initial_state) {
  initialize_(port);
  copy_memory_to_reference(reset_vector, image, image_size);
  set_state(initial_state);
}

void Riscv32DifftestReference::copy_memory_to_reference(uint32_t address, const void *data,
                                                        size_t size) {
  if (data == nullptr && size != 0) {
    fail("memory source must not be null when size is nonzero");
  }
  memory_copy_(address, const_cast<void *>(data), size, true);
}

void Riscv32DifftestReference::set_state(const riscv32_difftest_state_t &state) {
  riscv32_difftest_state_t copy = state;
  register_copy_(&copy, RISCV32_DIFFTEST_TO_REF);
}

riscv32_difftest_state_t Riscv32DifftestReference::get_state() {
  riscv32_difftest_state_t state = {};
  register_copy_(&state, RISCV32_DIFFTEST_TO_DUT);
  return state;
}

riscv32_difftest_state_t Riscv32DifftestReference::step() {
  execute(1);
  return get_state();
}

void Riscv32DifftestReference::execute(uint64_t count) {
  execute_(count);
}

void Riscv32DifftestReference::raise_interrupt(uint64_t cause) {
  raise_interrupt_(cause);
}

void *Riscv32DifftestReference::load_symbol_address(const char *name) {
  dlerror();
  void *symbol = dlsym(handle_, name);
  const char *error = dlerror();
  if (error != nullptr) {
    fail("missing symbol '" + std::string(name) + "': " + error);
  }
  return symbol;
}

} // namespace difftest
