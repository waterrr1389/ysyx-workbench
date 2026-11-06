# NPC: the Verilator model of the core plus its C++ harness.
#   meson setup build-npc npc                                (from the workbench root)
#   meson setup build-npc-diff npc -Ddifftest=true
#   ninja -C build-npc
# Each build directory is one configuration, so models built with different
# options live side by side. Options are listed in meson.options.

project('npc', meson_version: '>=1.12')

verilator = find_program('verilator')
workbench = meson.project_source_root() / '..'

## npc_config.h: the configuration as C macros, read through include/base/config.h

conf = configuration_data()
conf.set10('NPC_ITRACE', get_option('itrace'))
conf.set10('NPC_FTRACE', get_option('ftrace'))
conf.set10('NPC_MTRACE', get_option('mtrace'))
conf.set10('NPC_DIFFTEST', get_option('difftest'))
conf.set('NPC_NEED_INST_TRACE', '(NPC_ITRACE || NPC_FTRACE)')
config_h = configure_file(output: 'npc_config.h', configuration: conf)

## Sources

# npc_pkg.sv first: the package must be compiled before the modules that import it.
vsrcs = files(
  'vsrc/npc_pkg.sv',
  'vsrc/sim_observer.sv',
  'vsrc/Arbiter.sv',
  'vsrc/EXU.sv',
  'vsrc/IDU.sv',
  'vsrc/IFU.sv',
  'vsrc/LSU.sv',
  'vsrc/RegFile.sv',
  'vsrc/SRAM.sv',
  'vsrc/top.sv',
  'vsrc/UART.sv',
  'vsrc/WBU.sv',
  'vsrc/Xbar.sv',
)

csrcs = files(
  'csrc/difftest/difftest.cc',
  'csrc/dpi-c.cpp',
  'csrc/cpu_state.cpp',
  'csrc/pmem.cpp',
  'csrc/sdb.c',
  'csrc/sim_main.cpp',
  'csrc/trace/callstack.c',
  'csrc/trace/disasm.c',
  'csrc/trace/ftrace.c',
  'csrc/trace/iRingBuffer.c',
  '../nemu/tools/difftest-client/reference.cc',
)

# Headers are not on the Verilator command line; listing them makes an edit
# to one of them rebuild the model.
headers = files(
  'include/base/common.h',
  'include/base/config.h',
  'include/base/debug.h',
  'include/base/utils.h',
  'include/difftest/difftest.h',
  'include/sim/dpi-c.h',
  'include/sim/cpu_state.h',
  'include/sim/pmem.h',
  'include/sim/sdb.h',
  'include/sim/sim_main.h',
  'include/trace/callstack.h',
  'include/trace/disasm.h',
  'include/trace/ftrace.h',
  'include/trace/iRingBuffer.h',
  'include/trace/riscv_decode.h',
  # Shared with NEMU through the DiffTest client (reference.cc, difftest.cc).
  '../nemu/include/difftest/reference.hpp',
  '../nemu/include/difftest/arch/riscv32.h',
)

## The model: Verilator generates the C++ and compiles it with its own make

# The DiffTest reference: NEMU built as a shared library (see nemu/meson.build).
ref_so = workbench / get_option('nemu_so')

harness_args = [
  '-Wall', '-Werror', '-Wno-unused-function', '-ggdb3',
  # Verilator writes -CFLAGS into its generated makefile, where the shell strips
  # the single quotes and the compiler sees the string literal. (Meson rewrites
  # backslashes in commands, so the Makefile's \"...\" cannot be used here.)
  '-DREF_SO_FILE=\'"@0@"\''.format(ref_so),
  '-I' + meson.project_source_root() / 'include',
  '-I' + workbench / 'nemu/include',
  '-I' + meson.current_build_dir(),
]

cflags = []
foreach a : harness_args
  cflags += ['-CFLAGS', a]
endforeach

vtop = custom_target('Vtop',
  input: [vsrcs, csrcs],
  output: 'Vtop',
  depend_files: [headers, config_h],
  command: [verilator, '--trace-fst', '-cc', '--exe', '--build', '-j', '0',
            '--top-module', 'top', '--autoflush', '+define+NPC_SIM',
            '--Mdir', meson.current_build_dir() / 'obj',
            # -o is relative to --Mdir; the model goes next to obj/, where Meson expects it.
            '-o', '../Vtop',
            '-I' + meson.project_source_root() / 'vsrc',
            '-MAKEFLAGS', '--no-print-directory -s',
            cflags, '-LDFLAGS', '-lreadline',
            '@INPUT@'],
  console: true,
  build_by_default: true,
)

## Course tracing: commit to tracer-ysyx after every model build, like `make sim`

custom_target('tracer-sim-rtl',
  output: 'tracer-sim-rtl.stamp',
  command: ['flock', workbench / '.git', 'make', '-s', '-C', workbench, '.git_commit',
            'MSG=sim RTL'],
  env: {'NEMU_HOME': workbench / 'nemu'},
  depends: vtop,
  build_always_stale: true,
  build_by_default: true,
)

## Helpers

# Style checks are off in the model build; run on demand.
run_target('lint', command: [verilator, '--lint-only', '-Wall', '-Wno-PINCONNECTEMPTY',
  '--top-module', 'top', '-I' + meson.project_source_root() / 'vsrc', vsrcs])
