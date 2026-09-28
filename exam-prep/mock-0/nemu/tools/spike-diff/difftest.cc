/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "mmu.h"
#include "processor.h"
#include "sim.h"
#include "../../include/common.h"
#include <difftest-def.h>
#include <cassert>
#include <cstdio>
#include <cstdlib>

static std::vector<std::pair<reg_t, abstract_device_t*>> difftest_plugin_devices;
static std::vector<std::string> difftest_htif_args;
static std::vector<std::pair<reg_t, mem_t*>> difftest_mem(
    1, std::make_pair(reg_t(DRAM_BASE), new mem_t(CONFIG_MSIZE)));
static debug_module_config_t difftest_dm_config = {
  .progbufsize = 2,
  .max_sba_data_width = 0,
  .require_authentication = false,
  .abstract_rti = 0,
  .support_hasel = true,
  .support_abstract_csr_access = true,
  .support_abstract_fpr_access = true,
  .support_haltgroups = true,
  .support_impebreak = true
};

using diff_context_t = riscv32_difftest_state_t;

static sim_t* s = NULL;
static processor_t *p = NULL;
static state_t *state = NULL;

static bool valid_privilege(uint32_t priv) {
  return priv == PRV_U || priv == PRV_S || priv == PRV_M;
}

[[noreturn]] static void reject_abi_value(const char *field, uint32_t value) {
  std::fprintf(stderr, "Invalid RV32 DiffTest %s value %u\n", field, value);
  std::abort();
}

void sim_t::diff_init(int port) {
  p = get_core("0");
  state = p->get_state();
}

void sim_t::diff_step(uint64_t n) {
  step(n);
}

void sim_t::diff_get_regs(void *diff_context) {
  assert(diff_context != nullptr);
  auto &ctx = *static_cast<diff_context_t *>(diff_context);
  for (size_t i = 0; i < RISCV32_DIFFTEST_GPR_COUNT; i++) {
    ctx.gpr[i] = static_cast<uint32_t>(state->XPR[i]);
  }
  ctx.gpr[0] = 0;
  ctx.priv = static_cast<uint32_t>(state->prv);
  ctx.mcause = static_cast<uint32_t>(state->mcause->read());
  ctx.mstatus = static_cast<uint32_t>(state->mstatus->read());
  ctx.mepc = static_cast<uint32_t>(state->mepc->read());
  ctx.mtvec = static_cast<uint32_t>(state->mtvec->read());
  ctx.pc = static_cast<uint32_t>(state->pc);
}

void sim_t::diff_set_regs(void *diff_context) {
  assert(diff_context != nullptr);
  const auto &ctx = *static_cast<const diff_context_t *>(diff_context);
  if (!valid_privilege(ctx.priv)) {
    reject_abi_value("privilege", ctx.priv);
  }
  for (size_t i = 0; i < RISCV32_DIFFTEST_GPR_COUNT; i++) {
    state->XPR.write(i, static_cast<sword_t>(ctx.gpr[i]));
  }
  state->mcause->write(static_cast<reg_t>(ctx.mcause));
  state->mstatus->write(static_cast<reg_t>(ctx.mstatus));
  state->mepc->write(static_cast<reg_t>(ctx.mepc));
  state->mtvec->write(static_cast<reg_t>(ctx.mtvec));
  state->pc = static_cast<reg_t>(ctx.pc);
  p->set_privilege(static_cast<reg_t>(ctx.priv));
}

void sim_t::diff_memcpy(reg_t dest, void* src, size_t n) {
  mmu_t* mmu = p->get_mmu();
  for (size_t i = 0; i < n; i++) {
    mmu->store<uint8_t>(dest+i, *((uint8_t*)src+i));
  }
}

extern "C" {

__EXPORT uint32_t difftest_get_abi_version(void) {
  return RISCV32_DIFFTEST_ABI_VERSION;
}

__EXPORT uint32_t difftest_get_state_size(void) {
  return sizeof(riscv32_difftest_state_t);
}

__EXPORT void difftest_memcpy(paddr_t addr, void *buf, size_t n, bool direction) {
  if (direction == DIFFTEST_TO_REF) {
    s->diff_memcpy(addr, buf, n);
  } else {
    assert(0);
  }
}

__EXPORT void difftest_regcpy(riscv32_difftest_state_t *dut,
                              uint32_t direction) {
  assert(dut != nullptr);
  if (direction == DIFFTEST_TO_REF) {
    s->diff_set_regs(dut);
  } else if (direction == DIFFTEST_TO_DUT) {
    s->diff_get_regs(dut);
  } else {
    reject_abi_value("direction", direction);
  }
}

__EXPORT void difftest_exec(uint64_t n) {
  s->diff_step(n);
}

__EXPORT void difftest_init(int port) {
  difftest_htif_args.push_back("");
  const char *isa = "RV32IMAFDC";
  cfg_t cfg(/*default_initrd_bounds=*/std::make_pair((reg_t)0, (reg_t)0),
            /*default_bootargs=*/nullptr,
            /*default_isa=*/isa,
            /*default_priv=*/DEFAULT_PRIV,
            /*default_varch=*/DEFAULT_VARCH,
            /*default_misaligned=*/false,
            /*default_endianness*/endianness_little,
            /*default_pmpregions=*/16,
            /*default_mem_layout=*/std::vector<mem_cfg_t>(),
            /*default_hartids=*/std::vector<size_t>(1),
            /*default_real_time_clint=*/false,
            /*default_trigger_count=*/4);
  s = new sim_t(&cfg, false,
      difftest_mem, difftest_plugin_devices, difftest_htif_args,
      difftest_dm_config, nullptr, false, NULL,
      false,
      NULL,
      true);
  s->diff_init(port);
}

__EXPORT void difftest_raise_intr(uint64_t NO) {
  trap_t t(NO);
  p->take_trap_public(t, state->pc);
}

}
