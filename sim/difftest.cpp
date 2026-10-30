#include "difftest.h"

#include <riscv/cfg.h>
#include <riscv/mmu.h>
#include <riscv/processor.h>
#include <riscv/simif.h>

#include <cstring>
#include <iostream>
#include <map>
#include <memory>
#include <vector>

#include "mem.h"

namespace {

struct Region {
  uint32_t base, size;
  std::vector<char> data;
};

class RefSim : public simif_t {
 public:
  RefSim() {
    add(mem::MROM_BASE, mem::MROM_SIZE, mem::mrom);
    add(mem::SRAM_BASE, mem::SRAM_SIZE, nullptr);
    add(mem::FLASH_BASE, mem::FLASH_SIZE, mem::flash);
    add(mem::PSRAM_BASE, mem::PSRAM_SIZE, nullptr);
    add(mem::SDRAM_BASE, mem::SDRAM_SIZE, nullptr);
    cfg.isa = "rv32e_zicsr_zifencei";
    cfg.priv = "M";
    cfg.pmpregions = 0;
    cfg.mem_layout.clear();
    proc = std::make_unique<processor_t>(cfg.isa, cfg.priv, &cfg, this, 0, false, nullptr, std::cerr);
    harts[0] = proc.get();
  }

  char *addr_to_mem(reg_t paddr) override {
    paddr &= 0xffffffffu;  // RV32 addresses may arrive sign-extended
    for (auto &r : regions)
      if (paddr >= r.base && paddr - r.base < r.size) return &r.data[paddr - r.base];
    return nullptr;
  }
  bool mmio_load(reg_t, size_t, uint8_t *) override { return false; }
  bool mmio_store(reg_t, size_t, const uint8_t *) override { return false; }
  void proc_reset(unsigned) override {}
  const cfg_t &get_cfg() const override { return cfg; }
  const std::map<size_t, processor_t *> &get_harts() const override { return harts; }
  const char *get_symbol(uint64_t) override { return nullptr; }

  cfg_t cfg;
  std::unique_ptr<processor_t> proc;

 private:
  void add(uint32_t base, uint32_t size, const uint8_t *init) {
    Region r{base, size, std::vector<char>(size, 0)};
    if (init) memcpy(r.data.data(), init, size);
    regions.push_back(std::move(r));
  }
  std::vector<Region> regions;
  std::map<size_t, processor_t *> harts;
};

RefSim *ref;

}  // namespace

namespace difftest {

void init(uint32_t reset_pc) {
  ref = new RefSim();
  ref->proc->reset();
  state_t *s = ref->proc->get_state();
  s->pc = reset_pc;
  // Match the DUT reset state of mstatus (MPP hardwired to M).
  ref->proc->put_csr(CSR_MSTATUS, 0x1800);
}

uint32_t pc() { return (uint32_t)ref->proc->get_state()->pc; }

void step() { ref->proc->step(1); }

void sync(const uint32_t *gpr, uint32_t pc) {
  state_t *s = ref->proc->get_state();
  for (int i = 1; i < 16; i++) s->XPR.write(i, (reg_t)(int32_t)gpr[i]);
  s->pc = (reg_t)(int32_t)pc;
}

uint32_t gpr(int i) { return (uint32_t)ref->proc->get_state()->XPR[i]; }

bool is_memory(uint32_t addr) { return ref->addr_to_mem(addr) != nullptr; }

}  // namespace difftest
