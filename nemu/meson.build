# NEMU, built from the configuration that `make menuconfig` writes.
#   meson setup build-nemu nemu        (from the workbench root)
#   ninja -C build-nemu
# Kconfig stays the only place options are chosen: `conf` turns .config into
# include/generated/autoconf.h for the C code, and this file reads the same
# .config to pick sources and flags. Editing .config reconfigures automatically.

project('nemu', 'c', 'cpp',
  meson_version: '>=1.12',
  default_options: [
    # Flags come from .config below, not from Meson's build types.
    'buildtype=plain',
    'warning_level=0',
    'b_staticpic=false',
    'b_pie=false',
    'b_asneeded=false',
  ],
)

fs = import('fs')
if not fs.exists('include/generated/autoconf.h')
  error('NEMU is not configured: run `make -C nemu menuconfig` (or a *_defconfig) first')
endif
cfg = import('keyval').load('.config')

# Kconfig strings keep their quotes in .config: CONFIG_ISA="riscv32".
isa    = cfg.get('CONFIG_ISA').strip('"')
engine = cfg.get('CONFIG_ENGINE').strip('"')

if isa != 'riscv32' or engine != 'interpreter' or not cfg.has_key('CONFIG_MODE_SYSTEM')
  error('the Meson build only covers riscv32, the interpreter engine and system mode')
endif

if cfg.has_key('CONFIG_TARGET_NATIVE_ELF')
  share = false
elif cfg.has_key('CONFIG_TARGET_SHARE')
  share = true
else
  error('the Meson build supports the native-ELF and shared-library targets, not AM')
endif

## Compiler: chosen when the build directory is set up, so it must match .config

cc = meson.get_compiler('c')
if cfg.has_key('CONFIG_CC_CLANG')
  want_cc = 'clang'
elif cfg.has_key('CONFIG_CC_GCC')
  want_cc = 'gcc'
else
  error('.config selects g++ for C files; the Meson build supports gcc and clang')
endif
if cc.get_id() != want_cc
  error('.config selects @0@ but this build directory uses @1@; reconfigure with\n'.format(want_cc, cc.get_id())
    + '  CC="ccache @0@" CXX="ccache @1@" meson setup --wipe <builddir> nemu'.format(want_cc, want_cc == 'clang' ? 'clang++' : 'g++'))
endif

## Flags

build_args = [cfg.get('CONFIG_CC_OPT').strip('"')]
if cfg.has_key('CONFIG_CC_LTO')
  build_args += '-flto'
endif
if cfg.has_key('CONFIG_CC_DEBUG')
  build_args += ['-Og', '-ggdb3']
endif
if cfg.has_key('CONFIG_CC_ASAN')
  build_args += '-fsanitize=address'
endif

itrace_cond = cfg.get('CONFIG_ITRACE_COND', 'true').strip('"')

nemu_args = ['-O2', '-Wall', '-Werror'] + build_args + [
  '-DITRACE_COND=' + itrace_cond,
  '-D__GUEST_ISA__=' + isa,
]
link_args = ['-O2'] + build_args

# Meson defines _GLIBCXX_ASSERTIONS whenever b_ndebug is off; the Makefile build
# did not. b_ndebug=true is no fix: its -DNDEBUG would turn NEMU's assert()s off.
cpp_only_args = ['-U_GLIBCXX_ASSERTIONS']

inc = ['include', 'src/engine' / engine, 'src/isa' / isa / 'include']

if share
  # Loaded by a DUT through dlopen(); only the difftest_* API is exported.
  nemu_args += ['-fPIC', '-fvisibility=hidden']
endif

## Sources: what each removed filelist.mk selected, spelled out

srcs = files(
  'src/nemu-main.c',
  'src/cpu/cpu-exec.c',
  'src/cpu/difftest/dut.cc',
  'src/cpu/difftest/ref.c',
  'src/memory/paddr.c',
  'src/memory/vaddr.c',
  'src/monitor/monitor.c',
  'src/monitor/sdb/callstack.c',
  'src/monitor/sdb/expr.c',
  'src/monitor/sdb/ftrace.c',
  'src/monitor/sdb/iRngBuffer.c',
  'src/monitor/sdb/sdb.c',
  'src/monitor/sdb/watchpoint.c',
  'src/utils/log.c',
  'src/utils/state.c',
  'src/utils/timer.c',
  'src/device/io/map.c',
  'src/device/io/mmio.c',
  'src/device/io/port-io.c',
  'src/engine/interpreter/hostcall.c',
  'src/engine/interpreter/init.c',
  'src/isa/riscv32/difftest/dut.c',
  'src/isa/riscv32/difftest/state.c',
  'src/isa/riscv32/init.c',
  'src/isa/riscv32/logo.c',
  'src/isa/riscv32/reg.c',
  'src/isa/riscv32/system/intr.c',
  'src/isa/riscv32/system/mmu.c',
)

if cfg.has_key('CONFIG_RISCV_DECODER_HIERARCHICAL')
  srcs += files('src/isa/riscv32/inst-hierarchical.cc')
else
  srcs += files('src/isa/riscv32/inst.c')
endif

if cfg.has_key('CONFIG_DIFFTEST')
  srcs += files('tools/difftest-client/reference.cc')
endif

deps = []

if cfg.has_key('CONFIG_DEVICE')
  srcs += files('src/device/device.c', 'src/device/alarm.c', 'src/device/intr.c')
  # Link only: the Makefile never passed SDL's cflags (-D_GNU_SOURCE etc.).
  deps += dependency('sdl2').partial_dependency(links: true, link_args: true)
endif
foreach dev : [['HAS_SERIAL', 'serial'], ['HAS_TIMER', 'timer'],
               ['HAS_KEYBOARD', 'keyboard'], ['HAS_VGA', 'vga'],
               ['HAS_AUDIO', 'audio'], ['HAS_DISK', 'disk'],
               ['HAS_SDCARD', 'sdcard']]
  if cfg.has_key('CONFIG_' + dev[0])
    srcs += files('src/device' / dev[1] + '.c')
  endif
endforeach

if cfg.has_key('CONFIG_ITRACE') or cfg.has_key('CONFIG_IQUEUE')
  # disasm.c dlopen()s tools/capstone/repo/libcapstone.so.5 relative to the
  # working directory, so NEMU must run from nemu/ when itrace is on.
  if not fs.exists('tools/capstone/repo/include/capstone/capstone.h')
    error('itrace needs capstone: run `make -C nemu/tools/capstone` first')
  endif
  srcs += files('src/utils/disasm.c')
  inc += 'tools/capstone/repo/include'
endif

## Target

name = '@0@-nemu-@1@'.format(isa, engine)

if share
  # riscv32-nemu-interpreter.so; the Makefile named it ...-interpreter-so.
  nemu = shared_module(name, srcs,
    name_prefix: '',
    c_args: nemu_args,
    cpp_args: nemu_args + cpp_only_args,
    link_args: link_args,
    include_directories: inc,
    dependencies: deps,
    implicit_include_directories: false,
  )
else
  nemu = executable(name, srcs,
    c_args: nemu_args,
    cpp_args: nemu_args + cpp_only_args,
    link_args: link_args + ['-lreadline', '-ldl'],
    include_directories: inc,
    dependencies: deps,
    pie: true,
    implicit_include_directories: false,
  )
endif

## Course tracing: commit to tracer-ysyx after every build, like `make -C nemu`

root = meson.project_source_root() / '..'
custom_target('tracer-compile-nemu',
  output: 'tracer-compile-nemu.stamp',
  command: ['flock', root / '.git', 'make', '-s', '-C', root, '.git_commit',
            'MSG=compile NEMU'],
  env: {'NEMU_HOME': meson.project_source_root()},
  depends: nemu,
  build_always_stale: true,
  build_by_default: true,
)
