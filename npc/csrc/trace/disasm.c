#include "trace/disasm.h"

#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>

#include <capstone/capstone.h>

#define CAPSTONE_SO "/home/frisk/ysyx-workbench/nemu/tools/capstone/repo/libcapstone.so.5"

static size_t (*cs_disasm_dl)(csh handle, const uint8_t* code,
    size_t code_size, uint64_t address, size_t count, cs_insn** insn);
static void (*cs_free_dl)(cs_insn* insn, size_t count);

static csh handle;

void init_disasm(void) {
  void* dl_handle = dlopen(CAPSTONE_SO, RTLD_LAZY);
  assert(dl_handle != NULL);

  cs_err (*cs_open_dl)(cs_arch arch, cs_mode mode, csh* handlep) = NULL;
  cs_open_dl = (cs_err (*)(cs_arch, cs_mode, csh*))dlsym(dl_handle, "cs_open");
  assert(cs_open_dl != NULL);

  cs_disasm_dl = (size_t (*)(csh, const uint8_t*, size_t, uint64_t, size_t, cs_insn**))
      dlsym(dl_handle, "cs_disasm");
  assert(cs_disasm_dl != NULL);

  cs_free_dl = (void (*)(cs_insn*, size_t))dlsym(dl_handle, "cs_free");
  assert(cs_free_dl != NULL);

  int ret = cs_open_dl(CS_ARCH_RISCV, (cs_mode)(CS_MODE_RISCV32 | CS_MODE_RISCVC), &handle);
  assert(ret == CS_ERR_OK);
}

void disassemble(char* str, int size, uint64_t pc, const uint8_t* code, int nbyte) {
  cs_insn* insn = NULL;
  size_t count = cs_disasm_dl(handle, code, nbyte, pc, 0, &insn);
  assert(count == 1);

  int ret = snprintf(str, size, "%s", insn->mnemonic);
  if (insn->op_str[0] != '\0') {
    snprintf(str + ret, size - ret, "\t%s", insn->op_str);
  }
  cs_free_dl(insn, count);
}
