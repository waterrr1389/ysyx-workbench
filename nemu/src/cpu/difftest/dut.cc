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

#include <difftest/reference.hpp>

extern "C" {
#include <cpu/cpu.h>
#include <difftest-def.h>
#include <isa.h>
#include <memory/paddr.h>
#include <utils.h>
}

#include <memory>

#ifdef CONFIG_DIFFTEST

static std::unique_ptr<difftest::Riscv32DifftestReference> reference;
static bool is_skip_ref = false;

static void copy_state_to_ref(const CPU_state *state) {
  riscv32_difftest_state_t wire;
  isa_difftest_export_state(&wire, state);
  reference->set_state(wire);
}

// Lets the reference skip an instruction whose effect it cannot reproduce (device access).
extern "C" void difftest_skip_ref() {
  is_skip_ref = true;
}

extern "C" void init_difftest(char *ref_so_file, long img_size, int port) {
  assert(ref_so_file != NULL);

  reference.reset(new difftest::Riscv32DifftestReference(ref_so_file));

  Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
  Log("The result of every instruction will be compared with %s. "
      "This will help you a lot for debugging, but also significantly reduce the performance. "
      "If it is not necessary, you can turn it off in menuconfig.",
      ref_so_file);

  riscv32_difftest_state_t initial_state;
  isa_difftest_export_state(&initial_state, &cpu);
  reference->initialize(port, RESET_VECTOR, guest_to_host(RESET_VECTOR), img_size, initial_state);
}

static void checkregs(CPU_state *ref, vaddr_t pc) {
  if (!isa_difftest_checkregs(ref, pc)) {
    nemu_state.state = NEMU_ABORT;
    nemu_state.halt_pc = pc;
    isa_reg_display();
  }
}

extern "C" void difftest_step(vaddr_t pc, vaddr_t npc) {
  CPU_state ref_r;

  if (is_skip_ref) {
    // to skip the checking of an instruction, just copy the reg state to reference design
    copy_state_to_ref(&cpu);
    is_skip_ref = false;
    return;
  }

  riscv32_difftest_state_t wire = reference->step();
  isa_difftest_import_state(&ref_r, &wire);

  checkregs(&ref_r, pc);
}
#else
extern "C" void init_difftest(char *ref_so_file, long img_size, int port) {}
#endif
