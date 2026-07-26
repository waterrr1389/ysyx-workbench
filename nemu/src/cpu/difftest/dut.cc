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
static int skip_dut_nr_inst = 0;

static void copy_state_to_ref(const CPU_state *state) {
  riscv32_difftest_state_t wire;
  isa_difftest_export_state(&wire, state);
  reference->set_state(wire);
}

static void copy_state_from_ref(CPU_state *state) {
  riscv32_difftest_state_t wire = reference->get_state();
  isa_difftest_import_state(state, &wire);
}

// this is used to let ref skip instructions which
// can not produce consistent behavior with NEMU
extern "C" void difftest_skip_ref() {
  is_skip_ref = true;
  // If such an instruction is one of the instruction packing in QEMU
  // (see below), we end the process of catching up with QEMU's pc to
  // keep the consistent behavior in our best.
  // Note that this is still not perfect: if the packed instructions
  // already write some memory, and the incoming instruction in NEMU
  // will load that memory, we will encounter false negative. But such
  // situation is infrequent.
  skip_dut_nr_inst = 0;
}

// this is used to deal with instruction packing in QEMU.
// Sometimes letting QEMU step once will execute multiple instructions.
// We should skip checking until NEMU's pc catches up with QEMU's pc.
// The semantic is
//   Let REF run `nr_ref` instructions first.
//   We expect that DUT will catch up with REF within `nr_dut` instructions.
extern "C" void difftest_skip_dut(int nr_ref, int nr_dut) {
  skip_dut_nr_inst += nr_dut;

  if (nr_ref > 0) {
    reference->execute(static_cast<uint64_t>(nr_ref));
  }
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

  if (skip_dut_nr_inst > 0) {
    copy_state_from_ref(&ref_r);
    if (ref_r.pc == npc) {
      skip_dut_nr_inst = 0;
      checkregs(&ref_r, npc);
      return;
    }
    skip_dut_nr_inst--;
    if (skip_dut_nr_inst == 0)
      panic("can not catch up with ref.pc = " FMT_WORD " at pc = " FMT_WORD, ref_r.pc, pc);
    return;
  }

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
